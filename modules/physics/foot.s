; backlot-64 physics: the foot mover (docs/PHYSICS.md).

; ---------------------------------------------------------------------------
; the foot mover: eight directions, walk or run (fire), reached in a few
; frames; knocked down, it slides to a stop and gets up after a second.
foot:
        lda pb_st,x
        and #ST_DOWN
        beq @up
        jsr slow8
        dec pb_tmr,x
        bne :+
        lda pb_st,x
        and #<~ST_DOWN
        sta pb_st,x
:       rts
@up:    lda pb_in,x
        and #$0F
        tay
        lda dir_ang,y
        cmp #$FF
        beq :+                  ; no direction: keep the heading
        sta pb_ang,x
:       lda pb_in,x
        and #IN_FIRE
        beq :+
        tya
        ora #16                 ; the run table follows the walk table
        tay
:       lda walk_xl,y
        sta t0
        lda walk_xh,y
        sta t1
        lda walk_yl,y
        sta t2
        lda walk_yh,y
        sta t3
        lda pb_vxl,x             ; at the target already: done
        cmp t0
        bne @ax
        lda pb_vxh,x
        cmp t1
        bne @ax
        lda pb_vyl,x
        cmp t2
        bne @ax
        lda pb_vyh,x
        cmp t3
        bne @ax
        rts
@ax:    lda pb_vxl,x             ; x toward its target by 1/4 pixel a frame
        sta m16
        lda pb_vxh,x
        sta m16+1
        jsr approach
        lda m16
        sta pb_vxl,x
        lda m16+1
        sta pb_vxh,x
        lda t2
        sta t0
        lda t3
        sta t1
        lda pb_vyl,x
        sta m16
        lda pb_vyh,x
        sta m16+1
        jsr approach
        lda m16
        sta pb_vyl,x
        lda m16+1
        sta pb_vyh,x
        rts

; approach: m16 toward t0/t1 by FOOT_ACC at most
FOOT_ACC = $0040
approach:
        lda t0
        sec
        sbc m16
        sta t4
        lda t1
        sbc m16+1
        sta t5                  ; target - v
        bmi @down
        ora t4
        beq @done
        lda t4
        cmp #<FOOT_ACC
        lda t5
        sbc #>FOOT_ACC
        bcc @snap               ; within a step: arrive
        lda m16
        clc
        adc #<FOOT_ACC
        sta m16
        lda m16+1
        adc #>FOOT_ACC
        sta m16+1
@done:  rts
@down:  lda t4                  ; target below: -(t) <= step ?
        clc
        adc #<FOOT_ACC
        lda t5
        adc #>FOOT_ACC
        bpl @snap
        lda m16
        sec
        sbc #<FOOT_ACC
        sta m16
        lda m16+1
        sbc #>FOOT_ACC
        sta m16+1
        rts
@snap:  lda t0
        sta m16
        lda t1
        sta m16+1
        rts

; foot: the direction bits (up 1, down 2, left 4, right 8) -> heading, $FF none
dir_ang:  .byte $FF, 192, 64, $FF, 128, 160, 96, 128, 0, 224, 32, 0, $FF, 192, 64, $FF
; walk, then run: target velocity per direction, 8.8 (1.0 and 1.75; 0.71 and 1.24 diagonal)
W1 = $0100
W7 = $00B5
R1 = $01C0
R7 = $013D
walk_xl:  .byte 0, 0, 0, 0, <-W1, <-W7, <-W7, <-W1, <W1, <W7, <W7, <W1, 0, 0, 0, 0
          .byte 0, 0, 0, 0, <-R1, <-R7, <-R7, <-R1, <R1, <R7, <R7, <R1, 0, 0, 0, 0
walk_xh:  .byte 0, 0, 0, 0, >-W1, >-W7, >-W7, >-W1, >W1, >W7, >W7, >W1, 0, 0, 0, 0
          .byte 0, 0, 0, 0, >-R1, >-R7, >-R7, >-R1, >R1, >R7, >R7, >R1, 0, 0, 0, 0
walk_yl:  .byte 0, <-W1, <W1, 0, 0, <-W7, <W7, 0, 0, <-W7, <W7, 0, 0, <-W1, <W1, 0
          .byte 0, <-R1, <R1, 0, 0, <-R7, <R7, 0, 0, <-R7, <R7, 0, 0, <-R1, <R1, 0
walk_yh:  .byte 0, >-W1, >W1, 0, 0, >-W7, >W7, 0, 0, >-W7, >W7, 0, 0, >-W1, >W1, 0
          .byte 0, >-R1, >R1, 0, 0, >-R7, >R7, 0, 0, >-R7, >R7, 0, 0, >-R1, >R1, 0

