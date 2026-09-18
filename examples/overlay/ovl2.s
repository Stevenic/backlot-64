; backlot-64 example overlay 2: a different body for the same window.

.include "b64.inc"

.segment "OVERLAY"
entry:
        lda #<msg
        sta b64_val
        lda #>msg
        sta b64_val+1
        lda #5
        ldx #2
        jsr b64_text
        lda #$B2
        sta $E000
        inc $E001
        rts
msg:    .byte "OVERLAY TWO REPLACED IT", 0
        .res $2000-(*-entry)-1
        .byte $B2
