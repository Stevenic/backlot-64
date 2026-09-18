; backlot-64 data engine: REU DMA primitives.
;
; b64_fetch / b64_stash move b64_len bytes between REU address b64_reu (24-bit)
; and C64 address b64_ptr.  DMA halts the CPU, so on return the bytes are there.
; A length of 0 means 65536.

.include "b64.inc"

.segment "CODE"

b64_fetch:
        lda #REU_CMD_FETCH
        bne reu_go
b64_stash:
        lda #REU_CMD_STASH
reu_go:
        php                     ; no interrupt between the register writes and the go
        sei
        pha
        lda b64_ptr
        sta REU_C64_LO
        lda b64_ptr+1
        sta REU_C64_HI
        lda b64_reu
        sta REU_ADDR_LO
        lda b64_reu+1
        sta REU_ADDR_HI
        lda b64_reu+2
        sta REU_BANK
        lda b64_len
        sta REU_LEN_LO
        lda b64_len+1
        sta REU_LEN_HI
        lda #0
        sta REU_CTRL            ; both addresses increment
        pla
        sta REU_CMD             ; the CPU halts here until the bytes have moved
        plp
        rts

; C=1 if an REU answers at $DF00.  Open bus reads back garbage.
b64_reu_present:
        lda #$AA
        sta REU_ADDR_LO
        lda REU_ADDR_LO
        cmp #$AA
        bne @no
        lda #$55
        sta REU_ADDR_LO
        lda REU_ADDR_LO
        cmp #$55
        bne @no
        sec
        rts
@no:    clc
        rts

; Load a tileset from the REU slot at b64_reu:
;   +$0000 charset  -> B64_CHARSET  (2 KB)
;   +$0800 mtchars  -> B64_MTCHARS  (4 KB)
;   +$1800 mtcols   -> B64_MTCOLS   (4 KB)
;   +$2800 props    -> B64_PROPS    (256)
b64_load_tileset:
        B64_SET16 b64_ptr, B64_CHARSET
        B64_SET16 b64_len, $0800
        jsr b64_fetch
        jsr reu_advance_len
        B64_SET16 b64_ptr, B64_MTCHARS
        B64_SET16 b64_len, $1000
        jsr b64_fetch
        jsr reu_advance_len
        B64_SET16 b64_ptr, B64_MTCOLS
        B64_SET16 b64_len, $1000
        jsr b64_fetch
        jsr reu_advance_len
        B64_SET16 b64_ptr, B64_PROPS
        B64_SET16 b64_len, $0100
        jmp b64_fetch

; Load a 4 KB sprite bank from b64_reu into the VIC bank.
b64_load_sprites:
        B64_SET16 b64_ptr, B64_SPRITES
        B64_SET16 b64_len, $1000
        jmp b64_fetch

.export reu_advance_len

; b64_reu += b64_len
reu_advance_len:
        lda b64_reu
        clc
        adc b64_len
        sta b64_reu
        lda b64_reu+1
        adc b64_len+1
        sta b64_reu+1
        bcc :+
        inc b64_reu+2
:       rts
