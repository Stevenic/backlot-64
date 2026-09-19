; backlot-64 physics: a vehicle's own frame (docs/PHYSICS.md), shared by the
; wheels and hull movers.  A vehicle keeps its speed along its heading (v_long)
; and across it (v_lat); the core moves it by its world velocity (vx, vy).
; to_body turns the world velocity into the vehicle's frame after a collision
; changed it; same and world turn the frame back into the world velocity.

; enter: X = body.  Back into the vehicle's frame if a collision changed the
; world velocity; and the frame on entry noted, so that if nothing in it
; changes the world velocity can stay last frame's
enter:
        ldy #0
        lda pb_st,x
        and #ST_WORLD
        beq :+
        jsr to_body
        ldy #1                  ; the world velocity is worked out again
:       sty wv+5
        lda pb_ang,x
        sta wv
        lda pb_vll,x
        sta wv+1
        lda pb_vlh,x
        sta wv+2
        lda pb_vtl,x
        sta wv+3
        lda pb_vth,x
        sta wv+4
        rts

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
