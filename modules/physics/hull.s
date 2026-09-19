; backlot-64 physics: the hull mover (docs/PHYSICS.md).

; ---------------------------------------------------------------------------
; the hull mover: boats.  A boat keeps its speed along its heading (v_long)
; and across it (v_lat), as a car does, but water does not grip: the
; sideways speed loses a share of itself each frame (an eighth for a
; speedboat) instead of a fixed amount, so a boat carries its momentum
; through a turn and slides out wide.  Pulling back is reverse thrust, not a
; brake.  With the throttle off, drag takes a thirty-second of the speed a
; frame.  An airboat (M_AIRBOAT) is this mover with the marsh as water: its
; fan pushes it over the reeds, where it slides a sixteenth.
; The rudder turns it only while water flows past it: half as much
; when slow, and when still only with the throttle held, the propeller's
; wash doing the work.  Land is a wall (wall_and / wall_eor: anything but
; water).
hull:
        jsr enter
        ldy pb_cls,x
        lda pb_in,x
        and #IN_UP
        beq @nogas
        lda pb_vll,x             ; throttle, to the top speed (signed compare)
        cmp h_top_l-C_HULL0,y
        lda pb_vlh,x
        sbc h_top_h-C_HULL0,y
        bvc :+
        eor #$80
:       bpl @drag               ; at or over it (a push): drag brings it back
        lda pb_vll,x
        clc
        adc h_acc-C_HULL0,y
        sta pb_vll,x
        lda pb_vlh,x
        adc #0
        sta pb_vlh,x
        jmp @steer
@nogas: lda pb_in,x
        and #IN_DOWN
        beq @drag
        lda pb_vll,x             ; reverse thrust, to -h_rev
        clc
        adc h_rev-C_HULL0,y
        lda pb_vlh,x
        adc #0
        bmi @steer              ; v + rev < 0: already at the limit
        lda pb_vll,x
        sec
        sbc h_acc-C_HULL0,y
        sta pb_vll,x
        lda pb_vlh,x
        sbc #0
        sta pb_vlh,x
        jmp @steer
@drag:  jsr drag
@steer: lda pb_in,x
        and #IN_LEFT | IN_RIGHT
        bne :+
        jmp @lat
:
        lda pb_vlh,x             ; |v_long|
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
:       ldy pb_cls,x
        lda h_turn-C_HULL0,y
        ldy t1
        bne @full
        ldy t0
        cpy #$40
        bcs @half
        tay                     ; still water past the rudder: no turn, unless
        lda pb_in,x              ; the propeller washes it (thrust held)
        and #IN_UP | IN_DOWN
        beq @lat
        tya
@half:  lsr a                   ; slow: half
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
:       lda pb_vlh,x             ; going astern turns the other way
        bpl :+
        lda #0
        sec
        sbc t2
        sta t2
:       lda pb_ang,x
        clc
        adc t2
        sta pb_ang,x
        lda pb_vll,x             ; the momentum stays: v_lat -= v_long * sin(d)
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
@lat:   ldy pb_cls,x             ; sideways: v_lat -= v_lat >> h_lat
        lda h_lat-C_HULL0,y
        tay
        lda pb_vth,x
        sta t1
        lda pb_vtl,x
        sta t0
:       lda t1
        cmp #$80
        ror t1
        ror t0
        dey
        bne :-
        lda pb_vtl,x
        sec
        sbc t0
        sta pb_vtl,x
        lda pb_vth,x
        sbc t1
        sta pb_vth,x
        ; under 8/256 of a pixel a frame either way it is still; over 64,
        ; spray (ST_SKID, for the game to draw)
        clc
        lda pb_vtl,x
        adc #8
        sta t0
        lda pb_vth,x
        adc #0
        bne :+
        lda t0
        cmp #16
        bcs :+
        lda #0
        sta pb_vtl,x
        sta pb_vth,x
:       lda pb_st,x
        and #<~ST_SKID
        sta pb_st,x
        clc                     ; v_lat + 64 in 0-127: under 64 either way
        lda pb_vtl,x
        adc #64
        sta t0
        lda pb_vth,x
        adc #0
        bne @spray
        lda t0
        bpl @same
@spray: lda pb_st,x
        ora #ST_SKID
        sta pb_st,x
@same:  jmp same

; drag: X = body.  v_long -= v_long / 32 and one 256th more, to a stop
drag:
        lda pb_vlh,x
        sta t1
        lda pb_vll,x
        sta t0
        ldy #5
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
        lda pb_vll,x
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
@done:  rts

; the hull classes' figures, from C_HULL0: speedboat, launch, jet ski, then
; two not hulls (the helicopter and the plane), then the airboat
h_top_l:  .byte     0,   $80,   $80,     0,     0,     0     ; top speed, 8.8: 4.0, 2.5, 4.5; 4.0
h_top_h:  .byte     4,     2,     4,     0,     0,     4
h_acc:    .byte     6,     3,    10,     0,     0,     7
h_rev:    .byte   $A0,   $80,   $80,     0,     0,   $60     ; top speed astern, 1/256 pixel a frame
h_turn:   .byte     2,     1,     3,     0,     0,     3
h_lat:    .byte     3,     2,     3,     1,     1,     4     ; the sideways share lost a frame: 1/8, 1/4, 1/8; 1/16
