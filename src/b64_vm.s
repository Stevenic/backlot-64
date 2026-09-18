; backlot-64: the VM.  Byte-code threads with 16-bit variables, timers,
; branches, table lookups and a syscall bridge to the engine's primitives.
; Everything a scene or a mission decides is p-code; the engine only
; supplies the per-frame work the p-code asks for.
;
; Scripts live in the REU and run through the page cache.  A thread's
; position is a 16-bit offset from the script base (vm_pch:vm_pc); vm_page
; points at the cached copy of the page the offset is in, so an operand
; fetch is one indirect load with Y as the offset's low byte.  Instructions
; are at most 9 bytes, so when an instruction starts within 9 bytes of the
; end of a page its bytes are copied into a small buffer that spans the
; boundary; for that one instruction vm_page points at the buffer, Y counts
; from 0, and the start offset is added back when the instruction ends.
;
; Convention inside an op: Y = offset lo, past the opcode.  Read operands
; with FETCH.  Ops that need Y for something else save it with sty vm_pc
; and reload it before jumping to vm_next.  An op ends with jmp vm_next,
; or with jmp vm_yield to give the frame up.

.include "b64.inc"

.import shim_on

.export b64_vm_start
.export b64_vm_tick
.export vm_budget_max

VM_THREADS      = 8
VM_VARS         = 32
VM_T            = 32            ; hidden variable: the immediate of every xxxI opcode
VM_EDGE         = 243           ; an instruction starting at or past this offset spans the page
VM_IBUF         = 13            ; longest instruction (PCM)

.macro FETCH
        lda (vm_page),y
        iny
.endmacro

.segment "LOWRAM"
vm_lo:          .res VM_VARS+1
vm_hi:          .res VM_VARS+1
th_on:          .res VM_THREADS
th_pclo:        .res VM_THREADS
th_pchi:        .res VM_THREADS
th_wait:        .res VM_THREADS
th_sp:          .res VM_THREADS ; 0, 2, 4
th_stk:         .res VM_THREADS*4
vm_base:        .res 3          ; REU address of the script
vm_cur:         .res 1
vm_budget:      .res 1
vm_budget_max:  .res 1
vm_slow:        .res 1          ; 1 while vm_page points at the boundary buffer
vm_slowbase:    .res 1          ; offset lo where the buffered instruction starts
vm_x:           .res 1
vm_ibuf:        .res VM_IBUF
vm_line:        .res 41         ; TEXT copies its string here

.segment "CODE"

; b64_vm_start: b64_reu = script base, A/X = entry offset lo/hi.  Every
; thread stops; thread 0 starts at the entry.
b64_vm_start:
        sta th_pclo
        stx th_pchi
.ifdef VM_TRACE
        lda #0
        sta $E0FF
.endif
        lda b64_reu
        sta vm_base
        lda b64_reu+1
        sta vm_base+1
        lda b64_reu+2
        sta vm_base+2
        ldx #VM_THREADS-1
        lda #0
@clear: sta th_on,x
        sta th_wait,x
        sta th_sp,x
        dex
        bpl @clear
        lda #1
        sta th_on
        rts

; b64_vm_tick: once per frame.  Sleeping threads count down; ready threads
; run until they yield, wait, end, or spend the budget.
b64_vm_tick:
        jsr b64_spr_begin
        ldx #0
@thread:
        stx vm_cur
        lda th_on,x
        beq @next
        lda th_wait,x
        beq @run
        dec th_wait,x
        jmp @next
@run:   lda th_pclo,x
        sta vm_pc
        lda th_pchi,x
        sta vm_pch
        jsr vm_resolve
        lda vm_budget_max       ; set by the platform probe: 64 at 1 MHz, 255 with turbo
        sta vm_budget
        jsr vm_run
        ldx vm_cur
        lda vm_pc
        sta th_pclo,x
        lda vm_pch
        sta th_pchi,x
@next:  ldx vm_cur
        inx
        cpx #VM_THREADS
        bcc @thread
        jmp b64_spr_end

; ---------------------------------------------------------------------------
; the dispatch loop

; vm_run: execute from vm_pch:vm_pc until an op returns (yield, end, budget)
vm_run:
        ldy vm_pc
        jmp vm_exec

; vm_next: an op has finished with Y = offset lo
vm_next:
        sty vm_pc
        lda vm_slow
        beq vmn_chk
        jsr vm_sync             ; leave the boundary buffer, page forward if we crossed
        ldy vm_pc
vmn_chk:   dec vm_budget
        beq vme_out
vm_exec:
        cpy #VM_EDGE
        bcs vme_edge
vme_go:
.ifdef VM_TRACE
        ; debug: ring of (thread, offset hi, offset lo) at $E100, index at $E0FF
        sty vm_x
        ldx $E0FF
        cpx #$FF
        beq @nt
        lda vm_cur
        sta $E100,x
        lda vm_pch
        sta $E200,x
        tya
        sta $E300,x
        inc $E0FF
@nt:    ldy vm_x
.endif
        FETCH
        cmp #VM_OP_COUNT
        bcs vme_bad
        tax
        lda vm_ophi,x
        pha
        lda vm_oplo,x
        pha
        rts                     ; into the op, Y = first operand
vme_bad:   jmp op_end
vme_out:   rts
vme_edge:  jsr vm_boundary
        jmp vme_go

; vm_yield: give the frame up with Y = offset lo
vm_yield:
        sty vm_pc
        lda vm_slow
        beq :+
        jsr vm_sync
:       rts

; vm_resolve: vm_page = the cached page holding offset vm_pch; clears slow
vm_resolve:
        lda vm_base+1
        clc
        adc vm_pch
        tay
        lda vm_base+2
        adc #0
        tax
        tya
        jsr b64_page_get
        sta vm_page+1
        lda #0
        sta vm_page
        sta vm_slow
        rts

; vm_sync: vm_pc holds the bytes consumed (from the buffer) or the offset
; lo (from a page); make it the offset lo, carry into vm_pch, and point
; vm_page at the real page.  Clears slow.
vm_sync:
        lda vm_slow
        beq vm_resolve
        lda #0
        sta vm_slow
        lda vm_slowbase
        clc
        adc vm_pc
        sta vm_pc
        bcc vm_resolve
        inc vm_pch
        jmp vm_resolve

; vm_boundary: Y = offset lo >= VM_EDGE.  Copy the next VM_IBUF bytes,
; across the page end, into vm_ibuf; point vm_page at it with Y = 0.
vm_boundary:
        sty vm_pc
        sty vm_slowbase
        ldx #0
@copy:  lda (vm_page),y
        sta vm_ibuf,x
        inx
        cpx #VM_IBUF
        beq @done
        iny
        bne @copy
        ; on to the next page for the rest (vm_resolve clobbers X and Y)
        stx vm_x
        inc vm_pch
        jsr vm_resolve
        dec vm_pch
        ldx vm_x
        ldy #0
        jmp @copy
@done:  lda #<vm_ibuf
        sta vm_page
        lda #>vm_ibuf
        sta vm_page+1
        lda #1
        sta vm_slow
        ldy #0
        rts

; vm_setpc: A/X = new offset lo/hi.  A jump within the current page keeps
; vm_page; any other resolves it.
vm_setpc:
        sta vm_pc
        cpx vm_pch
        bne @far
        ldy vm_slow
        bne @far
        ldy vm_pc
        jmp vm_next
@far:   stx vm_pch
        jsr vm_resolve
        ldy vm_pc
        jmp vm_next

; vm_getc: A = the byte at the offset, offset += 1, any page crossing
; handled.  For strings; requires vm_slow = 0.  Test A, not the flags.
vm_getc:
        ldy vm_pc
        lda (vm_page),y
        inc vm_pc
        bne :+
        pha
        txa
        pha
        inc vm_pch
        jsr vm_resolve          ; clobbers X and Y
        pla
        tax
        pla
:       rts

; ---------------------------------------------------------------------------
; control
op_end:
        ldx vm_cur
        lda #0
        sta th_on,x
        jmp vm_yield
op_yield:
        jmp vm_yield
op_wait:
        FETCH
        ldx vm_cur
        sta th_wait,x
        jmp vm_yield
op_jmp:
        FETCH
        sta b64_tmp
        FETCH
        tax
        lda b64_tmp
        jmp vm_setpc
op_spawn:
        FETCH
        sta b64_val
        FETCH
        sta b64_val+1
        ldx #1
@find:  lda th_on,x
        beq @got
        inx
        cpx #VM_THREADS
        bcc @find
        jmp vm_next             ; no free thread: dropped
@got:   lda b64_val
        sta th_pclo,x
        lda b64_val+1
        sta th_pchi,x
        lda #0
        sta th_wait,x
        sta th_sp,x
        lda #1
        sta th_on,x
        jmp vm_next
op_call:
        FETCH
        sta b64_val
        FETCH
        sta b64_val+1
        ; the return offset: Y past the operands, plus the start offset if
        ; this instruction ran from the boundary buffer
        ldx vm_pch
        lda vm_slow
        beq :+
        tya
        clc
        adc vm_slowbase
        tay
        bcc :+
        inx
:       stx b64_tmp             ; return hi
        sty b64_tmp+1           ; return lo
        ldx vm_cur
        lda th_sp,x
        cmp #4
        bcs @go                 ; too deep: jump without a return
        jsr stack_index
        lda b64_tmp+1           ; the saved offset lo
        sta th_stk,y
        lda b64_tmp
        sta th_stk+1,y
        inc th_sp,x
        inc th_sp,x
@go:    lda b64_val
        ldx b64_val+1
        jmp vm_setpc
op_ret:
        ldx vm_cur
        lda th_sp,x
        beq @none
        dec th_sp,x
        dec th_sp,x
        jsr stack_index
        lda th_stk,y
        ldx th_stk+1,y
        jmp vm_setpc
@none:  jmp vm_next
; stack_index: X = thread -> Y = thread*4 + sp
stack_index:
        txa
        asl
        asl
        clc
        adc th_sp,x
        tay
        rts
op_loop:
        FETCH
        tax
        lda vm_lo,x
        bne :+
        dec vm_hi,x
:       dec vm_lo,x
        lda vm_lo,x
        ora vm_hi,x
        beq skip2
take:   FETCH
        sta b64_tmp
        FETCH
        tax
        lda b64_tmp
        jmp vm_setpc
skip2:  iny
        iny
        jmp vm_next

; ---------------------------------------------------------------------------
; data.  Register forms take X = v, Y = w with the offset saved in vm_pc;
; immediate forms load the hidden variable T and share the register code.

; vw: v -> vm_x, w -> Y, X = v; the offset is saved
.macro VW
        FETCH
        sta vm_x
        FETCH
        sty vm_pc
        tay
        ldx vm_x
.endmacro
; VI: v -> X, imm -> T, Y = T; the offset is saved
.macro VI
        FETCH
        sta vm_x
        FETCH
        sta vm_lo+VM_T
        FETCH
        sta vm_hi+VM_T
        sty vm_pc
        ldx vm_x
        ldy #VM_T
.endmacro

op_ldi:
        VI
mov_xy: lda vm_lo,y
        sta vm_lo,x
        lda vm_hi,y
        sta vm_hi,x
back:   ldy vm_pc
        jmp vm_next
op_mov:
        VW
        jmp mov_xy
op_addi:
        VI
        jmp add_xy
op_add:
        VW
add_xy: clc
        lda vm_lo,x
        adc vm_lo,y
        sta vm_lo,x
        lda vm_hi,x
        adc vm_hi,y
        sta vm_hi,x
        jmp back
op_subi:
        VI
        jmp sub_xy
op_sub:
        VW
sub_xy: sec
        lda vm_lo,x
        sbc vm_lo,y
        sta vm_lo,x
        lda vm_hi,x
        sbc vm_hi,y
        sta vm_hi,x
        jmp back
op_andi:
        VI
        jmp and_xy
op_and:
        VW
and_xy: lda vm_lo,x
        and vm_lo,y
        sta vm_lo,x
        lda vm_hi,x
        and vm_hi,y
        sta vm_hi,x
        jmp back
op_mini:
        VI
        jmp min_xy
op_min:
        VW
min_xy: jsr cmp_xy
        bcc @keep
        jmp mov_xy              ; v >= w: v = w
@keep:  jmp back
op_maxi:
        VI
        jmp max_xy
op_max:
        VW
max_xy: jsr cmp_xy
        bcs @keep
        jmp mov_xy              ; v < w: v = w
@keep:  jmp back
op_shr:
        VW
        cpy #0
        bne @l
        jmp back
@l:     lsr vm_hi,x
        ror vm_lo,x
        dey
        bne @l
        jmp back
op_shl:
        VW
        cpy #0
        bne @l
        jmp back
@l:     asl vm_lo,x
        rol vm_hi,x
        dey
        bne @l
        jmp back
; cmp_xy: C = (v >= w), Z = (v == w), unsigned 16-bit
cmp_xy: lda vm_hi,x
        cmp vm_hi,y
        bne :+
        lda vm_lo,x
        cmp vm_lo,y
:       rts

; branches: after the compare, Y = offset of the address operand
op_jlti:
        VI
        jmp jlt_xy
op_jlt:
        VW
jlt_xy: jsr cmp_xy
        php                     ; ldy would clobber Z
        ldy vm_pc
        plp
        bcc @t
        jmp skip2
@t:     jmp take
op_jgei:
        VI
        jmp jge_xy
op_jge:
        VW
jge_xy: jsr cmp_xy
        php                     ; ldy would clobber Z
        ldy vm_pc
        plp
        bcs @t
        jmp skip2
@t:     jmp take
op_jeqi:
        VI
        jmp jeq_xy
op_jeq:
        VW
jeq_xy: jsr cmp_xy
        php                     ; ldy would clobber Z
        ldy vm_pc
        plp
        beq @t
        jmp skip2
@t:     jmp take
op_jnei:
        VI
        jmp jne_xy
op_jne:
        VW
jne_xy: jsr cmp_xy
        php                     ; ldy would clobber Z
        ldy vm_pc
        plp
        bne @t
        jmp skip2
@t:     jmp take

; LDT v, addr, w: v = byte at script offset addr + w
op_ldt:
        FETCH
        sta vm_x
        FETCH
        sta b64_val
        FETCH
        sta b64_val+1
        FETCH
        sty vm_pc
        tax
        lda vm_lo,x
        clc
        adc b64_val
        sta b64_val
        lda vm_hi,x
        adc b64_val+1
        clc
        adc vm_base+1
        tay
        lda vm_base+2
        adc #0
        tax
        tya
        jsr b64_page_get
        sta b64_ptr+1
        lda #0
        sta b64_ptr
        ldy b64_val
        lda (b64_ptr),y
        ldx vm_x
        jsr set_byte
        jsr vm_sync             ; the lookup may have replaced our page
        jmp back
set_byte:
        sta vm_lo,x
        lda #0
        sta vm_hi,x
        rts
op_frame:
        FETCH
        tax
        lda b64_frame
        jsr set_byte
        jmp vm_next
op_joy:
        FETCH
        tax
        lda b64_joy
        jsr set_byte
        jmp vm_next

; ---------------------------------------------------------------------------
; syscalls.  The offset is saved before calling into the engine.
.macro SLOT
        FETCH
        sta b64_reu
        FETCH
        sta b64_reu+1
        FETCH
        sta b64_reu+2
.endmacro

op_still:
        SLOT
        sty vm_pc
        jsr b64_cut_still
        jmp back
op_object:
        SLOT
        sty vm_pc
        jsr b64_obj_load
        jmp back
op_shimmer:
        FETCH
        sta shim_on
        jmp vm_next
op_text:
        FETCH
        pha                     ; row
        FETCH
        sta vm_x                ; column
        sty vm_pc
        lda vm_slow
        beq :+
        jsr vm_sync
:       ldx #0
@copy:  jsr vm_getc
        sta vm_line,x
        cmp #0                  ; the flags after vm_getc are the pointer's, not the byte's
        beq @end
        inx
        cpx #40
        bne @copy
        lda #0
        sta vm_line,x
:       jsr vm_getc             ; skip the rest of an overlong string
        cmp #0
        bne :-
@end:   lda #<vm_line
        sta b64_val
        lda #>vm_line
        sta b64_val+1
        ldx vm_x
        pla
        jsr b64_cut_text
        jmp back
op_cleartext:
        sty vm_pc
        jsr b64_cut_clear_text
        jmp back
op_blit:
        SLOT
        FETCH
        sta b64_tmp
        FETCH
        tax
        sty vm_pc
        lda b64_tmp
        jsr b64_cut_blit
        jmp back
op_restore:
        FETCH
        sta b64_tmp
        FETCH
        sta b64_tmp+1
        FETCH
        sta b64_tmp+2
        FETCH
        sta b64_val
        sty vm_pc
        lda b64_tmp
        ldx b64_tmp+1
        ldy b64_tmp+2
        jsr b64_cut_restore
        jmp back
; park and unpark wait for a frame whose vblank is in the shimmer's base
; phase, so the block and the still it was composited on agree.  Until then
; the opcode re-runs next frame.
op_park:
        jsr park_phase
        bcs @retry
        FETCH
        sta b64_tmp
        FETCH
        tax
        sty vm_pc
        lda b64_tmp
        jsr b64_obj_park
        jmp back
@retry: dey                     ; back to the opcode
        jmp vm_yield
op_unpark:
        jsr park_phase
        bcs @retry
        FETCH
        sta b64_tmp
        FETCH
        tax
        sty vm_pc
        lda b64_tmp
        jsr b64_obj_unpark
        jmp back
@retry: dey
        jmp vm_yield
; C = 1 if this frame's vblank is not the right phase
park_phase:
        lda b64_frame
        clc
        adc #1
        and #4
        beq @ok
        sec
        rts
@ok:    clc
        rts
op_objspr:
        FETCH
        sta vm_x
        jsr spr_xy
        ldx vm_x
        jsr b64_obj_sprites
        jmp back
op_objanim:
        FETCH
        tax
        lda vm_lo,x
        jsr b64_obj_anim
        jmp vm_next
op_sprite:
        FETCH
        sta b64_spr_slot
        jsr spr_xy
        ldy vm_pc
        FETCH
        sta b64_spr_colour
        SLOT
        sty vm_pc
        lda #0
        sta b64_spr_flags
        jsr b64_spr_add
        jmp back
; PCM ch, slot24, len24, rate16, vol, pan
op_pcm:
        FETCH
        sta vm_x
        SLOT
        FETCH
        sta b64_val
        FETCH
        sta b64_val+1
        FETCH
        sta b64_val+2
        FETCH
        sta b64_tmp
        FETCH
        sta b64_tmp+1
        FETCH
        sta b64_tmp+2
        FETCH
        sta b64_tmp+3
        sty vm_pc
        ldx vm_x
        jsr b64_pcm_play
        jmp back
; spr_xy: operands vx, vy -> b64_spr_x/y; the offset is saved
spr_xy:
        FETCH
        tax
        lda vm_lo,x
        sta b64_spr_x
        lda vm_hi,x
        sta b64_spr_x+1
        FETCH
        tax
        sty vm_pc
        lda vm_lo,x
        sta b64_spr_y
        rts

.segment "RODATA"
vm_oplo:
        .lobytes op_end-1, op_wait-1, op_yield-1, op_jmp-1, op_spawn-1, op_call-1, op_ret-1, op_loop-1
        .lobytes op_ldi-1, op_mov-1, op_add-1, op_addi-1, op_sub-1, op_subi-1, op_and-1, op_andi-1
        .lobytes op_min-1, op_mini-1, op_max-1, op_maxi-1, op_shr-1, op_shl-1
        .lobytes op_jlt-1, op_jlti-1, op_jge-1, op_jgei-1, op_jeq-1, op_jeqi-1, op_jne-1, op_jnei-1
        .lobytes op_ldt-1, op_frame-1, op_joy-1
        .lobytes op_still-1, op_object-1, op_shimmer-1, op_text-1, op_cleartext-1, op_blit-1, op_restore-1
        .lobytes op_park-1, op_unpark-1, op_objspr-1, op_objanim-1, op_sprite-1, op_pcm-1
vm_ophi:
        .hibytes op_end-1, op_wait-1, op_yield-1, op_jmp-1, op_spawn-1, op_call-1, op_ret-1, op_loop-1
        .hibytes op_ldi-1, op_mov-1, op_add-1, op_addi-1, op_sub-1, op_subi-1, op_and-1, op_andi-1
        .hibytes op_min-1, op_mini-1, op_max-1, op_maxi-1, op_shr-1, op_shl-1
        .hibytes op_jlt-1, op_jlti-1, op_jge-1, op_jgei-1, op_jeq-1, op_jeqi-1, op_jne-1, op_jnei-1
        .hibytes op_ldt-1, op_frame-1, op_joy-1
        .hibytes op_still-1, op_object-1, op_shimmer-1, op_text-1, op_cleartext-1, op_blit-1, op_restore-1
        .hibytes op_park-1, op_unpark-1, op_objspr-1, op_objanim-1, op_sprite-1, op_pcm-1
