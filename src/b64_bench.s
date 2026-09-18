; backlot-64 benchmark harness: CIA2 timers A and B cascaded as a 32-bit
; cycle counter.  Counts wall-clock cycles including DMA and badlines.

.include "b64.inc"

.segment "CODE"

b64_bench_begin:
        lda #0
        sta CIA2_CRA
        sta CIA2_CRB
        lda #$FF
        sta CIA2_TA
        sta CIA2_TA+1
        sta CIA2_TB
        sta CIA2_TB+1
        lda #%01010001          ; force load, count TA underflows, start
        sta CIA2_CRB
        lda #%00010001          ; force load, start
        sta CIA2_CRA
        rts

; elapsed = ~(TB:TA) since both started at $FFFF
b64_bench_end:
        lda CIA2_TA
        eor #$FF
        sta b64_val
        lda CIA2_TA+1
        eor #$FF
        sta b64_val+1
        lda CIA2_TB
        eor #$FF
        sta b64_val+2
        ; max
        lda b64_val+2
        cmp bench_max+2
        bcc @done
        bne @set
        lda b64_val+1
        cmp bench_max+1
        bcc @done
        bne @set
        lda b64_val
        cmp bench_max
        bcc @done
@set:   lda b64_val
        sta bench_max
        lda b64_val+1
        sta bench_max+1
        lda b64_val+2
        sta bench_max+2
@done:  rts

; HUD: "LAST nnnnn  MAX nnnnn"
b64_bench_show:
        lda b64_val
        pha
        lda b64_val+1
        pha
        lda #<label_last
        sta b64_val
        lda #>label_last
        sta b64_val+1
        ldx #0
        jsr b64_hud_text
        pla
        sta b64_val+1
        pla
        sta b64_val
        ldx #5
        jsr b64_hud_number
        lda #<label_max
        sta b64_val
        lda #>label_max
        sta b64_val+1
        ldx #12
        jsr b64_hud_text
        lda bench_max
        sta b64_val
        lda bench_max+1
        sta b64_val+1
        ldx #16
        jmp b64_hud_number

.segment "RODATA"
label_last:     .byte "LAST ", 0
label_max:      .byte "MAX ", 0
