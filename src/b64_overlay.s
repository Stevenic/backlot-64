; backlot-64 data engine: code overlays.
;
; The 6502 cannot execute from the REU, so code that is not resident lives
; there in slots assembled for a fixed window and is DMA'd in when needed.
; Overlay region A is $8000-$9FFF (8 KB).  An overlay is a plain binary
; whose first byte is its entry point; a game calls b64_overlay_load and
; then jsr's the window.  The engine remembers which slot is resident, so
; loading the overlay that is already there costs a compare and no DMA.
;
; Overlays are linked against the resident program's addresses by
; tools/b64overlay.py, so they can call any engine routine.  The rule from
; the plan holds: the render path never depends on an overlay being present.

.include "b64.inc"

.export b64_overlay_load
.export b64_overlay_reset
.export ovl_loads

.segment "LOWRAM"
ovl_res:        .res 3          ; REU address of the resident overlay, $FFFFFF = none
ovl_loads:      .res 1          ; DMAs performed (for the tests)

.segment "CODE"

; b64_overlay_reset: forget what is resident (after anything else wrote
; the window, such as a cutscene's stash and restore)
b64_overlay_reset:
        lda #$FF
        sta ovl_res
        sta ovl_res+1
        sta ovl_res+2
        lda #0
        sta ovl_loads
        rts

; b64_overlay_load: b64_reu = slot, b64_len = length (at most 8 KB).
; C = 1 if the overlay was fetched, C = 0 if it was already resident.
; Interrupts may run during the DMA; the window is not touched by them.
b64_overlay_load:
        lda b64_reu
        cmp ovl_res
        bne @load
        lda b64_reu+1
        cmp ovl_res+1
        bne @load
        lda b64_reu+2
        cmp ovl_res+2
        bne @load
        clc
        rts
@load:  lda b64_reu
        sta ovl_res
        lda b64_reu+1
        sta ovl_res+1
        lda b64_reu+2
        sta ovl_res+2
        B64_SET16 b64_ptr, B64_OVERLAY_A
        jsr b64_fetch
        inc ovl_loads
        sec
        rts
