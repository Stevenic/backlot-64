; backlot-64 physics: the air mover, helicopters (docs/PHYSICS.md).

LIFT    = 12                    ; fire held: 12/256 of a pixel a frame more climb each frame,
SINK    = 12                    ; let go: 12/256 more fall, to at most half a pixel a frame
CEIL    = 112                   ; the highest it flies, pixels

; ---------------------------------------------------------------------------
; heli: X = body.  Altitude is a third coordinate (pb_zl/zh, 8.8 pixels,
; pb_vzl/vzh).  Fire held climbs, to CEIL; let go, the craft settles at
; half a pixel a frame onto whatever is under its box: the ground, or a roof
; (floor), where it rests.
; Flying, the stick thrusts it the way it points in the world (up is north)
; and it turns to face that way, 4 a frame; drag takes a thirty-second of
; its speed a frame, so it drifts on after the stick is let go.  On the
; ground or a roof it cannot move along it.  A building is a wall only below
; its height (corner, in the core, in this module).
heli:
        lda pb_in,x
        and #IN_FIRE
        beq @sink
        lda pb_vzl,x             ; climb, to a pixel a frame
        clc
        adc #LIFT
        sta pb_vzl,x
        lda pb_vzh,x
        adc #0
        sta pb_vzh,x
        bmi @z
        beq @z
        lda #0
        sta pb_vzl,x
        lda #1
        sta pb_vzh,x
        bne @z
@sink:  lda pb_vzl,x             ; settle, at most half a pixel a frame
        sec
        sbc #SINK
        sta pb_vzl,x
        lda pb_vzh,x
        sbc #0
        sta pb_vzh,x
        bpl @z
        cmp #$FF
        bne :+
        lda pb_vzl,x
        cmp #$80
        bcs @z
:       lda #$80
        sta pb_vzl,x
        lda #$FF
        sta pb_vzh,x
@z:     lda pb_zl,x              ; z += vz, between the ground and the ceiling
        clc
        adc pb_vzl,x
        sta pb_zl,x
        lda pb_zh,x
        adc pb_vzh,x
        sta pb_zh,x
        bpl :+
        lda #0                  ; under the ground: on it (the floor below says so)
        sta pb_zh,x
        sta pb_zl,x
:       cmp #CEIL
        bcc @floor
        lda #CEIL
        sta pb_zh,x
        lda #0
        sta pb_zl,x
        sta pb_vzl,x
        sta pb_vzh,x
@floor: jsr floor
        sta t5
        lda pb_zh,x             ; how high over it, for the game to draw
        sec
        sbc t5
        bcs :+
        lda #0
:       sta pb_agl,x
        lda pb_zh,x
        cmp t5
        bcc @land               ; under what is below it: down onto it
        bne @fly
        lda pb_vzh,x             ; level with it: climbing away, or resting
        bmi @land
        ora pb_vzl,x
        bne @fly
        jmp @rest
@land:  lda t5                  ; down onto it
        sta pb_zh,x
        lda #0
        sta pb_agl,x
        sta pb_zl,x
        sta pb_vzl,x
        sta pb_vzh,x
@rest:  lda pb_vxl,x             ; down: it skids to a stop, a quarter a frame
        sta t0
        lda pb_vxh,x
        jsr quarter
        sta pb_vxh,x
        lda t0
        sta pb_vxl,x
        lda pb_vyl,x
        sta t0
        lda pb_vyh,x
        jsr quarter
        sta pb_vyh,x
        lda t0
        sta pb_vyl,x
        rts
@fly:   lda #0                  ; flying: awake
        sta pb_idle,x
        lda pb_in,x
        and #$0F
        tay
        lda h_ax,y               ; thrust along x
        sta t0
        and #$80
        beq :+
        lda #$FF
:       sta t1
        lda pb_vxl,x
        clc
        adc t0
        sta pb_vxl,x
        lda pb_vxh,x
        adc t1
        sta pb_vxh,x
        lda h_ay,y               ; and y
        sta t0
        and #$80
        beq :+
        lda #$FF
:       sta t1
        lda pb_vyl,x
        clc
        adc t0
        sta pb_vyl,x
        lda pb_vyh,x
        adc t1
        sta pb_vyh,x
        lda h_dir,y              ; face the stick's way, 4 a frame
        bmi @drag
        sec
        sbc pb_ang,x
        clc
        adc #4
        cmp #9
        bcs @turn
        lda h_dir,y              ; within 4: there
        sta pb_ang,x
        jmp @drag
@turn:  sbc #4                  ; C=1: back to the difference
        bmi @left
        lda pb_ang,x
        clc
        adc #4
        sta pb_ang,x
        jmp @drag
@left:  lda pb_ang,x
        sec
        sbc #4
        sta pb_ang,x
@drag:  lda pb_vxl,x             ; drag: a thirty-second of the speed
        sta t0
        lda pb_vxh,x
        jsr drag32
        sta pb_vxh,x
        lda t0
        sta pb_vxl,x
        lda pb_vyl,x
        sta t0
        lda pb_vyh,x
        jsr drag32
        sta pb_vyh,x
        lda t0
        sta pb_vyl,x
        rts

; quarter: v = A (high), t0 (low) -> A, t0 = v - v/4, none when it is under
; 1/32 of a pixel a frame either way.  drag32 the same with v/32.  Keep X.
quarter:
        ldy #2
        bne shed
drag32:
        ldy #5
shed:   sta t1
        sta t2
        lda t0
        sta t3
:       lda t2                  ; t2:t3 = v >> y, sign kept
        cmp #$80
        ror t2
        ror t3
        dey
        bne :-
        lda t0
        sec
        sbc t3
        sta t0
        lda t1
        sbc t2
        sta t1
        clc                     ; under 8/256 either way: still
        lda t0
        adc #8
        tay
        lda t1
        adc #0
        bne :+
        cpy #16
        bcs :+
        lda #0
        sta t0
        rts
:       lda t1
        rts

; floor: X = body -> A = the height in pixels of the tallest thing under any
; corner of its box, 0 on open ground.  The corners as in wall_test.
floor:
        ldy pb_cls,x
        lda pb_xl,x
        and #31
        sta t0
        sec
        sbc c_hw,y
        lda #1
        bcs :+
        lda #0
:       sta t1
        lda t0
        clc
        adc c_hw,y
        cmp #32
        lda #1
        bcc :+
        lda #2
:       sta t2
        lda pb_yl,x
        and #31
        sta t0
        sec
        sbc c_hh,y
        lda #3
        bcs :+
        lda #0
:       sta t3
        lda t0
        clc
        adc c_hh,y
        cmp #32
        lda #3
        bcc :+
        lda #6
:       sta t4
        stx ub
        lda #0
        sta t5
        lda t3
        clc
        adc t1
        jsr f_corner
        lda t3
        clc
        adc t2
        jsr f_corner
        lda t4
        clc
        adc t1
        jsr f_corner
        lda t4
        clc
        adc t2
        jsr f_corner
        lda t5
        rts
f_corner:
        tay
        lda kofs,y
        clc
        adc ub
        tay
        lda cache,y
        bpl @no                 ; not solid: the ground
        and #$0F
        asl
        asl
        asl
        cmp t5
        bcc @no
        sta t5
@no:    rts

; load_heights: the tileset's heights (256 bytes at +$2900, storeys of 8
; pixels) into the module, for HEIGHT
load_heights:
        lda phys_tiles
        clc
        adc #<$2900
        sta b64_reu
        lda phys_tiles+1
        adc #>$2900
        sta b64_reu+1
        lda phys_tiles+2
        adc #0
        sta b64_reu+2
        lda #<heights
        sta b64_ptr
        lda #>heights
        sta b64_ptr+1
        lda #0
        sta b64_len
        lda #1
        sta b64_len+1
        jmp b64_fetch

; by the stick (pb_in & 15: up 1, down 2, left 4, right 8): thrust along x
; and y in 1/256 of a pixel a frame each frame (24 straight, 17 on a
; diagonal), and the heading it turns to ($FF: none)
h_ax:   .byte 0,   0,   0, 0, <-24, <-17, <-17, 0,  24,  17,  17, 0, 0, 0, 0, 0
h_ay:   .byte 0, <-24, 24, 0,    0, <-17,   17, 0,   0, <-17, 17, 0, 0, 0, 0, 0
h_dir:  .byte $FF, 192, 64, $FF, 128, 160,  96, $FF,  0, 224,  32, $FF, $FF, $FF, $FF, $FF
