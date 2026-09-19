; backlot-64 physics: the air mover, planes (docs/PHYSICS.md).

PL_TOP   = $0380                ; top speed, 3.5 pixels a frame
PL_LIFT  = $0200                ; at 2 pixels a frame the wings hold it up
PL_MIN   = $0180                ; in the air, throttling back stops at 1.5: it sinks
PL_ACC   = 5                    ; throttle, 1/256 of a pixel a frame each frame
PL_BRK   = 16                   ; the wheel brakes, on the ground
PL_CLIMB = 8                    ; climbing, levelling or sinking, 8/256 a frame each frame,
PL_VZ    = $C0                  ; to at most 3/4 of a pixel a frame

; ---------------------------------------------------------------------------
; plane: X = body.  A plane goes where it points (the vehicle's frame, with
; no sideways speed).  Up is the throttle, to the top speed; let go, drag
; takes a sixty-fourth of the speed a frame.  Down brakes on the ground and
; in the air throttles back to 1.5 pixels a frame.  At flying speed fire held
; climbs and let go it holds its height; slower, it sinks, which is how it
; lands.  It turns 2 a frame in the air, 1 on the ground when rolling.  The
; height, the ceiling and what is under it as for the helicopter (rise).
plane:
        jsr enter
        lda #0                  ; no sideways speed
        sta pb_vtl,x
        sta pb_vth,x
        lda pb_in,x
        and #IN_UP
        beq @nogas
        lda pb_vll,x             ; throttle, to the top speed
        clc
        adc #PL_ACC
        sta pb_vll,x
        lda pb_vlh,x
        adc #0
        sta pb_vlh,x
        lda pb_vll,x
        cmp #<PL_TOP
        lda pb_vlh,x
        sbc #>PL_TOP
        bcc @turn
        lda #<PL_TOP
        sta pb_vll,x
        lda #>PL_TOP
        sta pb_vlh,x
        jmp @turn
@nogas: lda pb_in,x
        and #IN_DOWN
        beq @drag
        lda pb_agl,x
        bne @back
        lda pb_vll,x             ; on the ground: the brakes, to a stop
        sec
        sbc #PL_BRK
        sta pb_vll,x
        lda pb_vlh,x
        sbc #0
        sta pb_vlh,x
        bcs @turn
        lda #0
        sta pb_vll,x
        sta pb_vlh,x
        beq @turn
@back:  lda pb_vll,x             ; in the air: throttled back, to 1.5
        sec
        sbc #PL_ACC
        sta pb_vll,x
        lda pb_vlh,x
        sbc #0
        sta pb_vlh,x
        lda pb_vll,x
        cmp #<PL_MIN
        lda pb_vlh,x
        sbc #>PL_MIN
        bcs @turn
        lda #<PL_MIN
        sta pb_vll,x
        lda #>PL_MIN
        sta pb_vlh,x
        jmp @turn
@drag:  lda pb_vll,x             ; no throttle: drag
        sta t0
        lda pb_vlh,x
        jsr drag64
        sta pb_vlh,x
        lda t0
        sta pb_vll,x
@turn:  lda pb_in,x
        and #IN_LEFT | IN_RIGHT
        beq @vert
        ldy #2                  ; in the air, 2 a frame
        lda pb_agl,x
        bne @rate
        lda pb_vlh,x             ; on the ground, 1, and only rolling
        bne @slow
        lda pb_vll,x
        cmp #$40
        bcc @vert
@slow:  ldy #1
@rate:  sty t2
        lda pb_in,x
        and #IN_LEFT
        beq :+
        lda #0
        sec
        sbc t2
        sta t2
:       lda pb_ang,x
        clc
        adc t2
        sta pb_ang,x
@vert:  lda pb_vll,x             ; flying speed?
        cmp #<PL_LIFT
        lda pb_vlh,x
        sbc #>PL_LIFT
        bcc @sink
        lda pb_in,x
        and #IN_FIRE
        beq @level
        lda pb_vzl,x             ; fire: climb
        clc
        adc #PL_CLIMB
        sta pb_vzl,x
        lda pb_vzh,x
        adc #0
        sta pb_vzh,x
        bmi @z
        bne :+
        lda pb_vzl,x
        cmp #PL_VZ
        bcc @z
:       lda #PL_VZ
        sta pb_vzl,x
        lda #0
        sta pb_vzh,x
        beq @z
@level: lda pb_vzh,x             ; let go: level off
        bmi @up
        ora pb_vzl,x
        beq @z
        lda pb_vzl,x
        sec
        sbc #PL_CLIMB
        sta pb_vzl,x
        lda pb_vzh,x
        sbc #0
        sta pb_vzh,x
        bpl @z
        bmi @stop
@up:    lda pb_vzl,x
        clc
        adc #PL_CLIMB
        sta pb_vzl,x
        lda pb_vzh,x
        adc #0
        sta pb_vzh,x
        bmi @z
@stop:  lda #0
        sta pb_vzl,x
        sta pb_vzh,x
        beq @z
@sink:  lda pb_vzl,x             ; too slow to fly: it sinks
        sec
        sbc #PL_CLIMB
        sta pb_vzl,x
        lda pb_vzh,x
        sbc #0
        sta pb_vzh,x
        bpl @z
        cmp #$FF
        bne :+
        lda pb_vzl,x
        cmp #<-PL_VZ
        bcs @z
:       lda #<-PL_VZ
        sta pb_vzl,x
        lda #$FF
        sta pb_vzh,x
@z:     jsr rise
        jmp same
