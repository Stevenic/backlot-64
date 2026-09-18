; backlot-64 example overlay 1: prints a line through the engine's text
; routine, records that it ran, and pads itself so the slot is a full 8 KB
; (the test wants the DMA to be the size a real overlay would be).

.include "b64.inc"

.segment "OVERLAY"
entry:
        lda #<msg
        sta b64_val
        lda #>msg
        sta b64_val+1
        lda #3                  ; row
        ldx #2                  ; column
        jsr b64_text
        lda #$A1                ; signature
        sta $E000
        inc $E001               ; calls
        rts
msg:    .byte "OVERLAY ONE RAN FROM $8000", 0
        .res $2000-(*-entry)-1
        .byte $A1               ; last byte of the window: proves the whole 8 KB arrived
