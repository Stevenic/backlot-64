; backlot-64 benchmark: DMA transfer times and p-code versus assembly.
;
; Interrupts stay off so nothing else runs.  Each test waits for a known
; raster line, runs once between b64_bench_begin and b64_bench_end, and
; stores the 24-bit cycle count in the results table at $E000.
;
;   0-4   fetch 64 / 256 / 1024 / 4096 / 8192 bytes, started at line 251 (border)
;   5-9   the same, started at line 100 (inside the display, badlines)
;   10    one VM tick of a script that is only LOOP: 64 opcodes (cache warm)
;   11    one VM tick of the cutscene's drive loop body: 71 opcodes, 4 steps
;   12    64 iterations of the same drive step written in assembly
;   13    one VM tick of 63 ADD v,w then YIELD (65 opcodes with the restart JMP)
;   14    (platform flags and REU size, not a time)
;   15-17 one scroller prepare for a cell crossing to the right, down, and
;         diagonally, started at line 100 with the example tileset and world
;   18-19 b64_spr_end for 32 sprites in the multiplexer harness's pattern:
;         the first list (from submission order), then the next frame's

.include "b64.inc"
.include "slots.inc"

.import spr_slots_reset
.import scr_vblank
.import spr_ready
.import spr_limit
.export game_main

.segment "GAMETOP"
results:        .res 3*20
bt:             .res 1
res_i:          .res 1
; assembly drive state (the old engine routine, verbatim)
cs_act_x:       .res 2
cs_act_xf:      .res 1
cs_drive_on:    .res 1
cs_drive_tx:    .res 2
cs_vel:         .res 2
cs_wacc:        .res 2
cs_wframe:      .res 1

.segment "GAME"
game_main:
        jsr b64_init
        sei
        lda #0
        sta res_i

        ; --- DMA from the border
        lda #251
        ldx #0
        jsr dma_series
        ; --- DMA from inside the display
        lda #100
        ldx #0
        jsr dma_series

        ; --- VM: LOOP only
        lda #0
        ldx #0
        jsr vm_once
        ; --- VM: drive body
        lda #<$100
        ldx #>$100
        jsr vm_once

        ; --- assembly drive step x 64
        lda #0
        sta cs_act_x
        sta cs_act_x+1
        sta cs_act_xf
        sta cs_vel
        sta cs_vel+1
        sta cs_wacc
        sta cs_wacc+1
        sta cs_wframe
        lda #<(240*16)
        sta cs_drive_tx
        lda #>(240*16)
        sta cs_drive_tx+1
        lda #251
        jsr wait_line
        jsr b64_bench_begin
        ldx #64
@a:     txa
        pha
        jsr cs_drive_step
        pla
        tax
        dex
        bne @a
        jsr b64_bench_end
        jsr store

        ; --- VM: ADD only
        lda #<$200
        ldx #>$200
        jsr vm_once

        lda b64_plat
        sta results+3*14
        lda b64_reu_mb
        sta results+3*14+1

        ; --- the scroller: one crossing each way, interrupts off, so the
        ; count is the prepare alone
        B64_SET24 b64_reu, SLOT_TILESET0
        jsr b64_load_tileset
        B64_SET16 b64_cam_x, 1300*32
        B64_SET16 b64_cam_y, 1000*32
        jsr b64_redraw
        lda #3*15
        sta res_i
        lda #8                  ; right
        ldx #0
        jsr scroll_once
        lda #0                  ; down
        ldx #8
        jsr scroll_once
        lda #8                  ; diagonal
        ldx #8
        jsr scroll_once

        ; --- the multiplexer's decisions, two consecutive frames, with the
        ; 32-sprite limit the turbo tier gets (the VM
        ; ticks above finished lists nobody took: interrupts are off)
        lda #0
        sta spr_ready
        lda #B64_MAX_SPRITES
        sta spr_limit
        lda #40
        sta bt
        jsr mux_list
        lda #41
        sta bt
        jsr mux_list
        lda #5
        sta VIC_BORDERCOLOR     ; green: done
        jmp test_done
test_done:                      ; the test runner breaks here
        jmp test_done

; mux_list: the harness's 32 sprites at t = bt, then one b64_spr_end timed
mux_list:
        jsr b64_spr_begin
        ldx #0
@s:     stx b64_tmp+7
        lda mx_lo,x
        sta b64_spr_x
        lda mx_hi,x
        sta b64_spr_x+1
        lda bt
        asl
        clc
        adc mphase,x
        and #127
        clc
        adc #60
        sta b64_spr_y
        txa
        and #7
        clc
        adc #1
        sta b64_spr_slot
        lda #1
        sta b64_spr_colour
        lda #0
        sta b64_spr_flags
        B64_SET24 b64_reu, SLOT_BLOCK
        jsr b64_spr_add
        ldx b64_tmp+7
        inx
        cpx #32
        bne @s
        lda #100
        jsr wait_line
        jsr b64_bench_begin
        jsr b64_spr_end
        jsr b64_bench_end
        jsr store
        lda #0
        sta spr_ready           ; as if the blank had taken it
        rts

; scroll_once: A = dx, X = dy in pixels (a whole cell): time one prepare,
; then apply it as the vertical blank would
scroll_once:
        jsr b64_move_camera
        lda #100
        jsr wait_line
        jsr b64_bench_begin
        jsr b64_scroll_prepare
        jsr b64_bench_end
        jsr store
        jmp scr_vblank

; A = raster line to start on, X = 0: run the five sizes
dma_series:
        sta b64_tmp+2
        ldx #0
@next:  stx b64_tmp+3
        lda sizes_lo,x
        sta b64_len
        lda sizes_hi,x
        sta b64_len+1
        B64_SET16 b64_ptr, $8000
        B64_SET24 b64_reu, 0
        lda b64_tmp+2
        jsr wait_line
        jsr b64_bench_begin
        jsr b64_fetch
        jsr b64_bench_end
        jsr store
        ldx b64_tmp+3
        inx
        cpx #5
        bne @next
        rts

; A/X = entry offset in the bench blob: start it, run one tick to warm the
; page cache, then time a second tick from line 251
vm_once:
        pha
        B64_SET24 b64_reu, SLOT_BENCH
        pla
        jsr b64_vm_start
        jsr spr_slots_reset     ; the sprite list handoff flag, since no vblank runs here
        jsr b64_vm_tick
        jsr spr_slots_reset
        lda #251
        jsr wait_line
        jsr b64_bench_begin
        jsr b64_vm_tick
        jsr b64_bench_end
        jmp store

; A = line: spin until the raster is there (bit 8 clear)
wait_line:
        sta b64_tmp
@w:     lda VIC_CTRL1
        bmi @w
        lda VIC_HLINE
        cmp b64_tmp
        bne @w
        rts

store:  ldx res_i
        lda b64_val
        sta results,x
        lda b64_val+1
        sta results+1,x
        lda b64_val+2
        sta results+2,x
        inx
        inx
        inx
        stx res_i
        rts

; the drive step exactly as it was in the engine before the VM, minus the
; two calls into the object animation
cs_drive_step:
        lda cs_drive_tx
        sec
        sbc cs_act_x
        sta b64_tmp
        lda cs_drive_tx+1
        sbc cs_act_x+1
        sta b64_tmp+1
        ora b64_tmp
        bne @go
        lda #0
        sta cs_drive_on
        sta cs_wframe
        rts
@go:    lda cs_vel
        clc
        adc #32
        sta cs_vel
        lda cs_vel+1
        adc #0
        sta cs_vel+1
        cmp #2
        bcc @cap
        lda #0
        sta cs_vel
        lda #2
        sta cs_vel+1
@cap:   lda b64_tmp+1
        bne @move
        lda b64_tmp
        cmp #16
        bcs @move
        lsr
        lsr
        lsr
        sta cs_vel+1
        lda b64_tmp
        and #7
        asl
        asl
        asl
        asl
        asl
        sta cs_vel
        lda cs_vel+1
        bne @move
        lda cs_vel
        cmp #64
        bcs @move
        lda #64
        sta cs_vel
@move:  lda cs_act_xf
        clc
        adc cs_vel
        sta cs_act_xf
        lda cs_act_x
        adc cs_vel+1
        sta cs_act_x
        lda cs_act_x+1
        adc #0
        sta cs_act_x+1
        cmp cs_drive_tx+1
        bcc @wheels
        bne @snap
        lda cs_act_x
        cmp cs_drive_tx
        bcc @wheels
@snap:  lda cs_drive_tx
        sta cs_act_x
        lda cs_drive_tx+1
        sta cs_act_x+1
        lda #0
        sta cs_act_xf
@wheels:
        lda cs_wacc
        clc
        adc cs_vel
        sta cs_wacc
        lda cs_wacc+1
        adc cs_vel+1
        sta cs_wacc+1
        cmp #2
        bcc @done
        bne @adv
        lda cs_wacc
        cmp #128
        bcc @done
@adv:   lda cs_wacc
        sec
        sbc #128
        sta cs_wacc
        lda cs_wacc+1
        sbc #2
        sta cs_wacc+1
        inc cs_wframe
        lda cs_wframe
        and #3
        sta cs_wframe
@done:  rts

.segment "RODATA"
sizes_lo:       .byte <64, <256, <1024, <4096, <8192
sizes_hi:       .byte >64, >256, >1024, >4096, >8192

mx_lo:
.repeat 32, i
        .byte <(24 + (i .mod 8) * 38)
.endrepeat
mx_hi:
.repeat 32, i
        .byte >(24 + (i .mod 8) * 38)
.endrepeat
mphase:
.repeat 32, i
        .byte <((i .mod 8) * 4 + (i / 8) * 32)
.endrepeat
