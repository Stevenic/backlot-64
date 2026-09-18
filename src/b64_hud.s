; backlot-64 HUD: one fixed text row at the bottom of the screen.
;
; The playfield scrolls with fine scroll; a raster IRQ at HUD_SPLIT_LINE
; resets YSCROLL to 3 and XSCROLL to 0, so screen row 23 is drawn unscrolled
; and unshifted.  Row 24 is hidden in 24-row mode.  The HUD's characters
; and colours live in hud_chars / hud_cols and are copied into the buffers
; whenever the scroller touches row 23.

.include "b64.inc"

.export hud_split
.export hud_flush
.export hud_init
.export split_done
.export split_line

HUD_ROW         = 23
HUD_OFFSET      = HUD_ROW * 40

.segment "LOWRAM"
hud_chars:      .res 40
hud_cols:       .res 40
split_done:     .res 1
split_line:     .res 1          ; 231 + YSCROLL, recomputed each vblank
hud_dirty:      .res 1

.segment "CODE"

; clear the HUD to spaces in white
b64_hud_clear:
        lda #1
        sta hud_dirty
        ldx #39
        lda #(B64_FONT_BASE + ' ' - 32)
:       sta hud_chars,x
        dex
        bpl :-
        ldx #39
        lda #1
:       sta hud_cols,x
        dex
        bpl :-
        rts

; b64_hud_text: X = column, string at (b64_val) 0-terminated, ASCII 32..95
b64_hud_text:
        lda #1
        sta hud_dirty
        ldy #0
@l:     lda (b64_val),y
        beq @done
        sec
        sbc #32
        clc
        adc #B64_FONT_BASE
        sta hud_chars,x
        lda #1
        sta hud_cols,x
        inx
        iny
        cpx #40
        bne @l
@done:  rts

; b64_hud_number: X = column, b64_val = 16-bit value, five digits
b64_hud_number:
        lda #1
        sta hud_dirty
        ldy #0
@digit:
        lda #0
        sta b64_tmp+3
@sub:   lda b64_val
        sec
        sbc pow10_lo,y
        sta b64_tmp+4
        lda b64_val+1
        sbc pow10_hi,y
        bcc @next
        sta b64_val+1
        lda b64_tmp+4
        sta b64_val
        inc b64_tmp+3
        jmp @sub
@next:  lda b64_tmp+3
        clc
        adc #(B64_FONT_BASE + '0' - 32)
        sta hud_chars,x
        lda #1
        sta hud_cols,x
        inx
        iny
        cpy #5
        bne @digit
        rts

; ---------------------------------------------------------------------------
; raster split: called from the IRQ dispatcher at HUD_SPLIT_LINE
hud_split:
        lda #%00010111          ; 24 rows, yscroll 7: next badline at 239
        sta VIC_CTRL1
        lda #%00011000          ; 40 columns, multicolour, xscroll 0
        sta VIC_CTRL2
        lda #1
        sta split_done
        rts

; hud_flush: if the HUD changed, copy it into row 23 of both buffers and
; colour RAM.  Called at the vertical blank.
hud_flush:
        lda hud_dirty
        bne :+
        rts
:       lda #0
        sta hud_dirty
        ldy #39
:       lda hud_chars,y
        sta B64_SCREEN_A + HUD_OFFSET,y
        sta B64_SCREEN_B + HUD_OFFSET,y
        lda hud_cols,y
        sta B64_COLOR_RAM + HUD_OFFSET,y
        dey
        bpl :-
        rts

; hud_init: blank row 24 in both buffers (it is mostly hidden) and mark dirty
hud_init:
        lda #0
        sta B64_IDLE_BYTE
        ldy #39
        lda #(B64_FONT_BASE + ' ' - 32)
:       sta B64_SCREEN_A + HUD_OFFSET + 40,y
        sta B64_SCREEN_B + HUD_OFFSET + 40,y
        dey
        bpl :-
        ldy #39
        lda #0
:       sta B64_COLOR_RAM + HUD_OFFSET + 40,y
        dey
        bpl :-
        lda #1
        sta hud_dirty
        rts

.segment "RODATA"
pow10_lo:       .byte <10000, <1000, <100, <10, <1
pow10_hi:       .byte >10000, >1000, >100, >10, >1
