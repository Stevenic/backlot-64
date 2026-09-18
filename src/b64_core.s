; backlot-64 core: boot, VIC bank, IRQ chain, frame loop.
;
; The BASIC stub jumps to the first byte of the engine's CODE segment, which
; must be this file's trampoline into the game's `game_main`.

.include "b64.inc"

.import game_main
.import scr_vblank
.import b64_scroll_prepare
.import b64_spr_vblank
.import mux_chain
.import hud_split
.import hud_init
.import mux_schedule
.import split_done
.import split_line
.import spr_slots_reset
.import cut_active
.import cut_vblank
.import b64_cut_frame
.import cut_split
.import mux_first

RASTER_VBLANK   = 255

.segment "LOADADDR"
        .word $0801
.segment "EXEHDR"
        .word next_line
        .word 10
        .byte $9E, "2061", 0
next_line:
        .word 0

.segment "LOWRAM"
irq_save:       .res 20

.segment "CODE"
_start:
        jmp game_main

.ifdef FRAME_TRACE
.export ftrace_log
ftrace_log:
        stx $E3FE
        ldx $E3FF
        cpx #252
        bcs @full               ; the ring is a one-shot log: stop when full
        sta $E400,x
        lda b64_frame
        sta $E401,x
        lda VIC_HLINE
        sta $E402,x
        inx
        inx
        inx
        stx $E3FF
@full:  ldx $E3FE
        rts
.endif

; ---------------------------------------------------------------------------
b64_init:
        sei
        lda #$35                ; RAM everywhere except I/O
        sta $01

        lda #$7F
        sta CIA1_ICR
        sta CIA2_ICR
        lda CIA1_ICR
        lda CIA2_ICR

        ; VIC bank 1 ($4000-$7FFF)
        lda CIA2_DDRA
        ora #$03
        sta CIA2_DDRA
        lda CIA2_PRA
        and #$FC
        ora #$02
        sta CIA2_PRA

        lda #%00000010          ; screen A, charset $4800
        sta VIC_VIDEO_ADR
        lda #%00010011          ; display on, 24 rows, yscroll 3
        sta VIC_CTRL1
        lda #%00010000          ; multicolour, 38 columns, xscroll 0
        sta VIC_CTRL2
        lda #0
        sta VIC_SPR_ENA
        sta VIC_SPR_HI_X
        sta VIC_SPR_EXP_X
        sta VIC_SPR_EXP_Y
        sta VIC_SPR_BG_PRIO
        sta VIC_BORDERCOLOR
        sta VIC_BG_COLOR0

        ; clear both screens and colour RAM
        ldx #0
        lda #0
@clr:   sta B64_SCREEN_A,x
        sta B64_SCREEN_A+$100,x
        sta B64_SCREEN_A+$200,x
        sta B64_SCREEN_A+$300,x
        sta B64_SCREEN_B,x
        sta B64_SCREEN_B+$100,x
        sta B64_SCREEN_B+$200,x
        sta B64_SCREEN_B+$300,x
        sta B64_COLOR_RAM,x
        sta B64_COLOR_RAM+$100,x
        sta B64_COLOR_RAM+$200,x
        sta B64_COLOR_RAM+$300,x
        inx
        bne @clr

        ; engine state
        lda #0
        sta scr_front
        sta scr_pending
        sta b64_frame
        sta scr_last_frame
        sta b64_joy
        sta b64_spr0_frame
        sta bench_max
        sta bench_max+1
        sta bench_max+2
        lda #$FF
        sta scr_newcol
        sta scr_newrow
        lda #>B64_SCREEN_B
        sta scr_back_hi
        lda #0
        sta spr_count_b
        sta spr_count_s
        sta spr_base_b
        sta mux_next
        lda #24
        sta spr_base_s
        lda #1
        sta mux_hw
        lda #255
        sta irq_line
        jsr spr_slots_reset
        jsr b64_page_flush
        jsr b64_plat_probe
        lda #0
        sta cut_active
        lda #1
        sta mux_first
        lda #0
        sta split_done
        jsr b64_hud_clear
        jsr hud_init

        ; raster IRQ at the bottom of the display
        lda #RASTER_VBLANK
        sta VIC_HLINE
        lda VIC_CTRL1
        and #$7F
        sta VIC_CTRL1
        lda #$01
        sta VIC_IMR
        sta VIC_IRR
        lda #<irq
        sta $FFFE
        lda #>irq
        sta $FFFF
        rts

; ---------------------------------------------------------------------------
b64_set_callback:
        sta b64_cb
        stx b64_cb+1
        rts

; The frame loop.  Once per frame: read input, run the game's callback, then
; prepare the next frame's scroll work into the back buffer.  The IRQ at the
; bottom of the display applies it.
b64_run:
        cli
@loop:
        lda b64_frame
        cmp scr_last_frame
        beq @loop
        sta scr_last_frame
        lda cut_active
        bne @cut
        lda scr_pending
        bne @loop               ; previous frame's work not yet applied

        jsr read_joystick
        jsr call_cb
        jsr b64_bench_begin
        jsr b64_scroll_prepare
        jsr b64_bench_end
        jmp @loop
@cut:   ; cutscene: no scroller, the callback drives everything
        jsr read_joystick
        FTRACE 3
        jsr call_cb
        FTRACE 6
        jsr b64_cut_frame       ; the shimmer, after the callback and before the rows it touches are drawn
        jmp @loop

call_cb:
        jmp (b64_cb)

read_joystick:
        lda CIA1_PRA
        eor #$FF
        and #$1F
        sta b64_joy
        rts

; ---------------------------------------------------------------------------
irq:
        pha
        txa
        pha
        tya
        pha
        lda VIC_HLINE
        cmp #250
        bcc :+
        jmp @vblank
:       cmp split_line
        bcc @tochain
        lda split_done
        bne @tochain
        lda cut_active
        beq @hud
        jmp @split
@tochain:
        jmp @chain
@split:
        jsr cut_split
        lda #1
        sta split_done
        jmp @sched
@hud:   jsr hud_split
@sched: jsr mux_schedule        ; continue the chain past the split
        jmp @ack
@vblank:
        FTRACE 1
        ; the vblank work does DMA and uses the shared scratch while the main
        ; loop may be in the middle of using it: keep the main loop's copy
        ldx #19
:       lda b64_ptr,x
        sta irq_save,x
        dex
        bpl :-
        inc b64_frame
        lda cut_active
        bne @cutvb
        jsr scr_vblank
        jmp @spr
@cutvb: jsr b64_spr_vblank      ; the sprite registers first, while the raster is still in the border
        jsr cut_vblank
        jmp @vbchk
@spr:   jsr b64_spr_vblank
@vbchk:
        ; if the vblank work ran into the next frame past the first chain
        ; line, that interrupt would never fire and the chain would stall
        ; for a frame: catch up now instead
        lda irq_line
        cmp #255
        beq @vbdone
        lda VIC_CTRL1
        bmi @vbdone                ; raster bit 8: still in the lower border
        lda VIC_HLINE
        cmp #250
        bcs @vbdone
        cmp irq_line
        bcc @vbdone
        jsr mux_chain
        jmp @vbdone
@vbdone:
        FTRACE 2
        ldx #9                  ; restore $06-$0F and $12-$19, not the frame counter
:       lda irq_save,x
        sta b64_ptr,x
        dex
        bpl :-
        ldx #7
:       lda irq_save+12,x
        sta b64_tmp,x
        dex
        bpl :-
        jmp @ack
@chain: jsr mux_chain
@ack:   lda #$01
        sta VIC_IRR
        pla
        tay
        pla
        tax
        pla
        rti
