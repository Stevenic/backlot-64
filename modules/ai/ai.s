; backlot-64 AI (docs/AI.md): scripts decide, this executes.
;
; A module for region A beside the collision module ($8D00, ai.cfg), running
; every tick before the physics step.  It reads the physics bodies, asks the
; collision module what can be seen, fires through it, and drives each body
; by writing its input byte, as a player's stick would.  The brains are at a
; fixed address (ai.inc) for the game to read and set.
;
; Every routine that works on one body takes it in X and keeps it there.
; Zero page $A0-$AF is the module's.

.include "b64.inc"
.include "defs.inc"
.include "collision_syms.inc"
.include "ai.inc"

.export ai_init, ai_set, ai_step, ai_noise, ai_event

SIGHT   = 120                   ; pixels, on the larger axis
CONE    = 40                    ; half the facing cone, in heading units (56 degrees)
RANGE   = 72                    ; attack fires within this
RATE    = 30                    ; ticks between one body's shots
FLEE_TO = 160                   ; flee until this far, then calm down
SCARE   = 32                    ; panic spreads this far
LOST_T  = 34                    ; turns unseen (three ticks each) before a pursuer searches

dxl     = $A0                   ; to the point being considered
dxh     = $A1
dyl     = $A2
dyh     = $A3
adx     = $A4                   ; |dx|, |dy| to a byte (255: far)
ady     = $A5
dh      = $A6                   ; the heading the body wants
go      = $A7                   ; 0 stop, 1 walk, 2 run
a_x     = $A8                   ; the body being worked on
a_n     = $A9
a_t     = $AA
a_q     = $AB
a_s     = $AC                   ; heading: the smaller and larger of |dx|, |dy|
a_l     = $AD
a_f     = $AE                   ; heading: flags; blocked: the try
a_ph    = $AF                   ; which third of the bodies perceives this tick

.segment "OVERLAY"
        jmp ai_init             ; +0
        jmp ai_set              ; +3   X = body, A = behaviour, Y = target body ($FF: ai_px/py)
        jmp ai_step             ; +6   every brain one tick
        jmp ai_noise            ; +9   ai_px/py, A = radius, X = who made it
        jmp ai_event            ; +12  C=1: A = what, X = body, Y = the other

; ---------------------------------------------------------------------------
ai_init:
        ldx #0
        txa
:       sta AB_BASE,x
        inx
        cpx #AB_END - AB_BASE + 5
        bne :-
        ldx #NB-1
        lda #$FF
:       sta ab_tgt,x
        dex
        bpl :-
        lda #0
        sta ev_head
        sta ev_tail
        sta a_ph
        lda #$A5
        sta rnd
        rts

ai_set:
        sta ab_beh,x
        tya
        sta ab_tgt,x
        lda ai_px
        sta ab_txl,x
        lda ai_px+1
        sta ab_txh,x
        lda ai_py
        sta ab_tyl,x
        lda ai_py+1
        sta ab_tyh,x
        lda #0
        sta ab_tmr,x
        sta ab_see,x
        rts

; ai_event: the oldest event -> C=1, A = what, X = body, Y = the other
ai_event:
        ldy ev_tail
        cpy ev_head
        bne :+
        clc
        rts
:       lda ev_a,y
        sta a_t
        lda ev_b,y
        tax
        lda ev_k,y
        pha
        iny
        tya
        and #15
        sta ev_tail
        ldy a_t
        pla
        sec
        rts

; ev_push: A = what, X = body, Y = the other; a full queue loses the newest
ev_push:
        sty a_t
        ldy ev_head
        sta ev_k,y
        txa
        sta ev_b,y
        lda a_t
        sta ev_a,y
        iny
        tya
        and #15
        cmp ev_tail
        beq :+
        sta ev_head
:       rts

; ---------------------------------------------------------------------------
; ai_noise: a noise at ai_px/py heard within A pixels, made by body X ($FF
; none).  A civilian who hears it panics and flees from it; an officer turns
; on its maker by the heat (1 pursue, 2 attack), or goes to look (heat 0, or
; no maker).
ai_noise:
        sta a_n
        stx a_t
        ldx #NB-1
@b:     stx a_x
        lda pb_mov,x
        beq @n
        lda ab_beh,x
        beq @n
        cpx a_t
        beq @n
        jsr at_noise
        jsr delta
        jsr far
        cmp a_n
        bcs @n
        lda ab_team,x
        bne @cop
        jsr fear                ; a civilian: flee from the noise
        ldy a_t
        lda #E_PANIC
        jsr ev_push
        jmp @n
@cop:   cmp #T_POLICE
        bne @n
        lda #255
        sta ab_alert,x
        ldy a_t
        lda #E_HEARD
        jsr ev_push
        lda ai_heat
        beq @look
        ldy a_t
        cpy #NB
        bcs @look
        jsr hostile             ; the heat decides: pursue or attack it
        jmp @n
@look:  lda ai_px               ; go and look
        sta ab_txl,x
        lda ai_px+1
        sta ab_txh,x
        lda ai_py
        sta ab_tyl,x
        lda ai_py+1
        sta ab_tyh,x
        lda #B_GOTO
        sta ab_beh,x
@n:     ldx a_x
        dex
        bpl @b
        rts

; fear: X = a civilian -> it flees from the noise at ai_px/py
fear:
        lda ai_px
        sta ab_txl,x
        lda ai_px+1
        sta ab_txh,x
        lda ai_py
        sta ab_tyl,x
        lda ai_py+1
        sta ab_tyh,x
        lda #$FF
        sta ab_tgt,x
        lda #B_FLEE
        sta ab_beh,x
        lda #60
        sta ab_tmr,x
        lda #255
        sta ab_alert,x
        rts

; hostile: X = an officer, Y = a suspect -> pursue it (heat 1) or attack it
; (heat 2 and over); where it is now is where it was last seen
hostile:
        tya
        sta ab_tgt,x
        lda #B_PURSUE
        ldy ai_heat
        cpy #2
        bcc :+
        lda #B_ATTACK
:       sta ab_beh,x
        lda #0
        sta ab_tmr,x
        ldy ab_tgt,x
        jmp seen_at

; ---------------------------------------------------------------------------
; ai_step: every brain one tick: its timers; and for one body in three
; (PLAN.md section 6.2), perception, panic spreading and its behaviour.
; The others hold the input they were given, so behaviour timers count in
; turns of three ticks.
ai_step:
        inc a_ph
        lda a_ph
        cmp #3
        bcc :+
        lda #0
        sta a_ph
:       lda rnd                 ; the tick's random byte
        asl a
        bcc :+
        eor #$1D
:       sta rnd
        ldx #NB-1
@b:     stx a_x
        lda pb_mov,x
        beq @n
        lda ab_beh,x
        beq @n
        lda ab_cool,x
        beq :+
        dec ab_cool,x
:       lda ab_alert,x
        beq :+
        dec ab_alert,x
:       lda mod3,x              ; its turn: one body in three a tick; the others
        cmp a_ph                ; keep the input they were given
        bne @n
        jsr perceive
        ldx a_x
        jsr spread
        ldx a_x
        jsr behave
@n:     ldx a_x
        dex
        bpl @b
        rts

mod3:   .byte 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2

; ---------------------------------------------------------------------------
; perceive: X = body.  Does it see its target?  Within SIGHT on the larger
; axis, within its facing cone unless it is alert, and no solid metatile
; on the line between them (los).
perceive:
        ldy ab_tgt,x
        cpy #NB
        bcc :+
        rts
:       lda pb_mov,y
        bne :+
        rts
:       sty a_t
        jsr at_body
        jsr delta
        jsr far
        cmp #SIGHT
        bcs @out
        lda ab_alert,x
        bne @los
        jsr heading             ; within the cone?
        sec
        sbc pb_ang,x
        clc
        adc #CONE
        cmp #CONE * 2 + 1
        bcc @los
@out:   jmp @unseen
@los:   lda ab_see,x            ; a trace every other turn: between, what it saw
        eor #1
        sta ab_see,x
        and #1
        bne :+
        rts
:       ldy a_t
        jsr los
        ldx a_x
        bcc @unseen
        ldy a_t                 ; seen
        jsr seen_at
        lda #255
        sta ab_alert,x
        jsr radio               ; officers tell each other
        lda ab_see,x
        bmi @done
        ora #$80
        sta ab_see,x
        ldy a_t
        lda #E_SAW
        jsr ev_push
        lda ab_team,x           ; an officer who sees a suspect, when the heat
        cmp #T_POLICE           ; is up, turns on it
        bne @done
        lda ai_heat
        beq @done
        lda ab_beh,x
        cmp #B_PURSUE
        bcs @done               ; pursuing or attacking already
        ldy a_t
        jmp hostile
@unseen:
        lda ab_see,x
        bpl @done
        and #1
        sta ab_see,x
        ldy a_t
        lda #E_LOST
        jsr ev_push
@done:  rts

; radio: X = an officer who sees its target, a_t -> every officer after the
; same target hears where it is: their last sighting is this one, and their
; count of turns unseen starts again (one memory for the force, as a radio
; call would make it).  Civilians keep their own.
; After DMA Design's Race'n'Chase design (1995: a radio call to every police
; car) and the GTA games' shared last-seen search.  Changed: a copy of the
; sighting to each officer's brain, no search area.
radio:
        lda ab_team,x
        cmp #T_POLICE
        bne @done
        ldy #NB-1
@o:     lda ab_team,y
        cmp #T_POLICE
        bne @n
        lda ab_tgt,y
        cmp a_t
        bne @n
        lda ab_lxl,x
        sta ab_lxl,y
        lda ab_lxh,x
        sta ab_lxh,y
        lda ab_lyl,x
        sta ab_lyl,y
        lda ab_lyh,x
        sta ab_lyh,y
        lda ab_beh,y            ; a pursuer's unseen count starts again
        cmp #B_PURSUE
        bcc @n
        lda #0
        sta ab_tmr,y
@n:     dey
        bpl @o
@done:  rts

; seen_at: X = body, Y = its target -> where Y is is where X last saw it
seen_at:
        lda pb_xl,y
        sta ab_lxl,x
        lda pb_xh,y
        sta ab_lxh,x
        lda pb_yl,y
        sta ab_lyl,x
        lda pb_yh,y
        sta ab_lyh,x
        lda #0
        sta ab_tmr,x
        rts

; spread: X = body.  A civilian fleeing scares the calm civilians within
; SCARE of it into fleeing from what it flees
spread:
        lda ab_team,x
        bne @out
        lda ab_beh,x
        cmp #B_FLEE
        beq :+
@out:   rts
:       ldy #NB-1
@o:     lda pb_mov,y
        beq @n
        lda ab_team,y
        bne @n
        lda ab_beh,y
        cmp #B_FLEE
        beq @n
        cmp #B_NONE
        beq @n
        lda pb_xl,y             ; the low bytes first: nowhere near, no more
        sec
        sbc pb_xl,x
        clc
        adc #SCARE
        cmp #SCARE * 2
        bcs @n
        lda pb_yl,y
        sec
        sbc pb_yl,x
        clc
        adc #SCARE
        cmp #SCARE * 2
        bcs @n
        sty a_t
        jsr at_body
        jsr delta
        jsr far
        ldy a_t
        cmp #SCARE
        bcs @n
        lda ab_txl,x            ; the same threat
        sta ab_txl,y
        lda ab_txh,x
        sta ab_txh,y
        lda ab_tyl,x
        sta ab_tyl,y
        lda ab_tyh,x
        sta ab_tyh,y
        lda ab_tgt,x
        sta ab_tgt,y
        lda #B_FLEE
        sta ab_beh,y
        lda #60
        sta ab_tmr,y
        lda #255
        sta ab_alert,y
        stx a_n
        tya
        tax
        ldy a_n
        lda #E_PANIC            ; Y scared by X
        jsr ev_push
        ldx a_n
        ldy a_t
@n:     dey
        bmi :+
        jmp @o
:       rts

; ---------------------------------------------------------------------------
; behave: X = body.  Its behaviour sets dh (the heading it wants) and go
; (stop, walk, run); move then steers around walls and drives the body.
behave:
        lda ab_beh,x
        asl a
        tay
        lda beh_tab+1,y
        pha
        lda beh_tab,y
        pha
        rts
beh_tab: .word b_none-1, b_idle-1, b_wander-1, b_goto-1, b_follow-1, b_flee-1, b_pursue-1, b_attack-1, b_search-1

b_none: rts

b_idle: lda #0
        sta go
        jmp drive

b_wander:
        lda ab_tmr,x            ; a new way now and then
        beq @new
        dec ab_tmr,x
        jmp @on
@new:   lda rnd
        eor pb_xl,x
        sta ab_dir,x
        and #63
        clc
        adc #40
        sta ab_tmr,x
@on:    lda ab_dir,x
        sta dh
        lda #1
        sta go
        jsr blocked             ; a wall ahead: a new way next tick
        bcc :+
        lda #0
        sta ab_tmr,x
:       jmp move

b_goto: jsr at_point
        jsr delta
        jsr far
        cmp #6
        bcs @on
        lda #B_WANDER           ; there: it carries on about its business (a
        sta ab_beh,x            ; script decides otherwise on the event)
        ldy #$FF
        lda #E_ARRIVED
        jsr ev_push
        lda #0
        sta ab_tmr,x
        jmp b_wander
@on:    jsr heading
        sta dh
        lda #1
        sta go
        jmp move

b_follow:
        ldy ab_tgt,x
        cpy #NB
        bcs b_idle
        jsr at_body
        jsr delta
        jsr far
        cmp #24
        bcc b_idle
        cmp #64
        lda #1
        bcc :+
        lda #2
:       sta go
        jsr heading
        sta dh
        jmp move

b_flee: ldy ab_tgt,x            ; from a body, or from the point
        cpy #NB
        bcs :+
        jsr at_body
        jmp :++
:       jsr at_point
:       jsr delta
        jsr far
        cmp #FLEE_TO
        bcc @run
        dec ab_tmr,x            ; far enough: calm down after a while
        bne @run
        lda #B_WANDER
        sta ab_beh,x
        lda #0
        sta ab_alert,x
        jmp b_wander
@run:   jsr heading
        eor #$80                ; away
        sta dh
        lda #2
        sta go
        jmp move

; b_pursue: toward where the target will be, while it is seen; to where it
; was last seen when it is not; searching after LOST_T ticks unseen
b_pursue:
        ldy ab_tgt,x
        cpy #NB
        bcs @idle
        lda pb_mov,y
        beq @idle
        lda ab_see,x
        bmi @lead
        inc ab_tmr,x
        lda ab_tmr,x
        cmp #LOST_T
        bcc :+
        lda #B_SEARCH
        sta ab_beh,x
        lda #0
        sta ab_tmr,x
        jmp b_search
:       jsr at_last
        jmp @go
@lead:  jsr at_body
        jsr lead                ; plus its velocity times the time to it
@go:    jsr delta
        jsr heading
        sta dh
        lda #2
        sta go
        jmp move
@idle:  jmp b_idle

; b_attack: pursue it; in sight and in range, stop, face it and fire
b_attack:
        ldy ab_tgt,x
        cpy #NB
        bcs b_pursue
        lda ab_see,x
        bpl b_pursue
        jsr at_body
        jsr delta
        jsr far
        cmp #RANGE
        bcs b_pursue
        jsr heading
        sta dh
        lda pb_mov,x            ; a walker turns to face it
        cmp #M_FOOT
        bne :+
        lda dh
        sta pb_ang,x
:       lda ab_cool,x
        bne @hold
        lda #RATE
        sta ab_cool,x
        lda pb_xl,x
        sta col_x0
        lda pb_xh,x
        sta col_x0+1
        lda pb_yl,x
        sta col_y0
        lda pb_yh,x
        sta col_y0+1
        lda dh
        ldy #6
        jsr shot_fire
        ldx a_x
        ldy ab_tgt,x
        lda #E_FIRED
        jsr ev_push
@hold:  lda #0
        sta go
        jmp drive

; b_search: to where the target was last seen; there, look about; then give up
b_search:
        lda ab_tmr,x
        bne @look
        jsr at_last
        jsr delta
        jsr far
        cmp #8
        bcc @there
        jsr heading
        sta dh
        lda #1
        sta go
        jmp move
@there: lda #30                 ; turns of looking about
        sta ab_tmr,x
@look:  dec ab_tmr,x             ; there: it stands and looks about
        bne :+
        lda #B_WANDER           ; nothing: back to its beat
        sta ab_beh,x
        ldy ab_tgt,x
        lda #E_GAVEUP
        jsr ev_push
        jmp b_wander
:       jmp b_idle

; ---------------------------------------------------------------------------
; los: X = body, Y = its target, dx/dy and |dx|/|dy| from delta (under 255)
; -> C=1 if the straight line between their centres crosses no solid
; metatile.  The metatiles it crosses are visited one by one, each asked of
; the collision module (col_tile: one byte of DMA).
; After Amanatides and Woo, "A Fast Voxel Traversal Algorithm for Ray
; Tracing" (Eurographics 1987).  Changed: whole metatiles; the distances to
; the next boundary kept as dx- and dy-scaled integers, so a step is an add.
los:
        lda pb_xl,y             ; the end cell
        sta ex1
        lda pb_xh,y
        sta ex1+1
        lda pb_yl,y
        sta ey1
        lda pb_yh,y
        sta ey1+1
        ldy #5
:       lsr ex1+1
        ror ex1
        lsr ey1+1
        ror ey1
        dey
        bne :-
        lda pb_xl,x             ; the start cell
        sta cx
        lda pb_xh,x
        sta cx+1
        lda pb_yl,x
        sta cy
        lda pb_yh,x
        sta cy+1
        ldy #5
:       lsr cx+1
        ror cx
        lsr cy+1
        ror cy
        dey
        bne :-
        lda pb_xl,x             ; to the next x boundary: 32 - (x & 31) east, x & 31 west
        and #31
        ldy dxh
        bmi :+
        eor #31
        clc
        adc #1
:       ldy ady                 ; ex = that * |dy|: where along the line it comes
        jsr mul
        sta ex+1
        lda a_q
        sta ex
        lda pb_yl,x             ; the same for y, scaled by |dx|
        and #31
        ldy dyh
        bmi :+
        eor #31
        clc
        adc #1
:       ldy adx
        jsr mul
        sta ey+1
        lda a_q
        sta ey
        lda adx                 ; no x movement: never an x step; no y, never a y step
        bne :+
        lda #$FF
        sta ex
        sta ex+1
:       lda ady
        bne :+
        lda #$FF
        sta ey
        sta ey+1
:       lda #32                 ; a whole metatile of x, and of y, in the same measure
        ldy ady
        jsr mul
        sta ix+1
        lda a_q
        sta ix
        lda #32
        ldy adx
        jsr mul
        sta iy+1
        lda a_q
        sta iy
        lda #12                 ; at most 12 metatiles along 120 pixels
        sta a_f
@step:  lda cx
        cmp ex1
        bne :+
        lda cy
        cmp ey1
        bne :+
        sec                     ; the target's metatile: nothing in the way
        rts
:       dec a_f
        bne :+
        sec                     ; (a bound, never reached)
        rts
:       lda ex                  ; the nearer boundary: x or y
        cmp ey
        lda ex+1
        sbc ey+1
        bcs @y
        lda ex                  ; x
        clc
        adc ix
        sta ex
        lda ex+1
        adc ix+1
        sta ex+1
        lda dxh
        bmi :+
        inc cx
        bne @test
        inc cx+1
        bne @test
:       lda cx
        bne :+
        dec cx+1
:       dec cx
        jmp @test
@y:     lda ey
        clc
        adc iy
        sta ey
        lda ey+1
        adc iy+1
        sta ey+1
        lda dyh
        bmi :+
        inc cy
        bne @test
        inc cy+1
        bne @test
:       lda cy
        bne :+
        dec cy+1
:       dec cy
@test:  lda cx                  ; is this metatile solid?
        sta col_x0
        lda cx+1
        sta col_x0+1
        lda cy
        sta col_y0
        lda cy+1
        sta col_y0+1
        ldy #5
:       asl col_x0
        rol col_x0+1
        asl col_y0
        rol col_y0+1
        dey
        bne :-
        jsr col_tile
        ldx a_x
        and #P_SOLID
        bne :+
        jmp @step
:       clc
        rts

; mul: A * Y (A up to 63) -> A:a_q (high:low).  Keeps X.
mul:    sta a_n
        sty a_l
        lda #0
        sta a_q
        sta a_s                 ; the multiplicand's high byte as it shifts
        tay                     ; the product's high byte
@l:     lsr a_n
        bcc :+
        lda a_q
        clc
        adc a_l
        sta a_q
        tya
        adc a_s
        tay
:       asl a_l
        rol a_s
        lda a_n
        bne @l
        tya
        rts

; ---------------------------------------------------------------------------
; where: at_body (Y = a body), at_point (the body's own point), at_last (where
; it last saw its target), at_noise (ai_px/py) -> tx/ty
at_body:
        lda pb_xl,y
        sta tx
        lda pb_xh,y
        sta tx+1
        lda pb_yl,y
        sta ty
        lda pb_yh,y
        sta ty+1
        rts
at_point:
        lda ab_txl,x
        sta tx
        lda ab_txh,x
        sta tx+1
        lda ab_tyl,x
        sta ty
        lda ab_tyh,x
        sta ty+1
        rts
at_last:
        lda ab_lxl,x
        sta tx
        lda ab_lxh,x
        sta tx+1
        lda ab_lyl,x
        sta ty
        lda ab_lyh,x
        sta ty+1
        rts
at_noise:
        lda ai_px
        sta tx
        lda ai_px+1
        sta tx+1
        lda ai_py
        sta ty
        lda ai_py+1
        sta ty+1
        rts

; lead: Y = the target, tx/ty its position -> tx/ty plus its velocity
; (whole pixels a frame) times 8 frames.  Keeps X and Y.
lead:
        lda pb_vxh,y
        jsr @x8
        clc
        adc tx
        sta tx
        lda a_q
        adc tx+1
        sta tx+1
        lda pb_vyh,y
        jsr @x8
        clc
        adc ty
        sta ty
        lda a_q
        adc ty+1
        sta ty+1
        rts
@x8:    sta a_n                 ; A signed -> A = low, a_q = high, of A * 8
        and #$80
        beq :+
        lda #$FF
:       sta a_q
        lda a_n
        asl a
        rol a_q
        asl a
        rol a_q
        asl a
        rol a_q
        rts

; delta: X = body -> dx, dy from it to tx/ty (16-bit) and |dx|, |dy| to a byte
delta:
        lda tx
        sec
        sbc pb_xl,x
        sta dxl
        lda tx+1
        sbc pb_xh,x
        sta dxh
        lda ty
        sec
        sbc pb_yl,x
        sta dyl
        lda ty+1
        sbc pb_yh,x
        sta dyh
        lda dxl
        sta a_q
        lda dxh
        jsr abs8
        sta adx
        lda dyl
        sta a_q
        lda dyh
        jsr abs8
        sta ady
        rts
; abs8: A = high, a_q = low -> A = |it|, 255 if 255 or more
abs8:   bmi @neg
        bne @far
        lda a_q
        rts
@neg:   cmp #$FF
        bne @far
        lda a_q
        eor #$FF
        clc
        adc #1
        beq @far
        rts
@far:   lda #255
        rts
; far: A = the larger of |dx|, |dy|
far:    lda adx
        cmp ady
        bcs :+
        lda ady
:       rts

; heading: dx/dy -> A = the heading that way (0 east, 64 south, 256 a turn).
; The octant from the signs and which is larger; within it, the angle of
; smaller / larger from a 32-entry table, the ratio by a 5-bit division.
heading:
        lda adx
        cmp #255
        beq h_far               ; either far: from the full 16 bits
        lda ady
        cmp #255
        beq h_far
        lda adx
        ldy ady
h_bytes:
        sty a_s                 ; A = |dx|, Y = |dy|, both bytes
        cmp a_s
        bcs :+
        sta a_s                 ; |dy| larger: swap, remember
        sty a_l
        lda #$40
        bne :++
:       sta a_l
        lda #0
:       sta a_f
        lda a_l
        beq @zero
        lda #0
        sta a_q
        lda a_s
        ldy #5
@d:     asl a
        bcs @s
        cmp a_l
        bcc @z
@s:     sbc a_l
        sec
@z:     rol a_q
        dey
        bne @d
        ldy a_q
        lda atab,y
        bit a_f
        bvc :+
        eor #$FF                ; 64 - a, for the steeper half
        sec
        adc #64
:       ldy dxh                 ; the quadrant
        bpl @xp
        eor #$FF                ; 128 - a
        sec
        adc #128
@xp:    ldy dyh
        bpl @done
        eor #$FF                ; 256 - a
        clc
        adc #1
@done:  rts
@zero:  lda #0
        rts
; h_far: shift the 16-bit magnitudes down until both fit a byte
h_far:  lda dxl
        sta a_q
        lda dxh
        bpl :+
        lda #0
        sec
        sbc dxl
        sta a_q
        lda #0
        sbc dxh
:       sta a_n                 ; |dx| = a_n:a_q
        lda dyl
        sta a_s
        lda dyh
        bpl :+
        lda #0
        sec
        sbc dyl
        sta a_s
        lda #0
        sbc dyh
:       sta a_l                 ; |dy| = a_l:a_s
:       lda a_n
        ora a_l
        beq :+
        lsr a_n
        ror a_q
        lsr a_l
        ror a_s
        jmp :-
:       lda a_q
        ldy a_s
        jmp h_bytes

; atan(q / 32) in heading units (32 = 45 degrees), q = 0-31
atab:   .byte 0, 1, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 15, 16, 17, 18
        .byte 19, 20, 21, 22, 23, 24, 25, 25, 26, 27, 28, 29, 29, 30, 31, 31

; ---------------------------------------------------------------------------
; blocked: X = body, A = a heading -> C=1 if a wall to its mover lies 12
; pixels that way: straight ahead, or ahead at either side of its box (its
; half width across the way), so a corner cannot catch the box's edge.
; From the physics module's cache of the 3 x 3 metatiles around the body.
blocked:
        clc
        adc #16
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        sta bway                ; the way, 0-7
        tay
        lda wx,y
        sta px
        lda wy,y
        sta py
        jsr probe               ; straight ahead
        bcs @yes
        lda bway                ; across the way: two ways round
        clc
        adc #2
        and #7
        tay
        lda sx+8,y              ; +hw, 0 or -hw on each axis: the sign
        sta osgn
        lda sx,y
        beq :+
        lda pb_hw,x
        bit osgn
        bpl :+
        eor #$FF
        clc
        adc #1
:       sta ox
        ldy bway
        iny
        iny
        tya
        and #7
        tay
        lda sy+8,y
        sta osgn
        lda sy,y
        beq :+
        lda pb_hw,x
        bit osgn
        bpl :+
        eor #$FF
        clc
        adc #1
:       sta oy
        ldy bway
        lda wx,y                ; ahead, one side
        clc
        adc ox
        sta px
        lda wy,y
        clc
        adc oy
        sta py
        jsr probe
        bcs @yes
        ldy bway
        lda wx,y                ; ahead, the other side
        sec
        sbc ox
        sta px
        lda wy,y
        sec
        sbc oy
        sta py
        jmp probe
@yes:   rts

; probe: X = body, px/py = a signed offset -> C=1 if the metatile there is a
; wall to its mover
probe:
        lda pb_xl,x
        and #31
        clc
        adc px
        jsr third               ; column 0-2
        sta a_n
        lda pb_yl,x
        and #31
        clc
        adc py
        jsr third
        sta a_q                 ; row
        asl a
        adc a_q
        adc a_n                 ; row * 3 + column
        tay
        lda k12,y
        clc
        adc a_x
        tay
        lda cache,y
        ldy pb_mov,x
        and m_and,y
        eor m_eor,y
        cmp #1                  ; C=1: something
        rts
third:  bmi @l
        cmp #32
        bcs @r
        lda #1
        rts
@l:     lda #0
        rts
@r:     lda #2
        rts
; the ways' axes: nonzero where the way has a component (the first eight), and
; its sign (the second eight)
sx:     .byte 1, 1, 0, 1, 1, 1, 0, 1
        .byte 0, 0, 0, $FF, $FF, $FF, 0, 0
sy:     .byte 0, 1, 1, 1, 0, 1, 1, 1
        .byte 0, 0, 0, 0, 0, $FF, $FF, $FF
wx:     .byte 12, 8, 0, <-8, <-12, <-8, 0, 8
wy:     .byte 0, 8, 12, 8, 0, <-8, <-12, <-8
k12:    .byte 0*NB, 1*NB, 2*NB, 3*NB, 4*NB, 5*NB, 6*NB, 7*NB, 8*NB
; what each mover counts as a wall, as in the physics modules
m_and:  .byte 0, WALL, WALL, P_WATER | P_SHALLOW, 0, 0, 0, P_WATER
m_eor:  .byte 0, 0, 0, P_WATER, 0, 0, 0, P_WATER

; move: X = body.  Steer round a wall ahead (a quarter turn the way nearer
; its heading, then the other, then a half), then drive
move:   lda go
        beq drive
        lda dh
        jsr blocked
        bcc drive
        lda #0
        sta a_f
@try:   ldy a_f
        lda dh
        clc
        adc turns,y
        sta cand
        jsr blocked
        bcc @ok
        inc a_f
        lda a_f
        cmp #6
        bcc @try
        lda #0                  ; boxed in: stop
        sta go
        beq drive
@ok:    lda cand
        sta dh
; drive: X = body, dh, go -> its input byte, by its mover: the stick's eight
; ways for a walker (fire to run) or a helicopter; steering and throttle for
; anything with a hull or wheels
drive:  lda pb_mov,x
        cmp #M_FOOT
        beq @stick
        cmp #M_AIR
        beq @stick
        lda go
        bne @steer
        lda pb_vlh,x            ; stop: brake while it rolls forward
        bmi :+
        ora pb_vll,x
        beq :+
        lda #IN_DOWN
        bne @set
:       lda #0
        beq @set
@steer: lda dh
        sec
        sbc pb_ang,x
        clc
        adc #6
        cmp #13
        lda #IN_UP              ; within 6: straight on
        bcc @set
        lda dh
        sec
        sbc pb_ang,x
        clc                     ; more than 3/8 of a turn off the nose: a
        adc #96                 ; three-point turn, backing with the other lock
        cmp #193                ; (backing turns the other way)
        bcs @back
        sbc #95                 ; (C=0: back to the difference)
        bmi :+
        lda #IN_UP | IN_RIGHT
        bne @set
:       lda #IN_UP | IN_LEFT
        bne @set
@back:  sbc #96                 ; (C=1)
        bmi :+
        lda #IN_DOWN | IN_LEFT
        bne @set
:       lda #IN_DOWN | IN_RIGHT
        bne @set
@stick: lda go
        beq @set
        lda dh
        clc
        adc #16
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        tay
        lda stick,y
        ldy go
        cpy #2
        bcc @set
        ldy pb_mov,x
        cpy #M_FOOT
        bne @set
        ora #IN_FIRE            ; a walker runs
@set:   sta pb_in,x
        rts
turns:  .byte 32, <-32, 64, <-64, 96, <-96
stick:  .byte IN_RIGHT, IN_RIGHT | IN_DOWN, IN_DOWN, IN_DOWN | IN_LEFT
        .byte IN_LEFT, IN_LEFT | IN_UP, IN_UP, IN_UP | IN_RIGHT

; ---------------------------------------------------------------------------
cand:   .res 1                  ; move: the heading being tried
bway:   .res 1                  ; blocked: the way, 0-7
px:     .res 1                  ; blocked: the offset probed
py:     .res 1
osgn:   .res 1
ox:     .res 1                  ; and the box's half width across the way
oy:     .res 1
cx:     .res 2                  ; los: the metatile, the end one, the boundaries
cy:     .res 2
ex1:    .res 2
ey1:    .res 2
ex:     .res 2
ey:     .res 2
ix:     .res 2
iy:     .res 2
tx:     .res 2                  ; the point being considered
ty:     .res 2
rnd:    .res 1
ev_head: .res 1                 ; the events: a ring of 16
ev_tail: .res 1
ev_k:   .res 16
ev_b:   .res 16
ev_a:   .res 16
