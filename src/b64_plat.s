; backlot-64 platform layer: probe the machine at boot and scale the engine.
;
; The engine runs on a stock C64 with an REU and grows into whatever the
; machine offers: a 16 MB REU, the Ultimate 64 / C64 Ultimate turbo CPU,
; the Ultimate Audio sampler, and the Ultimate Command Interface (files
; straight into the REU).  Nothing per-frame ever depends on an extra;
; extras add headroom and features, never correctness.
;
; Register facts from Gideon Zweijtzer's Ultimate documentation (turbo mode
; settings, Ultimate Audio Register API v0.2, Command Interface).  The audio
; probe follows 6510nl's detectaudio routine from ModPlayer_16k as read in
; xahmol's UltimateDemo2026.  See CREDITS.md.
; Register facts:
;   $D031  U64 turbo control: bits 0-3 speed index 0-15 (1 MHz .. 48/64 MHz),
;          bit 7 = 1 suppresses badline stalls.  Reads $FF when absent.
;   $D030  bit 0: turbo enable (C128-style), used with $D031.
;   $DF20  Ultimate Audio: 7 channels of 32 bytes at $DF20/$DF40/../$DFE0.
;          $DF21 reads the module version ($10 = 1.0); $DF20 the IRQ status.
;   $DF1C  UCI status (read) / control (write); $DF1D id, reads $C9.

.include "b64.inc"

.export b64_plat_probe
.export b64_turbo_set
.export b64_turbo_fast
.export b64_turbo_slow
.export b64_heap_alloc
.export b64_heap_reset

.import vm_budget_max
.import uci_detect

.segment "LOWRAM"
b64_plat:       .res 1          ; B64_PLAT_* bits
b64_reu_mb:     .res 1          ; REU size in MB: 0, 8 or 16 (anything smaller reports 8)
b64_turbo:      .res 1          ; last value written to $D031, or $FF
heap_ptr:       .res 3          ; next free REU byte in the game heap
heap_end:       .res 3
.export b64_plat, b64_reu_mb, b64_turbo

.segment "CODE"

; b64_plat_probe: fill b64_plat and friends.  Called from b64_init with
; interrupts off.  Safe on a stock C64: every probe reads open bus or a
; register that answers $FF when the feature is absent, and the REU probe
; only touches the SCRATCH slot.
b64_plat_probe:
        lda #0
        sta b64_plat
        sta b64_reu_mb
        lda #$FF
        sta b64_turbo

        ; --- REU present and how big
        jsr b64_reu_present
        bcc @noreu
        lda #B64_PLAT_REU
        sta b64_plat
        lda #8
        sta b64_reu_mb
        ; write a marker at $7F0000 and a different one at $FF0000; on an
        ; 8 MB REU the second lands on the first
        lda #$5A
        sta probe_byte
        B64_SET16 b64_ptr, probe_byte
        B64_SET16 b64_len, 1
        B64_SET24 b64_reu, $7F0000
        jsr b64_stash
        lda #$A5
        sta probe_byte
        B64_SET24 b64_reu, $FF0000
        jsr b64_stash
        B64_SET24 b64_reu, $7F0000
        jsr b64_fetch
        lda probe_byte
        cmp #$5A
        bne @noreu16
        lda #16
        sta b64_reu_mb
        lda b64_plat
        ora #B64_PLAT_REU16
        sta b64_plat
@noreu16:
@noreu:
        ; --- turbo register
        lda B64_TURBO_CTRL
        cmp #$FF
        beq @noturbo
        lda #0
        sta B64_TURBO_CTRL      ; 1 MHz, badlines on: the reference state
        lda B64_TURBO_CTRL
        and #$0F
        bne @noturbo            ; did not take: not a turbo register
        lda b64_plat
        ora #B64_PLAT_TURBO
        sta b64_plat
        lda #0
        sta b64_turbo
@noturbo:
        ; --- Ultimate Audio: idle status must read 0 for 256 reads, then a
        ; silent 256-byte loop on channel 0 must raise the end-of-sample flag.
        ; Open bus does neither.
        lda #0
        sta B64_UA_BASE         ; gate off
        lda #$FF
        sta B64_UA_BASE+$1F     ; clear irq
        ldx #0
@aidle: lda B64_UA_BASE
        bne @noaudio
        dex
        bne @aidle
        lda #0
        sta B64_UA_BASE+1       ; volume 0
        lda #$01
        sta B64_UA_BASE+4       ; start: REU $000000
        lda #0
        sta B64_UA_BASE+5
        sta B64_UA_BASE+6
        sta B64_UA_BASE+7
        sta B64_UA_BASE+9       ; length 256
        lda #1
        sta B64_UA_BASE+10
        lda #0
        sta B64_UA_BASE+11
        sta B64_UA_BASE+$0E     ; rate divider 1: as fast as it goes
        lda #1
        sta B64_UA_BASE+$0F
        lda #%00000101          ; gate + irq
        sta B64_UA_BASE
        ldx #128
@await: lda B64_UA_BASE
        and #1
        bne @agot
        dex
        bne @await
        lda #0
        sta B64_UA_BASE
        beq @noaudio
@agot:  lda #0
        sta B64_UA_BASE         ; gate off
        lda #$FF
        sta B64_UA_BASE+$1F
        lda b64_plat
        ora #B64_PLAT_AUDIO
        sta b64_plat
@noaudio:
        ; --- command interface
        jsr uci_detect
        bcc @nouci
        lda b64_plat
        ora #B64_PLAT_UCI
        sta b64_plat
@nouci:
        ; --- scale the engine
        ldx #64                 ; VM opcodes per thread per frame at 1 MHz
        lda b64_plat
        and #B64_PLAT_TURBO
        beq :+
        ldx #255
:       stx vm_budget_max
        jsr b64_heap_reset
        rts

; b64_turbo_set: A = $D031 value (speed index 0-15, bit 7 = badlines off).
; Nothing happens without the register.  Speed changes take effect on the
; next cycle; DMA and the VIC are unaffected in correctness, only in time.
b64_turbo_set:
        ldx b64_plat
        pha
        txa
        and #B64_PLAT_TURBO
        beq @skip
        pla
        sta b64_turbo
        sta B64_TURBO_CTRL
        and #$0F
        beq @slow
        lda B64_TURBO_EN
        ora #$01
        sta B64_TURBO_EN
        rts
@slow:  lda B64_TURBO_EN
        and #$FE
        sta B64_TURBO_EN
        rts
@skip:  pla
        rts

; the two settings the engine uses: everything, and the reference machine
b64_turbo_fast:
        lda #$8F                ; index 15, badlines off
        jmp b64_turbo_set
b64_turbo_slow:
        lda #0
        jmp b64_turbo_set

; ---------------------------------------------------------------------------
; The game heap: REU space above the packed assets for anything the game
; writes at run time (composited stills, generated tilesets, downloaded
; packs).  Bump allocation; reset frees everything.  Sized by the REU.
b64_heap_reset:
        lda b64_reu_mb
        cmp #16
        bcs @big
        B64_SET24 heap_ptr, B64_HEAP8
        B64_SET24 heap_end, B64_HEAP8_END
        rts
@big:   B64_SET24 heap_ptr, B64_HEAP16
        B64_SET24 heap_end, B64_HEAP16_END
        rts

; b64_heap_alloc: b64_val = 24-bit length -> b64_reu = address, C = 1 ok.
; C = 0 with b64_reu unchanged when the heap is full.
b64_heap_alloc:
        clc
        lda heap_ptr
        adc b64_val
        sta b64_tmp
        lda heap_ptr+1
        adc b64_val+1
        sta b64_tmp+1
        lda heap_ptr+2
        adc b64_val+2
        sta b64_tmp+2
        bcs @full
        ; new end <= heap_end ?
        lda b64_tmp+2
        cmp heap_end+2
        bcc @ok
        bne @full
        lda b64_tmp+1
        cmp heap_end+1
        bcc @ok
        bne @full
        lda b64_tmp
        cmp heap_end
        bcc @ok
        bne @full
@ok:    lda heap_ptr
        sta b64_reu
        lda heap_ptr+1
        sta b64_reu+1
        lda heap_ptr+2
        sta b64_reu+2
        lda b64_tmp
        sta heap_ptr
        lda b64_tmp+1
        sta heap_ptr+1
        lda b64_tmp+2
        sta heap_ptr+2
        sec
        rts
@full:  clc
        rts

.segment "LOWRAM"
probe_byte:     .res 1
