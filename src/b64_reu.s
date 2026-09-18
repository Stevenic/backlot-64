; backlot-64 data engine: REU DMA primitives.
;
; b64_fetch / b64_stash move b64_len bytes between REU address b64_reu (24-bit)
; and C64 address b64_ptr.  DMA halts the CPU, so on return the bytes are there.
; A length of 0 means 65536.

.include "b64.inc"
.include "slots.inc"

.segment "CODE"

b64_fetch:
        lda #REU_CMD_FETCH
        bne reu_go
b64_stash:
        lda #REU_CMD_STASH
reu_go:
        ; The hazard (an interrupt issuing its own DMA between the setup and
        ; the go) is the one DOOM C64U repairs by saving the REU registers in
        ; its handler; here it is prevented instead.  Changed, not measured
        ; as better: a handler that must issue a DMA still needs DOOM's form.
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

; b64_boot_check: the REU answers and holds the image this program was built
; against, or the machine halts with the reason in the border.  The image's
; header (tools/b64pack.py) is compared in place with the REU's verify
; command: first the magic, then the format and the layout hash.
; After Honza Slesinger, DOOM for the C64 Ultimate (REU image header with
; boot cross-checks).  Changed: verified by the REU against seven constant
; bytes, nothing is fetched and no RAM is used.
b64_boot_check:
        jsr b64_reu_present
        lda #B64_ERR_NOREU
        bcc b64_boot_halt
        B64_SET24 b64_reu, SLOT_HEADER
        B64_SET16 b64_ptr, boot_want
        ldx #4                  ; the magic
        ldy #B64_ERR_NOIMAGE
        jsr @verify
        B64_SET24 b64_reu, SLOT_HEADER+4
        B64_SET16 b64_ptr, boot_want+4
        ldx #3                  ; format and layout hash
        ldy #B64_ERR_STALE
@verify:
        stx b64_len
        lda #0
        sta b64_len+1
        lda #REU_CMD_VERIFY
        jsr reu_go
        lda REU_STATUS
        and #$20                ; fault: the bytes differ
        bne :+
        rts
:       tya
; b64_boot_halt: A = the colour.  Flashes it against black for ever.
b64_boot_halt:
        sei
        sta b64_tmp
@flash: eor b64_tmp             ; alternates the colour and 0
        sta VIC_BORDERCOLOR
        ldx #0
        ldy #0
:       dex
        bne :-
        dey
        bne :-
        jmp @flash

.segment "RODATA"
boot_want:      .byte "B64R", REU_FORMAT, <REU_LAYOUT_HASH, >REU_LAYOUT_HASH
.segment "CODE"

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
