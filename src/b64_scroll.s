; backlot-64 scroller: 8-way hardware scroll over the REU world.
;
; Two screen buffers.  When the camera crosses a cell boundary, the front
; buffer is copied to the back buffer through REU scratch with a byte offset
; (dx + 40*dy), the newly exposed column and/or row are filled from the
; metatile library, and the flip plus the colour RAM shift happen in the
; vertical border IRQ.  See docs/PLAN.md section 3.1.

.include "b64.inc"
.include "slots.inc"

.export scr_vblank
.import hud_flush

SCREEN_BYTES    = B64_PLAY_ROWS * 40      ; 920: rows 0-22 shift, the HUD rows stay

.segment "LOWRAM"
mt_buf:         .res 16
staged_col:     .res 25
staged_row:     .res 40

.segment "RODATA"
row_lo:
.repeat 25, r
        .byte <(r*40)
.endrepeat
row_hi:
.repeat 25, r
        .byte >(r*40)
.endrepeat
mt16_lo:
.repeat 256, i
        .byte <(i*16)
.endrepeat
mt16_hi:
.repeat 256, i
        .byte >(B64_MTCHARS + i*16)
.endrepeat

.segment "CODE"

; ---------------------------------------------------------------------------
; b64_move_camera: A = dx, X = dy, signed
b64_move_camera:
        sta b64_tmp
        stx b64_tmp+1
        ; cam_x += dx
        lda b64_tmp
        bpl :+
        clc
        adc b64_cam_x
        sta b64_cam_x
        lda b64_cam_x+1
        adc #$FF
        sta b64_cam_x+1
        jmp @y
:       clc
        adc b64_cam_x
        sta b64_cam_x
        lda b64_cam_x+1
        adc #0
        sta b64_cam_x+1
@y:     lda b64_tmp+1
        bpl :+
        clc
        adc b64_cam_y
        sta b64_cam_y
        lda b64_cam_y+1
        adc #$FF
        sta b64_cam_y+1
        rts
:       clc
        adc b64_cam_y
        sta b64_cam_y
        lda b64_cam_y+1
        adc #0
        sta b64_cam_y+1
        rts

; ---------------------------------------------------------------------------
; camera pixels -> camera cells (scr_cx/scr_cy) and fine scroll (scr_xs/scr_ys)
calc_cam:
        lda b64_cam_x+1
        sta scr_cx+1
        lda b64_cam_x
        sta scr_cx
        lsr scr_cx+1
        ror scr_cx
        lsr scr_cx+1
        ror scr_cx
        lsr scr_cx+1
        ror scr_cx
        lda b64_cam_y+1
        sta scr_cy+1
        lda b64_cam_y
        sta scr_cy
        lsr scr_cy+1
        ror scr_cy
        lsr scr_cy+1
        ror scr_cy
        lsr scr_cy+1
        ror scr_cy
        lda b64_cam_x
        and #7
        eor #7
        sta scr_xs
        lda b64_cam_y
        and #7
        eor #7
        sta scr_ys
        rts

; ---------------------------------------------------------------------------
; b64_scroll_prepare: called by the engine once per frame after the callback.
b64_scroll_prepare:
        jsr calc_cam
        ; dx = cx - ocx  (expected -1, 0, 1), dy likewise
        lda scr_cx
        sec
        sbc scr_ocx
        sta b64_tmp             ; dx (low byte is enough)
        lda scr_cy
        sec
        sbc scr_ocy
        sta b64_tmp+1           ; dy
        ora b64_tmp
        bne @shift
        ; no cell crossing: only the fine scroll registers
        lda #1
        sta scr_pending
        rts

@shift:
        ; back buffer high byte
        lda scr_front
        beq :+
        lda #>B64_SCREEN_A
        bne :++
:       lda #>B64_SCREEN_B
:       sta scr_back_hi

        ; off = dx + 40*dy as signed 16-bit
        lda #0
        sta scr_off_hi
        lda b64_tmp+1
        beq @nody
        bpl @dyp
        lda #<(-40)
        sta scr_off_lo
        lda #>(-40)
        sta scr_off_hi
        jmp @adddx
@dyp:   lda #40
        sta scr_off_lo
        jmp @adddx
@nody:  sta scr_off_lo
@adddx:
        lda b64_tmp
        beq @offdone
        bpl @dxp
        lda scr_off_lo
        sec
        sbc #1
        sta scr_off_lo
        bcs @offdone
        dec scr_off_hi
        jmp @offdone
@dxp:   inc scr_off_lo
        bne @offdone
        inc scr_off_hi
@offdone:

        ; screen shift: front -> scratch -> back, with offset
        lda scr_front
        beq :+
        lda #>B64_SCREEN_B
        bne :++
:       lda #>B64_SCREEN_A
:       sta b64_tmp+2           ; front hi
        jsr shift_buffer        ; uses b64_tmp+2 (src hi), scr_back_hi (dst hi)

        ; which edges to fill
        lda #$FF
        sta scr_newcol
        sta scr_newrow
        lda b64_tmp
        beq @nocol
        bpl :+
        lda #0
        sta scr_newcol
        beq @nocol
:       lda #39
        sta scr_newcol
@nocol:
        lda b64_tmp+1
        beq @norow
        bpl :+
        lda #0
        sta scr_newrow
        beq @norow
:       lda #(B64_PLAY_ROWS - 1)
        sta scr_newrow
@norow:
        lda scr_newcol
        cmp #$FF
        beq :+
        jsr fill_col
:       lda scr_newrow
        cmp #$FF
        beq :+
        jsr fill_row
:       lda scr_cx
        sta scr_ocx
        lda scr_cx+1
        sta scr_ocx+1
        lda scr_cy
        sta scr_ocy
        lda scr_cy+1
        sta scr_ocy+1
        lda #3
        sta scr_pending
        rts

; ---------------------------------------------------------------------------
; shift_buffer: copy 1000-|off| bytes from (b64_tmp+2):00 to (scr_back_hi):00
; with the signed offset in scr_off, via REU scratch.
shift_buffer:
        lda scr_off_hi
        bmi @neg
        ; positive: src = front + off, dst = back, len = 1000 - off
        lda scr_off_lo
        sta b64_ptr
        lda b64_tmp+2
        clc
        adc scr_off_hi
        sta b64_ptr+1
        lda #<SCREEN_BYTES
        sec
        sbc scr_off_lo
        sta b64_len
        lda #>SCREEN_BYTES
        sbc scr_off_hi
        sta b64_len+1
        B64_SET24 b64_reu, SLOT_SCRATCH
        jsr b64_stash
        lda #0
        sta b64_ptr
        lda scr_back_hi
        sta b64_ptr+1
        B64_SET24 b64_reu, SLOT_SCRATCH
        jmp b64_fetch
@neg:
        ; negative: src = front, dst = back + (-off), len = 1000 + off
        lda #0
        sta b64_ptr
        lda b64_tmp+2
        sta b64_ptr+1
        lda #<SCREEN_BYTES
        clc
        adc scr_off_lo
        sta b64_len
        lda #>SCREEN_BYTES
        adc scr_off_hi
        sta b64_len+1
        B64_SET24 b64_reu, SLOT_SCRATCH
        jsr b64_stash
        lda #0
        sec
        sbc scr_off_lo
        sta b64_ptr
        lda scr_back_hi
        sbc scr_off_hi
        sta b64_ptr+1
        B64_SET24 b64_reu, SLOT_SCRATCH
        jmp b64_fetch

; ---------------------------------------------------------------------------
; reu_map_addr: b64_reu = (scr_my << 11) | scr_mx   (world is 2048 wide)
reu_map_addr:
        lda scr_mx
        sta b64_reu
        lda scr_my
        and #$1F
        asl
        asl
        asl
        ora scr_mx+1
        sta b64_reu+1
        lda scr_my
        lsr
        lsr
        lsr
        lsr
        lsr
        sta b64_tmp+4
        lda scr_my+1
        asl
        asl
        asl
        ora b64_tmp+4
        sta b64_reu+2
        rts

; mt_ptr: A = metatile id -> scr_q = B64_MTCHARS + id*16, scr_mx = B64_MTCOLS + id*16
; (scr_mx is free once the DMA address has been computed)
mt_ptr:
        tay
        lda mt16_lo,y
        sta scr_q
        sta scr_mx
        lda mt16_hi,y
        sta scr_q+1
        clc
        adc #$10
        sta scr_mx+1
        rts

; ---------------------------------------------------------------------------
; fill_col: A = screen column.  Chars into the back buffer, colours staged.
fill_col:
        sta scr_i
        clc
        lda scr_cx
        adc scr_i
        sta scr_wx
        lda scr_cx+1
        adc #0
        sta scr_wx+1
        ; mx = wx >> 2, my = cy >> 2
        lda scr_wx+1
        sta scr_mx+1
        lda scr_wx
        sta scr_mx
        lsr scr_mx+1
        ror scr_mx
        lsr scr_mx+1
        ror scr_mx
        lda scr_cy+1
        sta scr_my+1
        lda scr_cy
        sta scr_my
        lsr scr_my+1
        ror scr_my
        lsr scr_my+1
        ror scr_my
        jsr reu_map_addr
        ; 8 metatiles down the column, stride 2048
        lda #1
        sta b64_len
        lda #0
        sta b64_len+1
        ldx #0
@f:     stx scr_k
        lda #<mt_buf
        clc
        adc scr_k
        sta b64_ptr
        lda #>mt_buf
        adc #0
        sta b64_ptr+1
        jsr b64_fetch
        lda b64_reu+1
        clc
        adc #8
        sta b64_reu+1
        bcc :+
        inc b64_reu+2
:       ldx scr_k
        inx
        cpx #8
        bne @f
        ; expand 25 rows
        lda scr_wx
        and #3
        sta scr_sub             ; column within metatile
        lda scr_cy
        and #3
        sta scr_k               ; running (suby0 + r)
        lda scr_i
        sta scr_p               ; running destination = back + col
        lda scr_back_hi
        sta scr_p+1
        ldx #0
@r:     cpx #0
        beq @calc
        lda scr_k
        and #3
        bne @same
@calc:  lda scr_k
        lsr
        lsr
        tay
        lda mt_buf,y
        jsr mt_ptr
@same:  lda scr_k
        and #3
        asl
        asl
        ora scr_sub
        tay
        lda (scr_mx),y
        sta staged_col,x
        lda (scr_q),y
        ldy #0
        sta (scr_p),y
        lda scr_p
        clc
        adc #40
        sta scr_p
        bcc :+
        inc scr_p+1
:       inc scr_k
        inx
        cpx #B64_PLAY_ROWS
        bne @r
        rts

; ---------------------------------------------------------------------------
; fill_row: A = screen row.  Chars into the back buffer, colours staged.
fill_row:
        sta scr_i
        clc
        lda scr_cy
        adc scr_i
        sta scr_wy
        lda scr_cy+1
        adc #0
        sta scr_wy+1
        ; mx = cx >> 2, my = wy >> 2
        lda scr_cx+1
        sta scr_mx+1
        lda scr_cx
        sta scr_mx
        lsr scr_mx+1
        ror scr_mx
        lsr scr_mx+1
        ror scr_mx
        lda scr_wy+1
        sta scr_my+1
        lda scr_wy
        sta scr_my
        lsr scr_my+1
        ror scr_my
        lsr scr_my+1
        ror scr_my
        jsr reu_map_addr
        B64_SET16 b64_ptr, mt_buf
        lda #11
        sta b64_len
        lda #0
        sta b64_len+1
        jsr b64_fetch
        ; expand 40 columns
        lda scr_wy
        and #3
        asl
        asl
        sta scr_sub             ; row within metatile * 4
        lda scr_cx
        and #3
        sta scr_k               ; running (subx0 + c)
        ldx scr_i
        lda row_lo,x
        sta scr_p
        lda row_hi,x
        clc
        adc scr_back_hi
        sta scr_p+1
        ldx #0
@c:     cpx #0
        beq @calc
        lda scr_k
        and #3
        bne @same
@calc:  lda scr_k
        lsr
        lsr
        tay
        lda mt_buf,y
        jsr mt_ptr
@same:  lda scr_k
        and #3
        ora scr_sub
        tay
        lda (scr_mx),y
        sta staged_row,x
        lda (scr_q),y
        sta b64_tmp+6
        txa
        tay
        lda b64_tmp+6
        sta (scr_p),y
        inc scr_k
        inx
        cpx #40
        bne @c
        rts

; ---------------------------------------------------------------------------
; b64_redraw: rebuild the front buffer and colour RAM from the camera.
b64_redraw:
        jsr calc_cam
        lda scr_front
        beq :+
        lda #>B64_SCREEN_B
        bne :++
:       lda #>B64_SCREEN_A
:       sta scr_back_hi         ; fill into the front buffer directly
        lda #0
        sta b64_tmp+7
@row:   lda b64_tmp+7
        jsr fill_row
        ; copy staged_row to colour RAM
        ldx b64_tmp+7
        lda row_lo,x
        sta scr_p
        lda row_hi,x
        clc
        adc #>B64_COLOR_RAM
        sta scr_p+1
        ldy #39
:       lda staged_row,y
        sta (scr_p),y
        dey
        bpl :-
        inc b64_tmp+7
        lda b64_tmp+7
        cmp #B64_PLAY_ROWS
        bne @row
        lda scr_cx
        sta scr_ocx
        lda scr_cx+1
        sta scr_ocx+1
        lda scr_cy
        sta scr_ocy
        lda scr_cy+1
        sta scr_ocy+1
        lda #$FF
        sta scr_newcol
        sta scr_newrow
        jsr apply_regs
        lda #0
        sta scr_pending
        rts

; ---------------------------------------------------------------------------
; scr_vblank: called from the engine IRQ at the bottom of the display.
scr_vblank:
        lda scr_pending
        bne :+
        jmp @done
:       and #2
        bne :+
        jmp @regs
:
        ; colour RAM shift with the same offset, in place via scratch
        lda scr_off_hi
        bmi @cneg
        lda scr_off_lo
        sta b64_ptr
        lda #>B64_COLOR_RAM
        clc
        adc scr_off_hi
        sta b64_ptr+1
        lda #<SCREEN_BYTES
        sec
        sbc scr_off_lo
        sta b64_len
        lda #>SCREEN_BYTES
        sbc scr_off_hi
        sta b64_len+1
        B64_SET24 b64_reu, SLOT_SCRATCH
        jsr b64_stash
        B64_SET16 b64_ptr, B64_COLOR_RAM
        B64_SET24 b64_reu, SLOT_SCRATCH
        jsr b64_fetch
        jmp @staged
@cneg:
        B64_SET16 b64_ptr, B64_COLOR_RAM
        lda #<SCREEN_BYTES
        clc
        adc scr_off_lo
        sta b64_len
        lda #>SCREEN_BYTES
        adc scr_off_hi
        sta b64_len+1
        B64_SET24 b64_reu, SLOT_SCRATCH
        jsr b64_stash
        lda #0
        sec
        sbc scr_off_lo
        sta b64_ptr
        lda #>B64_COLOR_RAM
        sbc scr_off_hi
        sta b64_ptr+1
        B64_SET24 b64_reu, SLOT_SCRATCH
        jsr b64_fetch
@staged:
        ; staged column colours
        lda scr_newcol
        cmp #$FF
        beq @nocol
        ldx #0
@sc:    lda row_lo,x
        clc
        adc scr_newcol
        sta scr_p
        lda row_hi,x
        adc #>B64_COLOR_RAM
        sta scr_p+1
        lda staged_col,x
        ldy #0
        sta (scr_p),y
        inx
        cpx #B64_PLAY_ROWS
        bne @sc
@nocol:
        lda scr_newrow
        cmp #$FF
        beq @norow
        tax
        lda row_lo,x
        sta scr_p
        lda row_hi,x
        clc
        adc #>B64_COLOR_RAM
        sta scr_p+1
        ldy #39
@sr:    lda staged_row,y
        sta (scr_p),y
        dey
        bpl @sr
@norow:
        ; flip buffers
        lda scr_front
        eor #1
        sta scr_front
@regs:
        jsr apply_regs
        lda #0
        sta scr_pending
@done:
        jsr hud_flush
        ; pinned sprite 0 pointer in both buffers
        lda b64_spr0_frame
        clc
        adc #B64_SPR_BASE
        sta B64_SPR_PTR_A
        sta B64_SPR_PTR_B
        rts

; video matrix and fine scroll registers from scr_front / scr_xs / scr_ys
apply_regs:
        lda scr_front
        beq :+
        lda #%00010010          ; screen B
        bne :++
:       lda #%00000010          ; screen A
:       sta VIC_VIDEO_ADR
        lda scr_xs
        ora #%00010000
        sta VIC_CTRL2
        lda scr_ys
        ora #%00010000
        sta VIC_CTRL1
        rts
