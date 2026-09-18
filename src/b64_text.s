; backlot-64 text: font chars 192..255 hold ASCII 32..95.
; For now text draws into the buffer that will be shown next, as a debug
; overlay.  The HUD row split arrives in E4.

.include "b64.inc"

.segment "CODE"

; A = row, X = col -> b64_ptr = target buffer address, b64_tmp+1 = colour RAM hi
text_target:
        sta b64_tmp
        ; buffer to show next: front, unless a flip is pending
        lda scr_front
        ldy scr_pending
        cpy #2
        bcc :+
        eor #1
:       tay
        lda #>B64_SCREEN_A
        cpy #0
        beq :+
        lda #>B64_SCREEN_B
:       sta b64_tmp+2
        ; offset = row*40 + col
        lda #0
        sta b64_ptr+1
        lda b64_tmp
        asl                     ; *2
        asl                     ; *4
        asl                     ; *8
        sta b64_ptr
        lda b64_tmp
        asl                     ; *2
        asl                     ; *4
        asl                     ; *8
        asl                     ; *16
        asl                     ; *32
        rol b64_ptr+1
        clc
        adc b64_ptr
        sta b64_ptr
        bcc :+
        inc b64_ptr+1
:       txa
        clc
        adc b64_ptr
        sta b64_ptr
        bcc :+
        inc b64_ptr+1
:       lda b64_ptr+1
        clc
        adc #>B64_COLOR_RAM
        sta b64_tmp+1           ; colour RAM hi for this offset
        lda b64_ptr+1
        clc
        adc b64_tmp+2
        sta b64_ptr+1
        rts

; b64_text: A = row, X = col, string at b64_val (2 bytes used as pointer)
b64_text:
        jsr text_target
        ldy #0
@l:     lda (b64_val),y
        beq @done
        sec
        sbc #32
        clc
        adc #B64_FONT_BASE
        sta (b64_ptr),y
        lda b64_ptr+1
        pha
        lda b64_tmp+1
        sta b64_ptr+1
        lda #1
        sta (b64_ptr),y
        pla
        sta b64_ptr+1
        iny
        bne @l
@done:  rts

; b64_number: A = row, X = col, b64_val = 16-bit value, prints 5 digits
b64_number:
        jsr text_target
        ldy #0
        ldx #0
@digit:
        lda #0
        sta b64_tmp+3           ; count
@sub:   lda b64_val
        sec
        sbc pow10_lo,x
        sta b64_tmp+4
        lda b64_val+1
        sbc pow10_hi,x
        bcc @next
        sta b64_val+1
        lda b64_tmp+4
        sta b64_val
        inc b64_tmp+3
        jmp @sub
@next:  lda b64_tmp+3
        clc
        adc #(B64_FONT_BASE + '0' - 32)
        sta (b64_ptr),y
        lda b64_ptr+1
        pha
        lda b64_tmp+1
        sta b64_ptr+1
        lda #1
        sta (b64_ptr),y
        pla
        sta b64_ptr+1
        iny
        inx
        cpx #5
        bne @digit
        rts

.segment "RODATA"
pow10_lo:       .byte <10000, <1000, <100, <10, <1
pow10_hi:       .byte >10000, >1000, >100, >10, >1
