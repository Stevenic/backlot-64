; backlot-64 example: code overlays loaded from the REU at run time.
;
; Loads overlay 1 into region A and calls it, loads overlay 2 over it and
; calls it, then asks for overlay 1 again (a DMA) and overlay 2 again (a
; DMA), and finally overlay 2 once more, which must not DMA because it is
; already resident.  Results at $E000 for the test runner:
;   $E000 signature of the last overlay that ran
;   $E001 number of overlay calls made (5)
;   $E002 number of DMAs the loader performed (4)
;   $E003 last byte of the window after the final load ($B2)
;   $E004-$E006 cycles for one 8 KB overlay load

.include "b64.inc"
.include "slots.inc"

.import ovl_loads
.export game_main

.segment "GAME"
game_main:
        jsr b64_init
        jsr b64_reu_present
        bcs :+
        lda #2
        sta VIC_BORDERCOLOR
@halt:  jmp @halt
:       B64_SET24 b64_reu, SLOT_TILESET0
        jsr b64_load_tileset    ; the font
        jsr b64_overlay_reset
        lda #0
        sta $E001

        ; 1
        jsr b64_bench_begin
        B64_SET24 b64_reu, SLOT_OVL1
        B64_SET16 b64_len, $2000
        jsr b64_overlay_load
        jsr b64_bench_end
        lda b64_val
        sta $E004
        lda b64_val+1
        sta $E005
        lda b64_val+2
        sta $E006
        jsr B64_OVERLAY_A
        ; 2
        B64_SET24 b64_reu, SLOT_OVL2
        B64_SET16 b64_len, $2000
        jsr b64_overlay_load
        jsr B64_OVERLAY_A
        ; 1 again
        B64_SET24 b64_reu, SLOT_OVL1
        B64_SET16 b64_len, $2000
        jsr b64_overlay_load
        jsr B64_OVERLAY_A
        ; 2 again
        B64_SET24 b64_reu, SLOT_OVL2
        B64_SET16 b64_len, $2000
        jsr b64_overlay_load
        jsr B64_OVERLAY_A
        ; 2 once more: resident, no DMA
        B64_SET24 b64_reu, SLOT_OVL2
        B64_SET16 b64_len, $2000
        jsr b64_overlay_load
        jsr B64_OVERLAY_A

        lda ovl_loads
        sta $E002
        lda B64_OVERLAY_A+$1FFF
        sta $E003
        lda #5
        sta VIC_BORDERCOLOR     ; green: done
        lda #<frame
        ldx #>frame
        jsr b64_set_callback
        jmp b64_run
frame:  rts
