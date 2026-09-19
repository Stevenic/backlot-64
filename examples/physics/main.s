; backlot-64 example: on foot and at the wheel, on the physics module.
;
; The physics module (modules/physics, docs/PHYSICS.md) is pinned at $6000
; from the REU at the start.  You begin on foot on a Bellamar pavement,
; beside four parked vehicles (a sedan, a sports car, a truck, a bike) with
; people walking by.  Every one of them is a physics body: walk into a car
; and you stop; tap fire beside one and you are driving it; drive into the
; others and they are shoved by their mass and take damage; drive into the
; people and they are knocked down.
;
; Joystick 2.  On foot: eight directions, fire held to run, fire tapped
; beside a car to get in.  Driving: up for throttle, down to brake and then
; reverse, left and right to steer, fire held for the handbrake, fire tapped
; when stopped to get out.  Assemble with -D AUTODRIVE=1 to play a recorded
; tape instead (the check does).

.include "b64.inc"
.include "slots.inc"
.include "../../modules/physics/physics.inc"
.include "physics_syms.inc"
.include "collision_syms.inc"

.export game_main

PCX     = 160                   ; the player's place on the playfield
PCY     = 92
START_X = 1300 * 32 + 16        ; the pavement south of the road at metatile row 1000
START_Y = 1001 * 32 + 16
LANE_E  = 1000 * 32 + 24        ; the road's eastbound lane
LANE_W  = 1000 * 32 + 8

.segment "GAMETOP"
player:  .res 1                 ; the body the stick drives
driving: .res 1                 ; 1 in a car
joy:     .res 1
joywas:  .res 1
tick:    .res 2
ped_t:   .res PHYS_NB           ; per pedestrian: frames until it picks a new way
ped_in:  .res PHYS_NB
colour:  .res PHYS_NB
tape_i:  .res 1                 ; AUTODRIVE: the tape's position and frames left
tape_n:  .res 1
rnd:     .res 1
camdx:   .res 2
hudbuf:  .res 41

.segment "GAME"
game_main:
        jsr b64_init
        B64_SET24 b64_reu, SLOT_TILESET0
        jsr b64_load_tileset
        lda #11
        sta VIC_BG_COLOR0
        lda #15
        sta VIC_BG_COLOR1
        lda #1
        sta VIC_BG_COLOR2
        lda #11
        sta VIC_BORDERCOLOR
        ; pin the physics module at $6000
        B64_SET24 b64_reu, SLOT_PHYSICS
        B64_SET16 b64_ptr, PHYS_BASE
        B64_SET16 b64_len, PHYS_SIZE
        jsr b64_fetch
        B64_SET24 b64_reu, SLOT_COLLISION      ; and the collision module in region A
        B64_SET16 b64_ptr, $8000
        B64_SET16 b64_len, $1000
        jsr b64_fetch
        jsr col_init
        jsr phys_init
        lda #<SLOT_WORLD
        sta phys_world
        lda #>SLOT_WORLD
        sta phys_world+1
        lda #^SLOT_WORLD
        sta phys_world+2
        lda #$5D
        sta rnd
        lda #0
        sta tick
        sta tick+1
        sta driving
        sta joywas
        sta tape_i
        sta tape_n
        ; the bodies, from the table below
        ldx #0
@add:   lda start_mov,x
        beq @added
        stx camdx
        lda start_xl,x
        sta phys_x
        lda start_xh,x
        sta phys_x+1
        lda start_yl,x
        sta phys_y
        lda start_yh,x
        sta phys_y+1
        lda start_ang,x
        sta phys_a
        ldy start_cls,x
        lda start_mov,x
        jsr phys_add
        lda camdx               ; the first body is the player, on foot
        bne :+
        stx player
:       ldy camdx
        lda start_col,y
        sta colour,x
        lda #0
        sta ped_t,x
        sta ped_in,x
        ldx camdx
        inx
        bne @add
@added: B64_SET16 b64_cam_x, START_X - PCX
        B64_SET16 b64_cam_y, START_Y - PCY
        jsr b64_redraw
        lda #PCX + 12
        sta VIC_SPR0_X
        lda #PCY + 40
        sta VIC_SPR0_Y
        lda #13
        sta VIC_SPR0_COLOR
        lda #1
        sta VIC_SPR_ENA
        sta VIC_SPR_MCOLOR
        lda #0
        sta VIC_SPR_MCOLOR0
        lda #1
        sta VIC_SPR_MCOLOR1
        jsr hud_update
        lda #<frame
        ldx #>frame
        jsr b64_set_callback
        jmp b64_run

; the starting bodies: the player, four parked vehicles, four walkers
start_mov: .byte M_FOOT, M_WHEELS, M_WHEELS, M_WHEELS, M_WHEELS, M_FOOT, M_FOOT, M_FOOT, M_FOOT, 0
start_cls: .byte C_WALKER, C_SEDAN, C_SPORTS, C_TRUCK, C_BIKE, C_WALKER, C_WALKER, C_WALKER, C_WALKER
start_xl:  .byte <START_X, <(START_X - 14), <(START_X + 60), <(START_X + 130), <(START_X - 70), <(START_X + 70), <(START_X + 140), <(START_X - 90), <(START_X + 20)
start_xh:  .byte >START_X, >(START_X - 14), >(START_X + 60), >(START_X + 130), >(START_X - 70), >(START_X + 70), >(START_X + 140), >(START_X - 90), >(START_X + 20)
start_yl:  .byte <START_Y, <LANE_E, <LANE_E, <LANE_E, <LANE_W, <START_Y, <START_Y, <START_Y, <(START_Y - 64)
start_yh:  .byte >START_Y, >LANE_E, >LANE_E, >LANE_E, >LANE_W, >START_Y, >START_Y, >START_Y, >(START_Y - 64)
start_ang: .byte 0, 0, 0, 0, 128, 0, 0, 0, 0
start_col: .byte 13, 2, 7, 15, 14, 4, 6, 3, 8

; ---------------------------------------------------------------------------
frame:
        inc tick
        bne :+
        inc tick+1
:       jsr input
        jsr control
        jsr walkers
        jsr phys_step
        jsr shot_step
        jsr follow
        jsr submit
        lda tick
        and #7
        bne :+
        jsr hud_update
:       rts

; input: the stick, or the tape
input:
.ifdef AUTODRIVE
        lda tape_n
        bne @run
        ldx tape_i
        lda tape_len,x
        bne :+
        lda #0                  ; the tape is over: hands off
        sta joy
        rts
:       sta tape_n
        inc tape_i
@run:   dec tape_n
        ldx tape_i
        lda tape_joy-1,x
        sta joy
        rts
.else
        lda b64_joy
        sta joy
        rts
.endif

; control: the stick to the player's body; fire tapped gets in or out
control:
        lda joy                 ; tapped: fire now, not the frame before
        and #IN_FIRE
        tax
        lda joywas
        eor #$FF
        stx joywas
        and joywas
        sta tapped
        ldx player
        lda driving
        bne @car
        lda tapped              ; on foot: a tap beside a car gets in, elsewhere fires
        beq @walk
        jsr get_in
        bcc :+
        rts
:       jsr fire
        ldx player
@walk:  lda joy
        sta pb_in,x
        rts
@car:   lda tapped              ; driving: a tap when all but stopped gets out
        beq @drive
        lda pb_vlh,x
        beq @slow
        cmp #$FF
        bne @drive
        lda pb_vll,x
        cmp #$D0
        bcc @drive
        bcs @out
@slow:  lda pb_vll,x
        cmp #$30
        bcs @drive
@out:   jmp get_out
@drive: lda joy
        sta pb_in,x
        rts

; get_in: the nearest body within 22 pixels (the collision module's
; col_near), if it is a car; C=1 if in
get_in:
        lda #22
        jsr col_near
        bcc @no
        lda pb_mov,y
        cmp #M_WHEELS
        bne @no
        sty camdx+1             ; in: the walker goes, the car is the player's
        jsr phys_remove
        ldx camdx+1
        stx player
        lda #0
        sta pb_in,x
        lda #1
        sta driving
        lda colour,x
        sta VIC_SPR0_COLOR
        sec
        rts
@no:    ldx player
        clc
        rts

; fire: a shot from the player the way it faces, 6 pixels a frame; standing
; still (no direction held), a grenade tossed that way instead
fire:
        ldx player
        lda pb_xl,x
        sta col_x0
        lda pb_xh,x
        sta col_x0+1
        lda pb_yl,x
        sta col_y0
        lda pb_yh,x
        sta col_y0+1
        lda joy
        and #$0F
        beq @toss
        lda pb_ang,x
        ldy #6
        jmp shot_fire
@toss:  lda pb_ang,x
        ldy #2
        jmp throw_fire

; get_out: a walker beside the car (18 pixels south of it); the car coasts
get_out:
        lda #0
        sta pb_in,x
        stx camdx+1
        lda pb_xl,x
        sta phys_x
        lda pb_xh,x
        sta phys_x+1
        lda pb_yl,x
        clc
        adc #18
        sta phys_y
        lda pb_yh,x
        adc #0
        sta phys_y+1
        lda #64
        sta phys_a
        lda #M_FOOT
        ldy #C_WALKER
        jsr phys_add
        bcc @no
        stx player
        lda #13
        sta colour,x
        sta VIC_SPR0_COLOR
        lda #0
        sta driving
@no:    rts

; walkers: every walker but the player picks a way now and then, and turns
; back from a wall
walkers:
        ldx #PHYS_NB-1
@w:     cpx player
        beq @n
        lda pb_mov,x
        cmp #M_FOOT
        bne @n
        lda pb_st,x
        and #ST_WALL
        bne @pick
        lda ped_t,x
        beq @pick
        dec ped_t,x
        jmp @go
@pick:  jsr random
        and #7
        tay
        lda ped_ways,y
        sta ped_in,x
        jsr random
        and #63
        clc
        adc #40
        sta ped_t,x
@go:    lda ped_in,x
        sta pb_in,x
@n:     dex
        bpl @w
        rts
ped_ways: .byte IN_LEFT, IN_RIGHT, IN_LEFT, IN_RIGHT, 0, IN_UP, IN_DOWN, IN_LEFT

random:
        lda rnd
        asl
        bcc :+
        eor #$1D
:       sta rnd
        rts

; follow: the camera toward the player, 8 pixels a frame at most
follow:
        ldx player
        lda pb_xl,x
        sec
        sbc #<PCX
        sta camdx
        lda pb_xh,x
        sbc #>PCX
        sta camdx+1
        lda camdx
        sec
        sbc b64_cam_x
        sta camdx
        lda camdx+1
        sbc b64_cam_x+1
        jsr clamp8
        pha
        lda pb_yl,x
        sec
        sbc #<PCY
        sta camdx
        lda pb_yh,x
        sbc #>PCY
        sta camdx+1
        lda camdx
        sec
        sbc b64_cam_y
        sta camdx
        lda camdx+1
        sbc b64_cam_y+1
        jsr clamp8
        tax
        pla
        jmp b64_move_camera
; clamp8: camdx = low byte, A = high byte of a difference -> A in -8..8
clamp8:
        bmi @neg
        bne @p8
        lda camdx
        cmp #9
        bcc @done
@p8:    lda #8
        rts
@neg:   cmp #$FF
        bne @m8
        lda camdx
        cmp #<-8
        bcs @done
@m8:    lda #<-8
        rts
@done:  lda camdx
        rts

; ---------------------------------------------------------------------------
; submit: the player on sprite 0, every other body on the multiplexer
submit:
        jsr b64_spr_begin
        ldx player
        jsr frame_of
        jsr b64_spr_pinned
        ldx player              ; sprite 0 where the player is on screen (the
        lda pb_xl,x             ; camera catches up after getting in or out)
        sec
        sbc b64_cam_x
        clc
        adc #12
        cmp #24
        bcs :+
        lda #24
:       sta VIC_SPR0_X
        lda pb_yl,x
        sec
        sbc b64_cam_y
        clc
        adc #40
        sta VIC_SPR0_Y
        ldx #PHYS_NB-1
@b:     cpx player
        beq @n
        lda pb_mov,x
        beq @n
        stx sb_x
        jsr submit_body
        ldx sb_x
@n:     dex
        bpl @b
        jsr submit_shots
        jmp b64_spr_end

; submit_shots: each shot in flight, and the last hit while it shows
submit_shots:
        ldx #NS-1
@s:     lda sh_on,x
        beq @n
        lda sh_xl,x
        sta shx
        lda sh_xh,x
        sta shx+1
        lda sh_yl,x
        sta shy
        lda sh_yh,x
        sta shy+1
        txa
        clc
        adc #13                 ; slots 13-20
        sta b64_spr_slot
        lda #1
        stx sb_x
        jsr submit_dot
        ldx sb_x
@n:     dex
        bpl @s
        lda fx_t
        beq @done
        lda fx_k
        cmp #2
        beq @ring
        lda fx_x                ; a shot's stop: a dot
        sta shx
        lda fx_x+1
        sta shx+1
        lda fx_y
        sta shy
        lda fx_y+1
        sta shy+1
        lda #21
        sta b64_spr_slot
        lda #7
        jsr submit_dot
        jmp @done
@ring:  lda #12                 ; a blast: four dots on a ring growing 3 pixels a frame
        sec
        sbc fx_t
        sta ring_r
        asl a
        adc ring_r
        sta ring_r
        ldx #3
@rd:    stx sb_x
        txa
        lsr a                   ; bit 0: left or right
        lda fx_x
        ldy fx_x+1
        jsr ring_off
        sta shx
        sty shx+1
        lda sb_x
        lsr a
        lsr a                   ; bit 1: up or down
        lda fx_y
        ldy fx_y+1
        jsr ring_off
        sta shy
        sty shy+1
        lda #21                 ; the one frame, shared
        sta b64_spr_slot
        lda fx_t                ; yellow and orange by turns
        lsr a
        and #1
        clc
        adc #7
        jsr submit_dot
        ldx sb_x
        dex
        bpl @rd
@done:  ldx #NT-1                ; thrown things: raised by their height, a shadow below
@t:     lda th_on,x
        beq @tn
        stx sb_x
        lda th_xl,x
        sta shx
        lda th_xh,x
        sta shx+1
        lda th_yl,x
        sta shy
        lda th_yh,x
        sta shy+1
        txa
        clc
        adc #22
        sta b64_spr_slot
        lda #0                  ; the shadow
        jsr submit_dot
        ldx sb_x
        lda th_yl,x             ; the thing itself, up by its height
        sec
        sbc th_zh,x
        sta shy
        lda th_yh,x
        sbc #0
        sta shy+1
        lda sb_x
        clc
        adc #26
        sta b64_spr_slot
        lda #7
        jsr submit_dot
        ldx sb_x
@tn:    dex
        bpl @t
        rts

; ring_off: A/Y = a coordinate -> A/Y = it plus ring_r, or minus it when C=1
ring_off:
        bcs @sub
        adc ring_r
        bcc :+
        iny
:       rts
@sub:   sbc ring_r
        bcs :+
        dey
:       rts

; submit_dot: shx/shy (world), A = colour, b64_spr_slot -> the lamp frame there
submit_dot:
        sta b64_spr_colour
        lda shx
        sec
        sbc b64_cam_x
        sta camdx
        lda shx+1
        sbc b64_cam_x+1
        sta camdx+1
        lda camdx
        clc
        adc #12
        sta b64_spr_x
        lda camdx+1
        adc #0
        sta b64_spr_x+1
        beq :+
        cmp #1
        bne @off
        lda b64_spr_x
        cmp #<344
        bcs @off
:       lda shy
        sec
        sbc b64_cam_y
        tay
        lda shy+1
        sbc b64_cam_y+1
        bne @off
        tya
        clc
        adc #40
        bcs @off
        cmp #30
        bcc @off
        cmp #250
        bcs @off
        sta b64_spr_y
        B64_SET24 b64_reu, SLOT_LAMP
        lda #0
        sta b64_spr_flags
        jmp b64_spr_add
@off:   rts

; submit_body: X = body, onto the multiplexer if it is on screen
submit_body:
        lda pb_xl,x             ; sprite x = x - camera x + 12
        sec
        sbc b64_cam_x
        sta camdx
        lda pb_xh,x
        sbc b64_cam_x+1
        sta camdx+1
        lda camdx
        clc
        adc #12
        sta b64_spr_x
        lda camdx+1
        adc #0
        sta b64_spr_x+1
        beq @xok
        cmp #1
        bne sb_out
        lda b64_spr_x
        cmp #<344
        bcs sb_out
@xok:   lda pb_yl,x             ; sprite y = y - camera y + 40
        sec
        sbc b64_cam_y
        sta camdx
        lda pb_yh,x
        sbc b64_cam_y+1
        bne sb_out
        lda camdx
        clc
        adc #40
        bcs sb_out
        cmp #30
        bcc sb_out
        cmp #250
        bcs sb_out
        sta b64_spr_y
        stx camdx
        jsr frame_of
        ldx camdx
        txa
        clc
        adc #1
        sta b64_spr_slot
        lda colour,x
        ldy pb_st,x
        cpy #ST_DOWN            ; knocked down: shown in pink
        bcc :+
        tya
        and #ST_DOWN
        beq :+
        lda #10
        bne :++
:       lda colour,x
:       sta b64_spr_colour
        lda #B64_SPR_FLAG_MC
        sta b64_spr_flags
        jsr b64_spr_add
sb_out: rts

; frame_of: X = body -> b64_reu = its sprite frame: a car at one of 16
; headings, a walker in one of two steps
frame_of:
        lda pb_mov,x
        cmp #M_WHEELS
        bne @foot
        lda pb_ang,x
        clc
        adc #8
        lsr
        lsr
        lsr
        lsr                     ; heading / 16
        ldy #0
        sty b64_reu+1
        lsr                     ; * 64 = (frame >> 2) << 8 | (frame & 3) << 6
        ror b64_reu+1
        lsr
        ror b64_reu+1
        sta b64_reu+2           ; frame >> 2 for now
        lda b64_reu+1
        clc
        adc #<SLOT_CARS16
        sta b64_reu
        lda b64_reu+2
        adc #>SLOT_CARS16
        sta b64_reu+1
        lda #^SLOT_CARS16
        adc #0
        sta b64_reu+2
        rts
@foot:  lda pb_xl,x             ; the step: every 8 pixels walked
        eor pb_yl,x
        and #8
        beq :+
        lda #64
:       clc
        adc #<(SLOT_SPRITES0 + 4 * 64)
        sta b64_reu
        lda #>(SLOT_SPRITES0 + 4 * 64)
        adc #0
        sta b64_reu+1
        lda #^(SLOT_SPRITES0 + 4 * 64)
        adc #0
        sta b64_reu+2
        rts

; ---------------------------------------------------------------------------
; hud_update: what the player is doing
hud_update:
        ldy #40
:       lda hud_tpl,y
        sta hudbuf,y
        dey
        bpl :-
        ldx player
        lda driving
        bne @car
        ldy #0                  ; "ON FOOT"
:       lda txt_foot,y
        beq @show
        sta hudbuf,y
        iny
        bne :-
@car:   ldy pb_cls,x            ; the class name
        lda cls_off,y
        tay
        ldx #0
:       lda cls_names,y
        beq :+
        sta hudbuf,x
        iny
        inx
        bne :-
:       ldx player
        lda pb_vlh,x            ; speed: |v_long|, one decimal
        sta camdx+1
        lda pb_vll,x
        sta camdx
        lda camdx+1
        bpl :+
        lda #0
        sec
        sbc camdx
        sta camdx
        lda #0
        sbc camdx+1
        sta camdx+1
:       lda camdx+1
        and #7
        clc
        adc #'0'
        sta hudbuf+14
        lda camdx               ; the tenths: low * 10 / 256
        lsr
        lsr
        lsr
        lsr
        tay
        lda tenths,y
        sta hudbuf+16
        lda pb_dmg,x
        jsr put_dec3
        lda pb_st,x
        and #ST_SKID
        beq @show
        ldy #3
:       lda txt_skid,y
        sta hudbuf+35,y
        dey
        bpl :-
@show:  B64_SET16 b64_val, hudbuf
        ldx #0
        jmp b64_hud_text

; put_dec3: A = 0-255 -> hudbuf+29..31
put_dec3:
        ldy #'0'
:       cmp #100
        bcc :+
        sbc #100
        iny
        bne :-
:       sty hudbuf+29
        ldy #'0'
:       cmp #10
        bcc :+
        sbc #10
        iny
        bne :-
:       sty hudbuf+30
        clc
        adc #'0'
        sta hudbuf+31
        rts

hud_tpl:   .byte "              0.0 PX  DAMAGE 000         ", 0
txt_foot:  .byte "ON FOOT", 0
txt_skid:  .byte "SKID"
cls_names: .byte "SEDAN", 0, "SPORTS", 0, "TRUCK", 0, "BIKE", 0
cls_off:   .byte 0, 0, 6, 13, 19
tenths:    .byte "0112334456678899"

; ---------------------------------------------------------------------------
; the tape (AUTODRIVE): frames, then the stick
.ifdef AUTODRIVE
; walk to the sedan and get in; drive into the others; coast, brake and
; reverse, turn; get up speed, then drift (the handbrake is fire held when
; moving: a tap when all but stopped would get out); brake to a stop, get out;
; walk east, fire, toss a grenade; face north, fire; walk south, away from
; the cars (a tap within reach of one gets in), face west, toss another
tape_len:  .byte 40, 6, 1, 1, 100, 30, 50, 25, 15, 25, 20, 40, 1, 1, 60, 1, 30, 1, 30, 4, 1, 30, 25, 3, 10, 1, 100, 0
tape_joy:  .byte 0, IN_UP, IN_UP | IN_FIRE, 0, IN_UP, 0, IN_DOWN, IN_UP | IN_LEFT, IN_UP | IN_RIGHT, IN_UP | IN_RIGHT | IN_FIRE
           .byte IN_DOWN, 0, IN_FIRE, 0, IN_RIGHT, IN_RIGHT | IN_FIRE, 0, IN_FIRE, 0, IN_UP, IN_UP | IN_FIRE, 0, IN_DOWN
           .byte IN_LEFT, 0, IN_FIRE, 0
.endif

.segment "GAMETOP"
shx:    .res 2
shy:    .res 2
tapped: .res 1
sb_x:   .res 1
ring_r: .res 1
