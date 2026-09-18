; backlot-64: the probe, the engine's instrumentation path.
;
; A probe build (assembled with -DB64_PROFILE) records into a fixed 2 KB
; block at $F800 that a host reads back without stopping the program:
; from VICE through the remote monitor, from a C64 Ultimate through its
; REST interface (GET /v1/machine:readmem).  tools/b64probe.py decodes
; both.  Without the define every hook is empty and nothing is resident.
;
; What it records:
;   events    (tag, frame, raster line) at every FTRACE point: the order of
;             work within a frame, for finding stalls
;   samples   at every vertical blank, the interrupted program counter and,
;             when the VM was running, the thread and its script offset: a
;             50 Hz statistical profile of the engine and of the scripts
;   opcodes   a 16-bit count per VM opcode: the opcode mix
;   tick      cycles of the last game callback, the worst, and a histogram
;             in 1,024-cycle buckets, from the CIA2 timers
;
; Sample layout: pcl, pch, vm (0 = not in the VM, else thread+1), script
; offset hi, script offset lo.
; The block is the game's hot-state region's top 2 KB; a probe build is a
; debug build and a game that uses $F800-$FFF9 cannot be probed.  The
; sampling idea and the per-frame histogram are after Honza Slesinger,
; DOOM C64U (src/instrument.asm, src/clock.asm).  Changed: samples carry
; the VM thread and script offset, so the same run profiles the p-code.

.include "b64.inc"

.ifdef B64_PROFILE

.export probe_event
.export probe_sample
.export probe_tick_begin
.export probe_tick_end
.export probe_init
.export probe_vm_active
.export probe_opcount_lo
.export probe_opcount_hi

.import vm_cur

; --- the block
PROBE           = $F800
P_MAGIC         = PROBE+0       ; "B64P"
P_VERSION       = PROBE+4       ; 1
P_PLAT          = PROBE+5       ; b64_plat
P_REUMB         = PROBE+6
P_FRAME         = PROBE+7       ; frame counter at the last sample
P_EVIDX         = PROBE+8       ; event ring write index, 16-bit, counts entries
P_SMIDX         = PROBE+10      ; sample ring write index, 16-bit
P_TICK_LAST     = PROBE+12      ; 3 bytes
P_TICK_MAX      = PROBE+15      ; 3 bytes
P_HIST          = PROBE+32      ; 16 x 16-bit buckets of 1,024 cycles
P_EVENTS        = PROBE+64      ; 160 x 3 bytes
P_NEV           = 160
P_SAMPLES       = PROBE+64+480  ; 128 x 5 bytes: pcl, pch, vm (0 none, 1+thread), pch, pcl
P_NSM           = 128
P_OPLO          = PROBE+64+480+640      ; 128 counters, low bytes (indexed by the doubled opcode)
P_OPHI          = P_OPLO+128
; end at PROBE+1440

.segment "LOWRAM"
probe_vm_active: .res 1         ; 1 while the VM is executing a thread
probe_tmp:      .res 2

.segment "CODE"

probe_init:
        ldx #0
        txa
@clr:   sta PROBE,x
        sta PROBE+$100,x
        sta PROBE+$200,x
        sta PROBE+$300,x
        sta PROBE+$400,x
        sta PROBE+$500,x
        inx
        bne @clr
        lda #'B'
        sta P_MAGIC
        lda #'6'
        sta P_MAGIC+1
        lda #'4'
        sta P_MAGIC+2
        lda #'P'
        sta P_MAGIC+3
        lda #1
        sta P_VERSION
        lda b64_plat
        sta P_PLAT
        lda b64_reu_mb
        sta P_REUMB
        lda #0
        sta probe_vm_active
        ; the sampler: CIA1 timer B every 4,093 cycles (a prime, so the
        ; samples sweep every phase of the frame), continuous, with its
        ; interrupt enabled.  The dispatcher answers it before the raster.
        lda #<4093
        sta CIA1_TB
        lda #>4093
        sta CIA1_TB+1
        lda #%00010001          ; force load, continuous, start
        sta CIA1_CRB
        lda #%10000010          ; enable timer B interrupt
        sta CIA1_ICR
        rts

; probe_event: A = tag.  Preserves A, X, Y.  Safe from the interrupt and
; the main loop (the index update runs with interrupts off).
probe_event:
        php
        sei
        sta probe_tmp
        txa
        pha
        tya
        pha
        ; entry pointer = P_EVENTS + (index mod 160) * 3
        lda P_EVIDX
        sec
@mod:   sbc #P_NEV
        bcs @mod
        adc #P_NEV
        sta probe_tmp+1
        lda #0
        sta b64_tmp+7
        lda probe_tmp+1
        asl
        rol b64_tmp+7
        clc
        adc probe_tmp+1
        bcc :+
        inc b64_tmp+7
:       clc
        adc #<P_EVENTS
        sta b64_tmp+6
        lda b64_tmp+7
        adc #>P_EVENTS
        sta b64_tmp+7
        ldy #0
        lda probe_tmp
        sta (b64_tmp+6),y
        iny
        lda b64_frame
        sta (b64_tmp+6),y
        iny
        lda VIC_HLINE
        sta (b64_tmp+6),y
        inc P_EVIDX
        bne :+
        inc P_EVIDX+1
:       pla
        tay
        pla
        tax
        lda probe_tmp
        plp
        rts

; probe_sample: from the interrupt dispatcher after its pushes (the timer
; path).  The interrupted PC is on the stack above Y, X, A and P.
probe_sample:
        lda b64_frame
        sta P_FRAME
        lda P_SMIDX
        and #P_NSM-1
        sta probe_tmp
        lda #0
        sta b64_tmp+7
        lda probe_tmp
        asl
        rol b64_tmp+7
        asl
        rol b64_tmp+7
        clc
        adc probe_tmp
        sta b64_tmp+6
        bcc :+
        inc b64_tmp+7
:       lda b64_tmp+6
        clc
        adc #<P_SAMPLES
        sta b64_tmp+6
        lda b64_tmp+7
        adc #>P_SAMPLES
        sta b64_tmp+7
        ; the interrupted PC: stack layout from the interrupt's pushes
        tsx
        lda $0107,x             ; PCL: S+1,2 return, S+3 Y, S+4 X, S+5 A, S+6 P, S+7 PCL, S+8 PCH
        ldy #0
        sta (b64_tmp+6),y
        lda $0108,x             ; PCH
        iny
        sta (b64_tmp+6),y
        lda probe_vm_active
        beq @novm
        lda vm_cur
        clc
        adc #1
        iny
        sta (b64_tmp+6),y
        lda vm_pch
        iny
        sta (b64_tmp+6),y
        lda $0103,x             ; Y at the interrupt = script offset lo
        iny
        sta (b64_tmp+6),y
        jmp @done
@novm:  lda #0
        iny
        sta (b64_tmp+6),y
        iny
        sta (b64_tmp+6),y
        iny
        sta (b64_tmp+6),y
@done:  inc P_SMIDX
        bne :+
        inc P_SMIDX+1
:       rts

; probe_tick_begin / end: time the game callback with the CIA2 timers
probe_tick_begin:
        jmp b64_bench_begin
probe_tick_end:
        jsr b64_bench_end       ; b64_val = cycles
        lda b64_val
        sta P_TICK_LAST
        lda b64_val+1
        sta P_TICK_LAST+1
        lda b64_val+2
        sta P_TICK_LAST+2
        ; max
        lda b64_val+2
        cmp P_TICK_MAX+2
        bcc @hist
        bne @set
        lda b64_val+1
        cmp P_TICK_MAX+1
        bcc @hist
        bne @set
        lda b64_val
        cmp P_TICK_MAX
        bcc @hist
@set:   lda b64_val
        sta P_TICK_MAX
        lda b64_val+1
        sta P_TICK_MAX+1
        lda b64_val+2
        sta P_TICK_MAX+2
@hist:  ; bucket = cycles / 1024, capped at 15
        lda b64_val+2
        bne @top
        lda b64_val+1
        lsr
        lsr
        cmp #15
        bcc :+
@top:   lda #15
:       asl
        tax
        inc P_HIST,x
        bne :+
        inc P_HIST+1,x
:       rts

probe_opcount_lo = P_OPLO
probe_opcount_hi = P_OPHI

.endif
