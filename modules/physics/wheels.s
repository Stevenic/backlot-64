; backlot-64 physics: the wheels mover (docs/PHYSICS.md).

; ---------------------------------------------------------------------------
; the wheels mover.  The car keeps its speed along its heading (v_long) and
; across it (v_lat).  Throttle, brake and reverse change v_long; steering
; turns the heading, and the momentum the car had now points partly across
; it; grip takes that sideways speed away a frame at a time, and what grip
; cannot take the car slides on.  The handbrake takes most of the grip.
wheels:
        ldy #0
        lda pb_st,x
        and #ST_WORLD
        beq :+
        jsr to_body             ; a collision moved it: back into the car's frame
        ldy #1                  ; and the world velocity is worked out again
:       sty wv+5
        lda pb_ang,x             ; the frame on entry: if nothing in it changes,
        sta wv                  ; the world velocity is last frame's
        lda pb_vll,x
        sta wv+1
        lda pb_vlh,x
        sta wv+2
        lda pb_vtl,x
        sta wv+3
        lda pb_vth,x
        sta wv+4
        ldy pb_cls,x
        ; the top speed, a quarter less off the road
        lda c_top_l,y
        sta t4
        lda c_top_h,y
        sta t5
        lda pb_surf,x
        cmp #2
        bcc :+
        lda t5
        lsr a
        sta t0
        lda t4
        ror a
        lsr t0
        ror a                   ; top / 4
        sta t1
        lda t4
        sec
        sbc t1
        sta t4
        lda t5
        sbc t0
        sta t5
:       ; engine and brakes
        lda pb_in,x
        and #IN_UP
        beq @nogas
        lda pb_vll,x             ; below the top speed (signed compare)
        cmp t4
        lda pb_vlh,x
        sbc t5
        bvc :+
        eor #$80
:       bpl @steer
        lda pb_vll,x
        clc
        adc c_acc,y
        sta pb_vll,x
        lda pb_vlh,x
        adc #0
        sta pb_vlh,x
        jmp @steer
@nogas: lda pb_in,x
        and #IN_DOWN
        beq @coast
        lda pb_vlh,x
        bmi @back
        ora pb_vll,x
        beq @back
        lda pb_vll,x             ; braking, to a stop
        sec
        sbc c_brk,y
        sta pb_vll,x
        lda pb_vlh,x
        sbc #0
        sta pb_vlh,x
        bpl @steer
        lda #0
        sta pb_vll,x
        sta pb_vlh,x
        jmp @steer
@back:  lda pb_vll,x             ; reverse, to -c_rev
        clc
        adc c_rev,y
        lda pb_vlh,x
        adc #0
        bmi @steer              ; v + rev < 0: already at the reverse limit
        lda pb_vll,x
        sec
        sbc c_acc,y
        sta pb_vll,x
        lda pb_vlh,x
        sbc #0
        sta pb_vlh,x
        jmp @steer
@coast: jsr coast
@steer: lda pb_in,x
        and #IN_LEFT | IN_RIGHT
        bne :+
        jmp @grip
:       ; how far it turns: none when nearly still, half when slow
        lda pb_vlh,x
        sta t1
        lda pb_vll,x
        sta t0
        lda t1
        bpl :+
        lda #0
        sec
        sbc t0
        sta t0
        lda #0
        sbc t1
        sta t1
:       lda c_turn,y
        ldy t1
        bne @full
        ldy t0
        cpy #$60
        bcc @grip
        lsr a
        bne @full
        lda #1
@full:  sta t2
        lda pb_in,x              ; left is anticlockwise
        and #IN_LEFT
        beq :+
        lda #0
        sec
        sbc t2
        sta t2
:       lda pb_vlh,x             ; backing up turns the other way
        bpl :+
        lda #0
        sec
        sbc t2
        sta t2
:       lda pb_ang,x
        clc
        adc t2
        sta pb_ang,x
        ; the velocity stays where it was: in the turned frame part of it is
        ; sideways, v_lat -= v_long * sin(d)
        lda pb_vll,x
        sta m16
        lda pb_vlh,x
        sta m16+1
        ldy t2
        lda phys_sine,y
        jsr smul
        lda pb_vtl,x
        sec
        sbc res
        sta pb_vtl,x
        lda pb_vth,x
        sbc res+1
        sta pb_vth,x
@grip:  lda pb_in,x               ; the handbrake slows it
        and #IN_FIRE
        beq :+
        jsr coast
:       ldy pb_cls,x             ; grip: less off the road, a quarter with the handbrake
        lda c_grip,y
        ldy pb_surf,x
        cpy #2
        bcc :+
        lsr a
:       sta t0
        lda pb_in,x
        and #IN_FIRE
        beq :+
        lsr t0
        lsr t0
:       lda pb_vth,x             ; |v_lat| <= grip: it holds
        bmi @left
        bne @slide
        lda pb_vtl,x
        cmp t0
        bcc @hold
        beq @hold
@slide: lda pb_vtl,x             ; sliding right: v_lat -= grip
        sec
        sbc t0
        sta pb_vtl,x
        lda pb_vth,x
        sbc #0
        sta pb_vth,x
        jmp @skid
@left:  cmp #$FF
        bne @slidel
        lda pb_vtl,x
        clc
        adc t0
        bcs @hold               ; within grip of zero
@slidel:
        lda pb_vtl,x
        clc
        adc t0
        sta pb_vtl,x
        lda pb_vth,x
        adc #0
        sta pb_vth,x
@skid:  lda pb_st,x
        ora #ST_SKID
        sta pb_st,x
        jmp same
@hold:  lda #0
        sta pb_vtl,x
        sta pb_vth,x
        lda pb_st,x
        and #<~ST_SKID
        sta pb_st,x
; same: heading and speeds as they were on entry, and no collision: the
; world velocity from last frame stands (a car cruising, a car standing)
same:   lda wv+5
        bne world
        lda pb_ang,x
        cmp wv
        bne world
        lda pb_vll,x
        cmp wv+1
        bne world
        lda pb_vlh,x
        cmp wv+2
        bne world
        lda pb_vtl,x
        cmp wv+3
        bne world
        lda pb_vth,x
        cmp wv+4
        bne world
        rts
; world: the car's frame to the world's, v = v_long * f + v_lat * r
world:
        lda pb_ang,x
        jsr sin_cos
        lda pb_vll,x
        sta m16
        lda pb_vlh,x
        sta m16+1
        lda t1
        jsr smul                ; v_long cos
        lda res
        sta pb_vxl,x
        lda res+1
        sta pb_vxh,x
        lda pb_vll,x
        sta m16
        lda pb_vlh,x
        sta m16+1
        lda t0
        jsr smul                ; v_long sin
        lda res
        sta pb_vyl,x
        lda res+1
        sta pb_vyh,x
        lda pb_vtl,x
        ora pb_vth,x
        beq @done
        lda pb_vtl,x             ; vx -= v_lat sin
        sta m16
        lda pb_vth,x
        sta m16+1
        lda t0
        jsr smul
        lda pb_vxl,x
        sec
        sbc res
        sta pb_vxl,x
        lda pb_vxh,x
        sbc res+1
        sta pb_vxh,x
        lda pb_vtl,x             ; vy += v_lat cos
        sta m16
        lda pb_vth,x
        sta m16+1
        lda t1
        jsr smul
        lda pb_vyl,x
        clc
        adc res
        sta pb_vyl,x
        lda pb_vyh,x
        adc res+1
        sta pb_vyh,x
@done:  rts

; to_body: X = body.  v_long = vx cos + vy sin, v_lat = vy cos - vx sin
to_body:
        lda pb_st,x
        and #<~ST_WORLD
        sta pb_st,x
        lda pb_ang,x
        jsr sin_cos
        lda pb_vxl,x
        sta m16
        lda pb_vxh,x
        sta m16+1
        lda t1
        jsr smul
        lda res
        sta pb_vll,x
        lda res+1
        sta pb_vlh,x
        lda pb_vyl,x
        sta m16
        lda pb_vyh,x
        sta m16+1
        lda t0
        jsr smul
        lda pb_vll,x
        clc
        adc res
        sta pb_vll,x
        lda pb_vlh,x
        adc res+1
        sta pb_vlh,x
        lda pb_vyl,x
        sta m16
        lda pb_vyh,x
        sta m16+1
        lda t1
        jsr smul
        lda res
        sta pb_vtl,x
        lda res+1
        sta pb_vth,x
        lda pb_vxl,x
        sta m16
        lda pb_vxh,x
        sta m16+1
        lda t0
        jsr smul
        lda pb_vtl,x
        sec
        sbc res
        sta pb_vtl,x
        lda pb_vth,x
        sbc res+1
        sta pb_vth,x
        rts

; coast: X = body.  Rolling: v_long -= v_long / 64 and 1/256 more, to a stop
coast:
        lda pb_vlh,x
        sta t1
        lda pb_vll,x
        sta t0
        ldy #6
:       lda t1
        cmp #$80
        ror t1
        ror t0
        dey
        bne :-
        lda pb_vlh,x
        bmi @neg
        lda pb_vll,x
        sec
        sbc t0
        sta pb_vll,x
        lda pb_vlh,x
        sbc t1
        sta pb_vlh,x
        lda pb_vll,x             ; and one 256th
        sec
        sbc #1
        sta pb_vll,x
        lda pb_vlh,x
        sbc #0
        sta pb_vlh,x
        bpl @done
        jmp @stop
@neg:   lda pb_vll,x
        sec
        sbc t0
        sta pb_vll,x
        lda pb_vlh,x
        sbc t1
        sta pb_vlh,x
        lda pb_vll,x
        clc
        adc #1
        sta pb_vll,x
        lda pb_vlh,x
        adc #0
        sta pb_vlh,x
        bmi @done
@stop:  lda #0
        sta pb_vll,x
        sta pb_vlh,x
@done:  ldy pb_cls,x
        rts

; the wheel classes' figures, by class (0 and anything not a vehicle: unused)
c_top_l:  .byte       0,  $80,   $80,    $80,     0      ; top speed, 8.8: 3.5, 4.5, 2.5, 4.0
c_top_h:  .byte       0,    3,     4,      2,     4
c_acc:    .byte       0,    8,    12,      4,    10
c_brk:    .byte       0,   24,    32,     16,    24
c_rev:    .byte       0,  $C0,   $C0,   $A0,   $A0      ; top speed in reverse, 1/256 pixel a frame
c_turn:   .byte       0,    3,     3,      2,     4
c_grip:   .byte       0,  $28,   $30,    $20,   $18

