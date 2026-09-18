; backlot-64 cutscene module (E12).
;
; Layers inside raster bands:
;   rows 0-19  multicolour bitmap: the still (set) with blitted blocks (props)
;   rows 20-24 character mode: the text band (font from the loaded tileset)
;   sprites    actors (grids) and overlays, through the multiplexer
;
; VIC bank while a cutscene is active:
;   $4000 text screen (rows 20-24 used)   $4800 charset (font at 192-255)
;   $5000 sprite slots                    $5C00 bitmap colour cells
;   $6000-$7FFF bitmap (game RAM, stashed to the REU for the duration)

.include "b64.inc"
.include "slots.inc"

.import reu_advance_len
.import mux_first
.export cut_active
.export cut_vblank
.export cut_split
.export shim_on
.export b64_cut_frame
.export b64_cut_light
.export b64_obj_lights
.export light_cur, light_pending, lights_on, obj_nlights, obj_x, light_hdr, obj_lights   ; for the probe and tests
.export cut_row_lo, cut_row_hi

CUT_BITMAP      = $6000
CUT_BMSCREEN    = $5C00
CUT_TEXT        = $4000
CUT_STASH       = SLOT_SCRATCH + $8000     ; 8 KB of game RAM lives here during a scene
CUT_D018        = %01111000                ; colour cells $5C00, bitmap $6000
TEXT_D018       = %00000010                ; screen $4000, charset $4800

.segment "LOWRAM"
cut_active:     .res 1
still_base:     .res 3          ; REU address of the current still (for restores)
cut_bg:         .res 1
blk_w:          .res 1
blk_h:          .res 1
blk_x:          .res 1
blk_y:          .res 1
blk_row:        .res 1
blk_tmp:        .res 2
; object (sprite + block from one master)
obj_hdr:        .res 8          ; gw, gh, cw, ch, mc0, ind, mc1, floor
obj_spans:      .res 32         ; per block row: first visible cell, last+1
obj_base:       .res 3
obj_spr:        .res 3          ; sprite frames
obj_bm:         .res 3          ; bitmap rows
obj_scr:        .res 3          ; screen bytes
obj_col:        .res 3          ; colour bytes
park_pending:   .res 1          ; 0 none, 1 park, 2 unpark
light_pending:  .res 1          ; 1 = apply the lighting state at light_addr at the next base-phase blank
light_addr:     .res 3
park_x:         .res 1
park_y:         .res 1
obj_k:          .res 1
obj_gx:         .res 1
obj_gy:         .res 1
obj_slot:       .res 1
obj_x:          .res 2
obj_y:          .res 1
obj_anim:       .res 3          ; animation section: nframes, nsprites, indices, frames
shim_n:         .res 1          ; shimmer cells in the loaded still
shim_cells:     .res 238        ; (column, row) pairs
shim_lo:        .res 119        ; colour-cell address of each cell, low byte
shim_hi:        .res 119        ; high byte; bit 7 set while the cell is under a parked block
shim_on:        .res 1
shim_due:       .res 1          ; a shimmer step is waiting to run
cut_heavy:      .res 1          ; 1 when this tick drew text: the shimmer's step waits a frame
shim_parked:    .res 1          ; 1 while an object block covers part of the still
shim_rx0:       .res 1          ; the parked rectangle in cells: x0, x1 (exclusive), y0, y1
shim_rx1:       .res 1
shim_ry0:       .res 1
shim_ry1:       .res 1
anim_hdr:       .res 10         ; nframes, nsprites, up to 8 sprite indices
obj_nlights:    .res 1          ; the object's light sources (lights section of the .b64o)
obj_lights:     .res 64         ; up to 4 x 16: dx, dy, radius, lamp, npat, pad, (colour, frames) x 4
lights_on:      .res 1          ; 1 = the engine lights the set from the object's lights
lights_slot:    .res 3          ; the baked lighting file for this set and object
lamp_slot:      .res 3          ; the lamp sprite frame
light_hdr:      .res 34         ; the file's layout: 'L', n, x0 lo/hi, xstep, npos, per light base lo/hi, ncol, colours[4]
light_cur:      .res 1          ; the state last queued, so a state is queued once
anim_frame:     .res 1

.segment "CODE"

; ---------------------------------------------------------------------------
; b64_cut_begin: stash game RAM, switch the VIC to the cutscene layout.
b64_cut_begin:
        B64_SET16 b64_ptr, CUT_BITMAP
        B64_SET16 b64_len, $2000
        B64_SET24 b64_reu, CUT_STASH
        jsr b64_stash
        lda #1
        sta cut_active
        lda #0
        sta park_pending
        sta light_pending
        sta shim_on
        sta shim_parked
        sta shim_n
        sta anim_hdr
        lda #0
        sta mux_first           ; no player sprite: the multiplexer gets all eight
        sta park_pending
        sta shim_on
        sta shim_n
        sta shim_parked
        ; blank, black border, park the pinned sprite off screen
        lda #%00001011          ; display off (never read D011 back: bit 7 is the raster's bit 8)
        sta VIC_CTRL1
        lda #0
        sta VIC_BORDERCOLOR
        sta VIC_SPR0_Y
        lda #0                  ; sprite shared colour 0 = black outlines
        sta VIC_SPR_MCOLOR0
        lda #6                  ; sprite shared colour 1 = blue (stripe) for actor grids
        sta VIC_SPR_MCOLOR1
        jsr b64_cut_clear_text
        ; regs for the top band; the vblank keeps them set
        lda #CUT_D018
        sta VIC_VIDEO_ADR
        lda #%00011000          ; multicolour, 40 columns
        sta VIC_CTRL2
        lda #%00111011          ; bitmap, display on, 25 rows, yscroll 3
        sta VIC_CTRL1
        rts

; b64_cut_end: restore game RAM and the playfield's VIC layout.  The game
; calls b64_redraw afterwards.
b64_cut_end:
        lda #0
        sta cut_active
        lda #1
        sta mux_first
        lda #%00001011          ; display off (never read D011 back: bit 7 is the raster's bit 8)
        sta VIC_CTRL1
        B64_SET16 b64_ptr, CUT_BITMAP
        B64_SET16 b64_len, $2000
        B64_SET24 b64_reu, CUT_STASH
        jsr b64_fetch
        lda #1
        sta VIC_SPR_MCOLOR1
        lda #TEXT_D018
        sta VIC_VIDEO_ADR
        lda #%00010000          ; 38 columns, multicolour
        sta VIC_CTRL2
        lda #%00010011          ; text, display on, 24 rows
        sta VIC_CTRL1
        rts

; ---------------------------------------------------------------------------
; b64_cut_still: b64_reu = still slot.  Loads it under a blanked display.
b64_cut_still:
        lda b64_reu
        sta still_base
        lda b64_reu+1
        sta still_base+1
        lda b64_reu+2
        sta still_base+2
        lda #%00001011          ; display off (never read D011 back: bit 7 is the raster's bit 8)
        sta VIC_CTRL1
        ; background byte
        B64_SET16 b64_ptr, cut_bg
        B64_SET16 b64_len, 1
        jsr b64_fetch
        jsr reu_advance_len
        lda cut_bg
        sta VIC_BG_COLOR0
        ; bitmap 8000
        B64_SET16 b64_ptr, CUT_BITMAP
        B64_SET16 b64_len, 8000
        jsr b64_fetch
        jsr reu_advance_len
        ; colour cells 1000
        B64_SET16 b64_ptr, CUT_BMSCREEN
        B64_SET16 b64_len, 1000
        jsr b64_fetch
        jsr reu_advance_len
        ; colour RAM 1000 (rows 20-24 are then overwritten by the text band colours)
        B64_SET16 b64_ptr, B64_COLOR_RAM
        B64_SET16 b64_len, 1000
        jsr b64_fetch
        jsr reu_advance_len
        B64_SET16 b64_ptr, shim_n
        B64_SET16 b64_len, 239
        jsr b64_fetch
        lda shim_n
        cmp #120
        bcc :+
        lda #0
        sta shim_n
:       jsr shim_precompute
        jsr text_colours
        lda #%00111011          ; bitmap, display on, 25 rows, yscroll 3
        sta VIC_CTRL1
        rts

; ---------------------------------------------------------------------------
; b64_cut_blit: b64_reu = block slot (w, h, bitmap rows, screen, colour),
; A = cell x, X = cell y.  DMAs the block into the still.
b64_cut_blit:
        sta blk_x
        stx blk_y
        B64_SET16 b64_ptr, blk_w
        B64_SET16 b64_len, 2
        jsr b64_fetch
        jsr reu_advance_len
        ; bitmap rows
        lda #0
        sta blk_row
@brow:  jsr bitmap_dest         ; b64_ptr = bitmap address of (blk_x, blk_y + row)
        lda blk_w
        asl
        asl
        asl
        sta b64_len
        lda #0
        sta b64_len+1
        jsr b64_fetch
        jsr reu_advance_len
        inc blk_row
        lda blk_row
        cmp blk_h
        bne @brow
        ; screen rows
        lda #0
        sta blk_row
@srow:  lda #>CUT_BMSCREEN
        jsr cell_dest
        lda blk_w
        sta b64_len
        lda #0
        sta b64_len+1
        jsr b64_fetch
        jsr reu_advance_len
        inc blk_row
        lda blk_row
        cmp blk_h
        bne @srow
        ; colour rows
        lda #0
        sta blk_row
@crow:  lda #>B64_COLOR_RAM
        jsr cell_dest
        lda blk_w
        sta b64_len
        lda #0
        sta b64_len+1
        jsr b64_fetch
        jsr reu_advance_len
        inc blk_row
        lda blk_row
        cmp blk_h
        bne @crow
        rts

; b64_cut_restore: A = cell x, X = cell y, Y = w, blk_h set by caller via
; b64_val (low byte).  Copies the still's original cells back over a prop.
b64_cut_restore:
        sta blk_x
        stx blk_y
        sty blk_w
        lda b64_val
        sta blk_h
        lda #0
        sta blk_row
@row:   jsr restore_row
        inc blk_row
        lda blk_row
        cmp blk_h
        beq @done
        jmp @row
@done:  rts

; restore_row: cells (blk_x .. blk_x+blk_w) of still row (blk_y + blk_row)
restore_row:
        ; bitmap: still_base + 1 + ((y+row)*40 + x)*8
        jsr bitmap_dest
        jsr cell_offset         ; blk_tmp = (y+row)*40 + x
        lda blk_tmp
        asl
        rol blk_tmp+1
        asl
        rol blk_tmp+1
        asl
        rol blk_tmp+1
        clc
        adc #1
        sta b64_reu
        lda blk_tmp+1
        adc #0
        sta b64_reu+1
        lda #0
        sta b64_reu+2
        jsr reu_add_base
        lda blk_w
        asl
        asl
        asl
        sta b64_len
        lda #0
        sta b64_len+1
        jsr b64_fetch
        ; screen: still_base + 8001 + off
        lda #>CUT_BMSCREEN
        jsr cell_dest
        jsr cell_offset
        lda blk_tmp
        clc
        adc #<8001
        sta b64_reu
        lda blk_tmp+1
        adc #>8001
        sta b64_reu+1
        lda #0
        sta b64_reu+2
        jsr reu_add_base
        lda blk_w
        sta b64_len
        lda #0
        sta b64_len+1
        jsr b64_fetch
        ; colour: still_base + 9001 + off
        lda #>B64_COLOR_RAM
        jsr cell_dest
        jsr cell_offset
        lda blk_tmp
        clc
        adc #<9001
        sta b64_reu
        lda blk_tmp+1
        adc #>9001
        sta b64_reu+1
        lda #0
        sta b64_reu+2
        jsr reu_add_base
        lda blk_w
        sta b64_len
        lda #0
        sta b64_len+1
        jmp b64_fetch

; blk_tmp = (blk_y + blk_row) * 40 + blk_x
cell_offset:
        lda blk_y
        clc
        adc blk_row
        sta blk_tmp
        lda #0
        sta blk_tmp+1
        ; *40 = *32 + *8
        lda blk_tmp
        asl
        asl
        asl                     ; *8 (fits: row <= 24 -> 192)
        sta b64_tmp+6
        lda #0
        sta b64_tmp+7
        asl b64_tmp+6
        rol b64_tmp+7
        asl b64_tmp+6
        rol b64_tmp+7           ; *32
        lda blk_tmp
        asl
        asl
        asl
        clc
        adc b64_tmp+6
        sta blk_tmp
        lda b64_tmp+7
        adc #0
        sta blk_tmp+1
        lda blk_tmp
        clc
        adc blk_x
        sta blk_tmp
        bcc :+
        inc blk_tmp+1
:       rts

; b64_ptr = CUT_BITMAP + cell_offset * 8
bitmap_dest:
        jsr cell_offset
        lda blk_tmp
        asl
        rol blk_tmp+1
        asl
        rol blk_tmp+1
        asl
        rol blk_tmp+1
        sta b64_ptr
        lda blk_tmp+1
        clc
        adc #>CUT_BITMAP
        sta b64_ptr+1
        rts

; A = page of a 1000-byte cell table -> b64_ptr = table + cell_offset
cell_dest:
        sta b64_tmp+5
        jsr cell_offset
        lda blk_tmp
        sta b64_ptr
        lda blk_tmp+1
        clc
        adc b64_tmp+5
        sta b64_ptr+1
        rts

; b64_reu += still_base
reu_add_base:
        lda b64_reu
        clc
        adc still_base
        sta b64_reu
        lda b64_reu+1
        adc still_base+1
        sta b64_reu+1
        lda b64_reu+2
        adc still_base+2
        sta b64_reu+2
        rts

; ---------------------------------------------------------------------------
; text band: rows 20-24 of the text screen
b64_cut_clear_text:
        ldx #0
        lda #(B64_FONT_BASE + ' ' - 32)
@l:     sta CUT_TEXT + 20*40,x
        sta CUT_TEXT + 20*40 + 100,x
        inx
        cpx #100
        bne @l
        jmp text_colours

text_colours:
        ldx #0
        lda #1
@l:     sta B64_COLOR_RAM + 20*40,x
        sta B64_COLOR_RAM + 20*40 + 100,x
        inx
        cpx #100
        bne @l
        rts

; b64_cut_text: A = row (20-24), X = column, string at (b64_val)
b64_cut_text:
        ldy #1
        sty cut_heavy           ; the shimmer waits a frame (b64_cut_frame)
        sec
        sbc #20
        ; ptr = CUT_TEXT + 800 + (row-20)*40 + col
        sta b64_tmp
        lda #0
        sta b64_ptr+1
        lda b64_tmp
        asl
        asl
        asl                     ; *8
        sta b64_ptr
        lda b64_tmp
        asl
        asl
        asl
        asl
        asl                     ; *32
        clc
        adc b64_ptr
        sta b64_ptr
        txa
        clc
        adc b64_ptr
        sta b64_ptr
        bcc :+
        inc b64_ptr+1
:       lda b64_ptr
        clc
        adc #<(CUT_TEXT + 800)
        sta b64_ptr
        lda b64_ptr+1
        adc #>(CUT_TEXT + 800)
        sta b64_ptr+1
        ldy #0
@l:     lda (b64_val),y
        beq @done
        sec
        sbc #32
        clc
        adc #B64_FONT_BASE
        sta (b64_ptr),y
        iny
        bne @l
@done:  rts

; ---------------------------------------------------------------------------
; IRQ hooks, called by the core dispatcher while cut_active
cut_vblank:
        lda #CUT_D018
        sta VIC_VIDEO_ADR
        lda #%00111011          ; bitmap on for the top band
        sta VIC_CTRL1
        lda #%00011000
        sta VIC_CTRL2
        ; deferred park/unpark: runs in the border, in the same vblank as the
        ; sprite list swap, so the sprite form vanishes as the block appears.
        ; Only on a frame where the shimmer is in its base phase (blocks were
        ; composited against the unswapped still), so no cell is out of step.
        lda park_pending
        beq @done
        lda b64_frame
        and #4
        bne @done
        lda park_pending
        cmp #1
        bne @un
        jsr obj_blit
        jmp @clr
@un:    jsr obj_restore
@clr:   lda #0
        sta park_pending
@done:
        ; deferred lighting: a 2 KB state (background, 800 screen bytes,
        ; 800 colour bytes for the visible rows) streamed in the border on
        ; a base-phase frame, so the shimmer's swapped cells are never
        ; relit out of step.  About 1,900 cycles.
        lda light_pending
        beq @lit
        lda b64_frame
        and #4
        bne @lit
        lda light_addr
        sta b64_reu
        lda light_addr+1
        sta b64_reu+1
        lda light_addr+2
        sta b64_reu+2
        B64_SET16 b64_ptr, cut_bg
        B64_SET16 b64_len, 1
        jsr b64_fetch
        jsr reu_advance_len
        lda cut_bg
        sta VIC_BG_COLOR0
        B64_SET16 b64_ptr, CUT_BMSCREEN
        B64_SET16 b64_len, 800
        jsr b64_fetch
        jsr reu_advance_len
        B64_SET16 b64_ptr, B64_COLOR_RAM
        B64_SET16 b64_len, 800
        jsr b64_fetch
        lda #0
        sta light_pending
@lit:   rts

; b64_cut_light: b64_reu = address of a 2 KB lighting state: queue it for
; the next base-phase vertical blank.  A newer request replaces an older
; one that has not landed yet.
b64_cut_light:
        lda b64_reu
        sta light_addr
        lda b64_reu+1
        sta light_addr+1
        lda b64_reu+2
        sta light_addr+2
        lda #1
        sta light_pending
        rts

; shimmer: every 4th frame swap the two colour codes of each listed cell by
; exchanging the nibbles of its screen byte, so the dither pattern inverts and
; the reflection appears to move.  ~20 cycles per cell, in the border.
; shim_precompute: (column, row) pairs -> colour-cell addresses
shim_precompute:
        ldx #0
        ldy #0
@c:     cpx shim_n
        bcs @done
        lda shim_cells+1,y      ; row
        sta b64_tmp
        lda shim_cells,y        ; column
        pha
        ldy b64_tmp
        lda cut_row_lo,y
        sta b64_tmp+1
        lda cut_row_hi,y
        clc
        adc #>CUT_BMSCREEN
        sta shim_hi,x
        pla
        clc
        adc b64_tmp+1
        sta shim_lo,x
        bcc :+
        inc shim_hi,x
:       inx
        txa
        asl
        tay
        jmp @c
@done:  rts

; shim_mask: flag (bit 7 of shim_hi) every cell inside the parked rectangle
; so the shimmer leaves it alone; A = 0 clears every flag
shim_mask:
        ldx #0
        ldy #0
@c:     cpx shim_n
        bcs @done
        lda shim_hi,x
        and #$7F
        sta shim_hi,x
        lda shim_parked
        beq @next
        lda shim_cells+1,y      ; row
        cmp shim_ry0
        bcc @next
        cmp shim_ry1
        bcs @next
        lda shim_cells,y        ; column
        cmp shim_rx0
        bcc @next
        cmp shim_rx1
        bcs @next
        lda shim_hi,x
        ora #$80
        sta shim_hi,x
@next:  inx
        iny
        iny
        jmp @c
@done:  rts

; b64_cut_frame: the engine's per-frame work in a cutscene, run from the
; main loop after the game callback.  Every 4th frame it swaps the two
; colour codes of each listed reflection cell (nibble swap through a table)
; so the wet road moves.  It runs before the reflection rows are drawn, so
; the change lands within the frame; and it runs here, not in the vertical
; blank, because 80 cells cost about 4,000 cycles and the interrupt must
; stay short.  Cells under a parked block are flagged and skipped.  A
; tick that drew text (about 7,300 cycles) puts the step off to the next
; frame: the two together overrun the frame (2026-09-18, cutscene ticks).
b64_cut_frame:
        ldy cut_heavy
        lda #0
        sta cut_heavy
        lda shim_on
        beq @done
        lda b64_frame
        and #3
        bne :+
        inc shim_due            ; a step every fourth frame
:       lda shim_due
        beq @done
        tya
        bne @done               ; due, but this tick drew text: the next frame
        lda #0
        sta shim_due
        ldx #0
@cell:  cpx shim_n
        bcs @done
        lda shim_hi,x
        bmi @skip
        sta b64_ptr+1
        lda shim_lo,x
        sta b64_ptr
        ldy #0
        lda (b64_ptr),y
        sta b64_tmp+6
        asl
        asl
        asl
        asl
        sta b64_tmp+7
        lda b64_tmp+6
        lsr
        lsr
        lsr
        lsr
        ora b64_tmp+7
        sta (b64_ptr),y
@skip:  inx
        bne @cell
@done:  rts

; ---------------------------------------------------------------------------
; objects
; b64_obj_load: b64_reu = object address
b64_obj_load:
        lda b64_reu
        sta obj_base
        lda b64_reu+1
        sta obj_base+1
        lda b64_reu+2
        sta obj_base+2
        B64_SET16 b64_ptr, obj_hdr
        B64_SET16 b64_len, 40
        jsr b64_fetch
        jsr reu_advance_len     ; b64_reu = sprites
        lda b64_reu
        sta obj_spr
        lda b64_reu+1
        sta obj_spr+1
        lda b64_reu+2
        sta obj_spr+2
        ; + gw*gh*64
        lda obj_hdr
        sta b64_tmp
        lda #0
        ldx obj_hdr+1
:       clc
        adc b64_tmp
        dex
        bne :-
        tax                     ; n = gw*gh
        lda #0
        sta b64_len+1
        txa
        lsr
        lsr
        sta b64_len+1           ; n*64 high
        txa
        and #3
        asl
        asl
        asl
        asl
        asl
        asl
        sta b64_len
        jsr reu_advance_len
        lda b64_reu
        sta obj_bm
        lda b64_reu+1
        sta obj_bm+1
        lda b64_reu+2
        sta obj_bm+2
        ; + cw*ch*8
        jsr obj_cells           ; A = cw*ch
        tax
        lsr
        lsr
        lsr
        lsr
        lsr
        sta b64_len+1
        txa
        and #31
        asl
        asl
        asl
        sta b64_len
        jsr reu_advance_len
        lda b64_reu
        sta obj_scr
        lda b64_reu+1
        sta obj_scr+1
        lda b64_reu+2
        sta obj_scr+2
        jsr obj_cells
        sta b64_len
        lda #0
        sta b64_len+1
        jsr reu_advance_len
        lda b64_reu
        sta obj_col
        lda b64_reu+1
        sta obj_col+1
        lda b64_reu+2
        sta obj_col+2
        jsr obj_cells
        sta b64_len
        lda #0
        sta b64_len+1
        jsr reu_advance_len
        lda b64_reu
        sta obj_anim
        lda b64_reu+1
        sta obj_anim+1
        lda b64_reu+2
        sta obj_anim+2
        B64_SET16 b64_ptr, anim_hdr
        B64_SET16 b64_len, 10
        jsr b64_fetch
        lda anim_hdr+1
        cmp #9
        bcc :+
        lda #0                  ; no animation section (garbage header): disable
        sta anim_hdr
:       lda #0
        sta anim_frame
        ; the lights section follows the animation section:
        ; anim size = 2 + nsprites + nframes * nsprites * 64
        lda #0
        sta obj_nlights
        sta lights_on           ; a new object's lights are off until LIGHTS says otherwise
        sta light_pending
        lda anim_hdr+1          ; nsprites (0 when there is no animation)
        clc
        adc #2
        sta b64_len
        lda #0
        sta b64_len+1
        jsr reu_advance_len
        lda anim_hdr            ; nframes
        beq @lights
        ldx anim_hdr+1          ; frames * sprites * 64: sprites <= 8, frames <= 8
        lda #0
:       clc
        adc anim_hdr
        dex
        bne :-                  ; A = frames * sprites (<= 64)
        ldx #0
        stx b64_len
        lsr
        ror b64_len
        lsr
        ror b64_len             ; * 64 = << 6: high = A >> 2, low = (A & 3) << 6
        sta b64_len+1
        jsr reu_advance_len
@lights:
        B64_SET16 b64_ptr, obj_nlights
        B64_SET16 b64_len, 65
        jsr b64_fetch
        lda obj_nlights
        cmp #5
        bcc :+
        lda #0                  ; no lights section (garbage count): none
        sta obj_nlights
:       rts

; b64_obj_lights: b64_reu = the baked lighting file, b64_ptr = lamp sprite
; frame address (24-bit in b64_ptr..+2 via b64_val), A = 1 on / 0 off.
; On: read the file's layout header and light the set from the object's
; position and patterns every frame it is drawn.  Off: restore state 0.
b64_obj_lights:
        sta lights_on
        lda b64_reu
        sta lights_slot
        lda b64_reu+1
        sta lights_slot+1
        lda b64_reu+2
        sta lights_slot+2
        lda b64_val
        sta lamp_slot
        lda b64_val+1
        sta lamp_slot+1
        lda b64_val+2
        sta lamp_slot+2
        lda #$FF
        sta light_cur
        lda lights_on
        beq @off
        ; the layout header sits at offset 1601 of state 0
        lda b64_reu
        clc
        adc #<1601
        sta b64_reu
        lda b64_reu+1
        adc #>1601
        sta b64_reu+1
        bcc :+
        inc b64_reu+2
:       B64_SET16 b64_ptr, light_hdr
        B64_SET16 b64_len, 34
        jsr b64_fetch
        rts
@off:   jsr b64_cut_light       ; state 0: the set as it is
        rts

; lights_tick: called from b64_obj_sprites with the object at obj_x/obj_y.
; For each light: its pattern entry for this frame; a lamp sprite if the
; light has one and is on; and the map for (light, position, colour),
; queued when it differs from the last one.
lights_tick:
        lda lights_on
        bne :+
        rts
:
        lda #0
        sta b64_tmp+4           ; light index
        sta b64_tmp+5           ; state chosen this frame, 0 = none yet
@light: lda b64_tmp+4
        cmp obj_nlights
        bcc :+
        jmp @apply
:
        asl
        asl
        asl
        asl
        tax                     ; X = record offset
        ; pattern: total = sum of frames; t = frame mod total; walk entries
        lda #0
        ldy obj_lights+4,x      ; npat
        sty b64_tmp+6
:       clc
        adc obj_lights+7,x      ; frames of entry (x + 6 + 2k + 1): sum via a walking index
        inx
        inx
        dey
        bne :-
        sta b64_tmp+7           ; total
        txa
        sec
        sbc b64_tmp+6
        sbc b64_tmp+6
        tax                     ; back to the record
        lda b64_frame
:       cmp b64_tmp+7
        bcc :+
        sbc b64_tmp+7
        jmp :-
:       ldy obj_lights+4,x
@walk:  cmp obj_lights+7,x
        bcc @entry
        sbc obj_lights+7,x
        inx
        inx
        dey
        bne @walk
        dex                     ; ran past (rounding): use the last entry
        dex
@entry: ldy obj_lights+6,x      ; the entry's colour, 0 = off
        ; X is now record + 2k; the record base is X - 2k; recover it by
        ; walking back is messy, so keep the base in b64_tmp+6
        sty b64_tmp+6
        lda b64_tmp+4
        asl
        asl
        asl
        asl
        tax
        lda b64_tmp+6
        bne :+
        jmp @next               ; off this frame: no lamp, no map
:
        ; lamp sprite
        lda obj_lights+3,x
        beq @map
        lda obj_x
        clc
        adc obj_lights,x
        sta b64_spr_x
        lda obj_x+1
        adc #0
        sta b64_spr_x+1
        lda obj_y
        clc
        adc obj_lights+1,x      ; dy, signed
        sta b64_spr_y
        lda b64_tmp+6
        sta b64_spr_colour
        lda #23
        sec
        sbc b64_tmp+4
        sta b64_spr_slot
        lda #0
        sta b64_spr_flags
        lda lamp_slot
        sta b64_reu
        lda lamp_slot+1
        sta b64_reu+1
        lda lamp_slot+2
        sta b64_reu+2
        jsr b64_spr_add
@map:   ; state = base + pos * ncol + colour index
        lda b64_tmp+4
        asl
        asl
        asl
        sec
        sbc b64_tmp+4           ; light * 7
        clc
        adc #6
        tay                     ; Y = 6 + light * 7: the light's entry in the file header
        ; colour index
        ldx #0
@ci:    lda light_hdr+3,y       ; colours[x]
        cmp b64_tmp+6
        beq @found
        iny
        inx
        cpx #4
        bcc @ci
        jmp @next               ; colour not in the file
@found: stx b64_tmp+6           ; colour index
        tya
        sec
        sbc b64_tmp+6
        tay                     ; Y = 6 + light * 7 again (the search advanced Y once per colour tried)
        ; pos = (obj_x - x0) / xstep, clamped to npos - 1
        lda obj_x
        sec
        sbc light_hdr+2
        sta b64_tmp+7
        lda obj_x+1
        sbc light_hdr+3
        bcs :+
        lda #0                  ; left of x0
        sta b64_tmp+7
        beq @div
:       bne @max                ; 256 or more px past x0: clamp
        lda b64_tmp+7
@div:   ldx #0
:       cmp light_hdr+4         ; xstep
        bcc @pos
        sbc light_hdr+4
        inx
        jmp :-
@max:   ldx light_hdr+5
        dex
        jmp @pos2
@pos:   cpx light_hdr+5
        bcc @pos2
        ldx light_hdr+5
        dex
@pos2:  ; state = base + pos * ncol + ci  (8-bit state numbers suffice here)
        txa
        sta b64_tmp+7
        lda #0
        ldx light_hdr+2,y       ; ncol
        bne :+
        jmp @next
:
:       clc
        adc b64_tmp+7
        dex
        bne :-
        clc
        adc b64_tmp+6           ; + colour index
        clc
        adc light_hdr,y         ; + base lo
        sta b64_tmp+5           ; the state for this light this frame
@next:  inc b64_tmp+4
        jmp @light
@apply: lda b64_tmp+5
        beq @done               ; no light on: leave the last map (the pattern's off entries)
        cmp light_cur
        beq @done
        sta light_cur
        ; address = lights_slot + state * 2048
        lda lights_slot
        sta b64_reu
        lda b64_tmp+5
        and #31
        asl
        asl
        asl
        clc
        adc lights_slot+1
        sta b64_reu+1
        lda #0
        adc #0
        sta b64_tmp+6
        lda b64_tmp+5
        lsr
        lsr
        lsr
        lsr
        lsr
        clc
        adc b64_tmp+6
        adc lights_slot+2
        sta b64_reu+2
        jsr b64_cut_light
@done:  rts

; b64_obj_anim: A = frame
b64_obj_anim:
        ldx anim_hdr
        beq :+
        sta anim_frame
:       rts

; anim_lookup: X = grid sprite k -> C=1 and b64_reu = frame address if the
; current animation frame overrides that sprite, else C=0
anim_lookup:
        lda anim_hdr            ; nframes
        beq @no
        ldy #0
@scan:  cpy anim_hdr+1
        bcs @no
        txa
        cmp anim_hdr+2,y
        beq @hit
        iny
        bne @scan
@no:    clc
        rts
@hit:   ; offset = 2 + m + (frame*m + j) * 64
        lda anim_frame
        sta b64_tmp+2
        lda #0
        ldx anim_hdr+1
        beq :++
:       clc
        adc b64_tmp+2
        dex
        bne :-
:       sty b64_tmp+2
        clc
        adc b64_tmp+2           ; frame*m + j
        tax
        lda #0
        sta b64_reu+1
        txa
        lsr
        lsr
        sta b64_reu+1           ; (frame*m+j)*64 high
        txa
        and #3
        asl
        asl
        asl
        asl
        asl
        asl
        sta b64_reu
        lda anim_hdr+1
        clc
        adc #2
        clc
        adc b64_reu
        sta b64_reu
        bcc :+
        inc b64_reu+1
:       lda b64_reu
        clc
        adc obj_anim
        sta b64_reu
        lda b64_reu+1
        adc obj_anim+1
        sta b64_reu+1
        lda #0
        adc obj_anim+2
        sta b64_reu+2
        sec
        rts

; A = cw*ch
obj_cells:
        lda obj_hdr+2
        sta b64_tmp
        lda #0
        ldx obj_hdr+3
:       clc
        adc b64_tmp
        dex
        bne :-
        rts

; b64_obj_sprites: b64_spr_x/b64_spr_y = top-left, X = first slot.
b64_obj_sprites:
        stx obj_slot
        lda b64_spr_x
        sta obj_x
        lda b64_spr_x+1
        sta obj_x+1
        lda b64_spr_y
        sta obj_y
        lda #0
        sta obj_k
        sta obj_gy
@row:   lda #0
        sta obj_gx
@col:   ; x = obj_x + gx*24
        lda obj_gx
        asl
        asl
        asl
        sta b64_tmp
        asl
        clc
        adc b64_tmp
        clc
        adc obj_x
        sta b64_spr_x
        lda obj_x+1
        adc #0
        sta b64_spr_x+1
        ; y = obj_y + gy*21
        lda obj_gy
        asl
        asl
        asl
        asl
        sta b64_tmp
        lda obj_gy
        asl
        asl
        clc
        adc b64_tmp
        clc
        adc obj_gy
        clc
        adc obj_y
        sta b64_spr_y
        lda obj_slot
        clc
        adc obj_k
        sta b64_spr_slot
        lda obj_hdr+5
        sta b64_spr_colour
        lda #B64_SPR_FLAG_MC
        sta b64_spr_flags
        ; frame = animation override, or obj_spr + k*64
        ldx obj_k
        jsr anim_lookup
        bcs @have
        lda obj_k
        asl
        asl
        asl
        asl
        asl
        asl
        sta b64_tmp
        lda obj_k
        lsr
        lsr
        sta b64_tmp+1
        lda obj_spr
        clc
        adc b64_tmp
        sta b64_reu
        lda obj_spr+1
        adc b64_tmp+1
        sta b64_reu+1
        lda obj_spr+2
        adc #0
        sta b64_reu+2
@have:  jsr b64_spr_add
        inc obj_k
        inc obj_gx
        lda obj_gx
        cmp obj_hdr
        beq :+
        jmp @col
:       inc obj_gy
        lda obj_gy
        cmp obj_hdr+1
        beq :+
        jmp @row
:       jmp lights_tick

b64_obj_park:
        sta park_x
        stx park_y
        lda #1
        sta park_pending
        rts

b64_obj_unpark:
        sta park_x
        stx park_y
        lda #2
        sta park_pending
        rts

; obj_blit: for each block row with visible cells, DMA bitmap, screen and
; colour spans from the object into the still at (park_x, park_y).
obj_blit:
        lda park_x
        sta shim_rx0
        clc
        adc obj_hdr+2
        sta shim_rx1
        lda park_y
        sta shim_ry0
        clc
        adc obj_hdr+3
        sta shim_ry1
        lda #1
        sta shim_parked
        jsr shim_mask
        lda #0
        sta obj_k               ; row
@row:   ldx obj_k
        cpx obj_hdr+3
        bcc :+
        jmp @done
:
        txa
        asl
        tax
        lda obj_spans,x         ; first
        cmp obj_spans+1,x       ; last+1
        bne :+
        jmp @next               ; empty row
:
        sta b64_tmp+2           ; first
        lda obj_spans+1,x
        sec
        sbc b64_tmp+2
        sta b64_tmp+3           ; width
        ; destination cell (park_x + first, park_y + row)
        lda park_x
        clc
        adc b64_tmp+2
        sta blk_x
        lda park_y
        clc
        adc obj_k
        sta blk_y
        lda #0
        sta blk_row
        ; source offset t = row*cw + first
        lda obj_hdr+2
        sta b64_tmp
        lda #0
        ldx obj_k
        beq :++
:       clc
        adc b64_tmp
        dex
        bne :-
:       clc
        adc b64_tmp+2
        sta b64_tmp+4           ; t
        ; bitmap: obj_bm + t*8, len width*8
        jsr bitmap_dest
        lda b64_tmp+4
        asl
        asl
        asl
        sta b64_reu
        lda b64_tmp+4
        lsr
        lsr
        lsr
        lsr
        lsr
        sta b64_reu+1
        lda #0
        sta b64_reu+2
        lda b64_reu
        clc
        adc obj_bm
        sta b64_reu
        lda b64_reu+1
        adc obj_bm+1
        sta b64_reu+1
        lda b64_reu+2
        adc obj_bm+2
        sta b64_reu+2
        lda b64_tmp+3
        asl
        asl
        asl
        sta b64_len
        lda #0
        sta b64_len+1
        jsr b64_fetch
        ; screen: obj_scr + t, len width
        lda #>CUT_BMSCREEN
        jsr cell_dest
        lda obj_scr
        clc
        adc b64_tmp+4
        sta b64_reu
        lda obj_scr+1
        adc #0
        sta b64_reu+1
        lda obj_scr+2
        adc #0
        sta b64_reu+2
        lda b64_tmp+3
        sta b64_len
        lda #0
        sta b64_len+1
        jsr b64_fetch
        ; colour: obj_col + t, len width
        lda #>B64_COLOR_RAM
        jsr cell_dest
        lda obj_col
        clc
        adc b64_tmp+4
        sta b64_reu
        lda obj_col+1
        adc #0
        sta b64_reu+1
        lda obj_col+2
        adc #0
        sta b64_reu+2
        lda b64_tmp+3
        sta b64_len
        lda #0
        sta b64_len+1
        jsr b64_fetch
@next:  inc obj_k
        jmp @row
@done:  rts

; obj_restore: the same spans, restored from the still's original
obj_restore:
        lda #0
        sta shim_parked
        jsr shim_mask
        sta obj_k
@row:   ldx obj_k
        cpx obj_hdr+3
        bcs @done
        txa
        asl
        tax
        lda obj_spans,x
        cmp obj_spans+1,x
        bne :+
        jmp @next
:       sta b64_tmp+2
        lda obj_spans+1,x
        sec
        sbc b64_tmp+2
        sta blk_w
        lda park_x
        clc
        adc b64_tmp+2
        sta blk_x
        lda park_y
        clc
        adc obj_k
        sta blk_y
        lda #0
        sta blk_row
        jsr restore_row
@next:  inc obj_k
        jmp @row
@done:  rts

cut_split:
        lda #%00011011          ; bitmap off: rows 20-24 are text
        sta VIC_CTRL1
        lda #TEXT_D018
        sta VIC_VIDEO_ADR
        rts

.segment "RODATA"
cut_row_lo:
.repeat 25, r
        .byte <(r*40)
.endrepeat
cut_row_hi:
.repeat 25, r
        .byte >(r*40)
.endrepeat

.segment "RODATA"
