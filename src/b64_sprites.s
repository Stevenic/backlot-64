; backlot-64 sprite multiplexer.
;
; Hardware sprite 0 is pinned (the game writes its registers directly).
; Hardware sprites 1-7 are multiplexed across up to 24 virtual sprites.
; The game builds a list each frame with b64_spr_begin / b64_spr_add /
; b64_spr_end.  The list is sorted by y.  At the vertical blank the first
; seven entries are written to the hardware and a chain of raster
; interrupts reassigns each hardware sprite to its next entry once the
; previous one has finished displaying.
;
; Lists are double-buffered: the game writes list B while the chain reads
; list A, and they swap at the vertical blank.

.include "b64.inc"

.export b64_spr_vblank
.export mux_chain
.export mux_schedule
.export spr_slots_reset
.export mux_first
.import split_done
.import split_line
.import cut_active

.ifdef FRAME_TRACE
.import ftrace_log
.endif

.segment "LOWRAM"
spr_ready:      .res 1          ; 1 = a finished list waits for the next vblank
vs_xlo:         .res 48
vs_xhi:         .res 48
vs_y:           .res 48
vs_frm:         .res 48
vs_col:         .res 48
vs_flg:         .res 48
vs_order:       .res 48
; per-slot cache of the REU address currently loaded, so a frame is fetched
; only when an entity's type, heading, or state actually changes
slot_lo:        .res B64_SPR_SLOTS
slot_hi:        .res B64_SPR_SLOTS
slot_bk:        .res B64_SPR_SLOTS
mux_first:      .res 1          ; first hardware sprite the multiplexer may use: 1 (sprite 0 pinned) or 0
hw_count:       .res 1          ; 8 - mux_first

.segment "RODATA"
hw2:            .byte 0, 2, 4, 6, 8, 10, 12, 14
bit_set:        .byte $01, $02, $04, $08, $10, $20, $40, $80
bit_clr:        .byte $FE, $FD, $FB, $F7, $EF, $DF, $BF, $7F

.segment "CODE"

; ---------------------------------------------------------------------------
b64_spr_begin:
        FTRACE 4
:       lda spr_ready           ; the previous list must be taken first
        bne :-
        FTRACE 5
        sta spr_count_b
        rts

b64_spr_add:
        ldx spr_count_b
        cpx #B64_MAX_SPRITES
        bcs @full
        inc spr_count_b
        ldx b64_spr_slot
        jsr slot_load
        ldx spr_count_b
        dex
        txa
        clc
        adc spr_base_b
        tax
        lda b64_spr_x
        sta vs_xlo,x
        lda b64_spr_x+1
        sta vs_xhi,x
        lda b64_spr_y
        sta vs_y,x
        lda b64_spr_slot
        sta vs_frm,x
        lda b64_spr_colour
        sta vs_col,x
        lda b64_spr_flags
        sta vs_flg,x
@full:  rts

; forget every slot's contents so the next add fetches
spr_slots_reset:
        lda #0
        sta spr_ready
        ldx #B64_SPR_SLOTS-1
        lda #$FF
:       sta slot_lo,x
        sta slot_hi,x
        sta slot_bk,x
        dex
        bpl :-
        rts

; b64_spr_pinned: b64_reu = frame source for hardware sprite 0 (slot 0)
b64_spr_pinned:
        ldx #0
        jsr slot_load
        lda #0
        sta b64_spr0_frame
        rts

; slot_load: X = slot, b64_reu = frame address.  Fetches 64 bytes into the
; slot's VIC RAM if the address differs from what the slot holds.
slot_load:
        lda b64_reu
        cmp slot_lo,x
        bne @load
        lda b64_reu+1
        cmp slot_hi,x
        bne @load
        lda b64_reu+2
        cmp slot_bk,x
        bne @load
        rts
@load:  FTRACE 12
        lda b64_reu
        sta slot_lo,x
        lda b64_reu+1
        sta slot_hi,x
        lda b64_reu+2
        sta slot_bk,x
        ; C64 address = B64_SPRITES + slot*64
        txa
        lsr
        lsr
        clc
        adc #>B64_SPRITES
        sta b64_ptr+1
        txa
        and #3
        asl
        asl
        asl
        asl
        asl
        asl                     ; (slot & 3) << 6
        sta b64_ptr
        lda #64
        sta b64_len
        lda #0
        sta b64_len+1
        jmp b64_fetch

; Insertion sort of the build list's order array by y.
; b64_tmp+0 = lo, +1 = hi bound, +2 = key, +3 = key y, +4 = i, +5 = left count
b64_spr_end:
        FTRACE 10
        lda spr_count_b
        beq @done
        clc
        adc spr_base_b
        sta b64_tmp+1
        ldx spr_base_b
        stx b64_tmp
@id:    txa
        sta vs_order,x
        inx
        cpx b64_tmp+1
        bne @id
        ldx b64_tmp
        inx
@outer:
        cpx b64_tmp+1
        bcs @done
        lda vs_order,x
        sta b64_tmp+2
        tay
        lda vs_y,y
        sta b64_tmp+3
        stx b64_tmp+4
        txa
        sec
        sbc b64_tmp
        sta b64_tmp+5
@inner:
        lda b64_tmp+5
        beq @place
        dex
        ldy vs_order,x
        lda vs_y,y
        cmp b64_tmp+3
        bcc @stop
        beq @stop
        lda vs_order,x
        sta vs_order+1,x
        dec b64_tmp+5
        jmp @inner
@stop:  inx
@place: lda b64_tmp+2
        sta vs_order,x
        ldx b64_tmp+4
        inx
        jmp @outer
@done:  lda #1
        sta spr_ready
        rts

; ---------------------------------------------------------------------------
; mux_assign: Y = sorted position in the show list.  Writes hardware sprite
; mux_hw from that entry and advances mux_hw.  IRQ context: uses only
; mux_tmp / mux_tmp2.
mux_assign:
        tya
        clc
        adc spr_base_s
        tax
        lda vs_order,x
        tay                     ; Y = entry
        ldx mux_hw
        lda hw2,x
        sta mux_tmp
        lda vs_xlo,y
        ldx mux_tmp
        sta VIC_SPR0_X,x
        lda vs_y,y
        sta VIC_SPR0_Y,x
        ldx mux_hw
        lda vs_col,y
        sta VIC_SPR0_COLOR,x
        lda vs_frm,y
        clc
        adc #B64_SPR_BASE
        sta B64_SPR_PTR_A,x
        sta B64_SPR_PTR_B,x
        sta B64_SPR_PTR_C,x
        ; x msb
        lda vs_xhi,y
        beq @clr
        lda VIC_SPR_HI_X
        ora bit_set,x
        bne @w1
@clr:   lda VIC_SPR_HI_X
        and bit_clr,x
@w1:    sta VIC_SPR_HI_X
        ; multicolour
        lda vs_flg,y
        and #B64_SPR_FLAG_MC
        beq @nomc
        lda VIC_SPR_MCOLOR
        ora bit_set,x
        bne @w2
@nomc:  lda VIC_SPR_MCOLOR
        and bit_clr,x
@w2:    sta VIC_SPR_MCOLOR
        ; priority
        lda vs_flg,y
        and #B64_SPR_FLAG_PRIO
        beq @nopr
        lda VIC_SPR_BG_PRIO
        ora bit_set,x
        bne @w3
@nopr:  lda VIC_SPR_BG_PRIO
        and bit_clr,x
@w3:    sta VIC_SPR_BG_PRIO
        inx
        cpx #8
        bne :+
        ldx mux_first
:       stx mux_hw
        rts

; mux_schedule: set the raster line for the next reassignment, or 255.
mux_schedule:
        ldy mux_next
        cpy spr_count_s
        bcs @vb
        tya
        sec
        sbc hw_count
        clc
        adc spr_base_s
        tax
        lda vs_order,x
        tax
        lda vs_y,x
        clc
        adc #22
        bcs @vb
        cmp #250
        bcs @vb
        sta irq_line
        jmp set_raster
@vb:    lda #255
        sta irq_line
        jmp set_raster

; set the raster compare to A, but never past the HUD split while it is pending
set_raster:
        ldx split_done
        bne :+
        cmp split_line
        bcc :+
        lda split_line
:       sta VIC_HLINE
        rts

; ---------------------------------------------------------------------------
; b64_spr_vblank: swap lists, write the first seven, start the chain.
b64_spr_vblank:
        lda #0
        sta split_done
        lda cut_active
        beq :+
        lda #B64_CUT_SPLIT
        bne :++
:       lda scr_ys
        clc
        adc #B64_SPLIT_BASE
:       sta split_line
        lda spr_ready           ; only a finished list is shown
        beq @keep
        FTRACE 7
        lda #0
        sta spr_ready
        lda spr_base_b
        ldx spr_base_s
        sta spr_base_s
        stx spr_base_b
        lda spr_count_b
        sta spr_count_s
@keep:
        lda #8
        sec
        sbc mux_first
        sta hw_count
        lda mux_first
        sta mux_hw
        ldy #0
@first: cpy spr_count_s
        bcs @firstdone
        cpy hw_count
        bcs @firstdone
        sty mux_tmp2
        jsr mux_assign
        ldy mux_tmp2
        iny
        jmp @first
@firstdone:
        sty mux_next
        ; enable the hardware sprites in use: the pinned sprite 0 when mux_first is 1,
        ; plus the n assigned this frame -> mask = 2^(n + mux_first) - 1
        tya
        clc
        adc mux_first
        tay
        lda ena_mask,y
        sta VIC_SPR_ENA
        jmp mux_schedule

; chain IRQ: reassign as many entries as are due, then schedule the next
mux_chain:
@again:
        ldy mux_next
        cpy spr_count_s
        bcs @done
        jsr mux_assign
        inc mux_next
        jsr mux_schedule
        lda irq_line
        cmp #255
        beq @done
        cmp VIC_HLINE
        bcc @again
        beq @again
@done:  rts

.segment "RODATA"
; masks[k] = 2^k - 1 for k hardware sprites in use (0..8)
ena_mask:       .byte $00, $01, $03, $07, $0F, $1F, $3F, $7F, $FF
