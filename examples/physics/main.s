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
; when stopped to get out.  Flying: the stick moves, fire held climbs, let
; go it settles; down with fire tapped, on the ground, gets out.  Assemble with -D AUTODRIVE=1 to play a recorded
; tape instead (the check does).
;
; Assembled with -D COAST=1 (make run-boats) it starts on the beach where the
; road meets the sea, beside a moored speedboat, with a launch and a jet ski
; at sea.  Getting into a boat fetches the water module over the ground
; module at $6000; getting out onto land fetches the ground module back.
; Every module is called through its jump table (PHYS_STEP and the rest), so
; the same calls work whichever is in.  A boat steers like a car without
; grip; down is reverse thrust.
;
; Assembled with -D MARSH=1 (make run-marsh) it starts on the sand beside a
; marsh with an airboat on the reeds: the marsh is water to an airboat and a
; wall to a boat, and a speedboat at sea shows it.
;
; Assembled with -D DEBRIS=1 (make run-debris) it plays a tape of crashes
; and a blast; each throws out debris, which ignores everything but the
; ground.  Only this scene asks for debris: every piece is a sprite, and the
; city scene has no frame time to spare for one.
;
; Assembled with -D PLANE=1 (make run-plane) it has a light plane on the
; road: up is the throttle, fire climbs at flying speed, down throttles back
; in the air and brakes on the ground.
;
; Assembled with -D HOVER=1 (make run-hover) it starts in the air module,
; a helicopter holding 32 pixels up across the road: shots and a grenade
; pass beneath it until it settles.
;
; Assembled with -D SKY=1 (make run-sky) it starts on the pavement with a
; helicopter on the road; getting in fetches the air module.  Buildings are
; walls to it only below their height (the tileset's heights table).

.include "b64.inc"
.include "slots.inc"
.include "../../modules/physics/physics.inc"
.include "physics_syms.inc"
.include "collision_syms.inc"

.export game_main

PCX     = 160                   ; the player's place on the playfield
.ifdef HOVER
PCY     = 124                   ; lower: the scene happens north of the player
.else
PCY     = 92
.endif
.ifdef SKY
START_X = 1300 * 32 + 16        ; the pavement south of the road at metatile row 1000,
START_Y = 1001 * 32 + 16        ; a six-storey block south of it (rows 1002-1005)
ROAD_Y  = 1000 * 32 + 16
.elseif .defined(PLANE)
START_X = 1300 * 32 + 16        ; the pavement south of the road at metatile row 1000,
START_Y = 1001 * 32 + 16        ; which runs east long enough to take off from
ROAD_Y  = 1000 * 32 + 16
.elseif .defined(HOVER)
START_X = 1300 * 32 + 16        ; the pavement south of the road at metatile row 1000;
START_Y = 1001 * 32 + 16        ; the helicopter lifts off the pavement across it
HELI_Y  = 999 * 32 + 24
HOVER_Z = 32                    ; the height it holds, pixels
HOVER_UNTIL = 330               ; the tick it lets go and settles
.elseif .defined(MARSH)
START_X = 1700 * 32 + 16        ; the sand at the north edge of the marsh (metatile rows
START_Y = 1038 * 32 + 16        ; 1040-1087, from the sand to column 1711 in the sea)
SEA_X   = 1716 * 32             ; deep water, east of the marsh
.elseif .defined(COAST)
START_X = 1700 * 32 + 16        ; the beach where the road at metatile row 1000 meets the sea
START_Y = 1000 * 32 + 16
SHORE   = 1704 * 32             ; the first pixel of water, all the way down the coast
.else
START_X = 1300 * 32 + 16        ; the pavement south of the road at metatile row 1000
START_Y = 1001 * 32 + 16
LANE_E  = 1000 * 32 + 24        ; the road's eastbound lane
LANE_W  = 1000 * 32 + 8
.endif

.segment "GAMETOP"
player:  .res 1                 ; the body the stick drives
driving: .res 1                 ; 1 in a car
joy:     .res 1
joywas:  .res 1
tick:    .res 2
ped_t:   .res PHYS_NB           ; per pedestrian: frames until it picks a new way
ped_in:  .res PHYS_NB
crash_t: .res 1                 ; the player's car's impact at the last step (DEBRIS)
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
.ifdef DEBRIS
        lda #6                  ; a blast throws out six pieces
        sta db_blast
.endif
        jsr PHYS_INIT
        lda #<SLOT_WORLD
        sta phys_world
        lda #>SLOT_WORLD
        sta phys_world+1
        lda #^SLOT_WORLD
        sta phys_world+2
        lda #<SLOT_TILESET0     ; the tileset, for the air module's heights
        sta phys_tiles
        lda #>SLOT_TILESET0
        sta phys_tiles+1
        lda #^SLOT_TILESET0
        sta phys_tiles+2
        lda #0                  ; the ground module is in (fetched above)
        sta module
.ifdef HOVER
        lda #2                  ; this scene starts in the air module
        jsr use_module
.endif
.ifdef MARSH
        lda #1                  ; this scene starts in the water module: the
        jsr use_module          ; speedboat at sea moves from the first frame
.endif
        lda #$5D
        sta rnd
        lda #0
        sta tick
        sta tick+1
        sta driving
        sta crash_t
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
        jsr PHYS_ADD
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
        jsr hud_show
        lda #<frame
        ldx #>frame
        jsr b64_set_callback
        jmp b64_run

.ifdef SKY
; the starting bodies: the player on the pavement, a helicopter on the road
; beside it, a car parked along the road, two walkers
start_mov: .byte M_FOOT, M_AIR, M_WHEELS, M_FOOT, M_FOOT, 0
start_cls: .byte C_WALKER, C_HELI, C_SEDAN, C_WALKER, C_WALKER
start_xl:  .byte <START_X, <(START_X + 40), <(START_X - 70), <(START_X - 40), <(START_X + 90)
start_xh:  .byte >START_X, >(START_X + 40), >(START_X - 70), >(START_X - 40), >(START_X + 90)
start_yl:  .byte <START_Y, <ROAD_Y, <(ROAD_Y + 8), <START_Y, <START_Y
start_yh:  .byte >START_Y, >ROAD_Y, >(ROAD_Y + 8), >START_Y, >START_Y
start_ang: .byte 0, 0, 0, 0, 0
start_col: .byte 13, 14, 2, 4, 3
.elseif .defined(PLANE)
; the starting bodies: the player on the pavement, a plane on the road facing
; east, two walkers
start_mov: .byte M_FOOT, M_PLANE, M_FOOT, M_FOOT, 0
start_cls: .byte C_WALKER, C_PLANE, C_WALKER, C_WALKER
start_xl:  .byte <START_X, <(START_X + 40), <(START_X - 60), <(START_X - 90)
start_xh:  .byte >START_X, >(START_X + 40), >(START_X - 60), >(START_X - 90)
start_yl:  .byte <START_Y, <ROAD_Y, <START_Y, <START_Y
start_yh:  .byte >START_Y, >ROAD_Y, >START_Y, >START_Y
start_ang: .byte 0, 0, 0, 0
start_col: .byte 13, 7, 4, 3
.elseif .defined(HOVER)
; the starting bodies: the player, a helicopter across the road, which holds
; 32 pixels up and then settles, and a car parked along the road
start_mov: .byte M_FOOT, M_AIR, M_WHEELS, 0
start_cls: .byte C_WALKER, C_HELI, C_SEDAN
start_xl:  .byte <START_X, <START_X, <(START_X + 90)
start_xh:  .byte >START_X, >START_X, >(START_X + 90)
start_yl:  .byte <START_Y, <HELI_Y, <(1000 * 32 + 24)
start_yh:  .byte >START_Y, >HELI_Y, >(1000 * 32 + 24)
start_ang: .byte 0, 0, 0
start_col: .byte 13, 14, 2
.elseif .defined(MARSH)
; the starting bodies: the player on the sand, an airboat on the reeds south
; of it, and a speedboat at sea that heads west into the marsh (captains)
start_mov: .byte M_FOOT, M_AIRBOAT, M_HULL, 0
start_cls: .byte C_WALKER, C_AIRBOAT, C_SPEEDBOAT
start_xl:  .byte <START_X, <START_X, <SEA_X
start_xh:  .byte >START_X, >START_X, >SEA_X
start_yl:  .byte <START_Y, <(1040 * 32 + 8), <(1050 * 32 + 16)
start_yh:  .byte >START_Y, >(1040 * 32 + 8), >(1050 * 32 + 16)
start_ang: .byte 0, 64, 128
start_col: .byte 13, 12, 1
.elseif .defined(COAST)
; the starting bodies: the player on the beach, a speedboat moored at the
; water's edge, a launch and a jet ski at sea, a car on the sand, two walkers
start_mov: .byte M_FOOT, M_HULL, M_HULL, M_HULL, M_WHEELS, M_FOOT, M_FOOT, 0
start_cls: .byte C_WALKER, C_SPEEDBOAT, C_LAUNCH, C_JETSKI, C_SEDAN, C_WALKER, C_WALKER
start_xl:  .byte <START_X, <(SHORE + 8), <(SHORE + 130), <(SHORE + 90), <(START_X - 80), <(START_X - 40), <(START_X - 60)
start_xh:  .byte >START_X, >(SHORE + 8), >(SHORE + 130), >(SHORE + 90), >(START_X - 80), >(START_X - 40), >(START_X - 60)
start_yl:  .byte <START_Y, <START_Y, <(START_Y - 6), <(START_Y + 60), <(START_Y + 30), <(START_Y - 40), <(START_Y + 40)
start_yh:  .byte >START_Y, >START_Y, >(START_Y - 6), >(START_Y + 60), >(START_Y + 30), >(START_Y - 40), >(START_Y + 40)
start_ang: .byte 0, 0, 64, 0, 192, 0, 0
start_col: .byte 13, 1, 7, 10, 2, 4, 3
.else
; the starting bodies: the player, four parked vehicles, four walkers
start_mov: .byte M_FOOT, M_WHEELS, M_WHEELS, M_WHEELS, M_WHEELS, M_FOOT, M_FOOT, M_FOOT, M_FOOT, 0
start_cls: .byte C_WALKER, C_SEDAN, C_SPORTS, C_TRUCK, C_BIKE, C_WALKER, C_WALKER, C_WALKER, C_WALKER
start_xl:  .byte <START_X, <(START_X - 14), <(START_X + 60), <(START_X + 130), <(START_X - 70), <(START_X + 70), <(START_X + 140), <(START_X - 90), <(START_X + 20)
start_xh:  .byte >START_X, >(START_X - 14), >(START_X + 60), >(START_X + 130), >(START_X - 70), >(START_X + 70), >(START_X + 140), >(START_X - 90), >(START_X + 20)
start_yl:  .byte <START_Y, <LANE_E, <LANE_E, <LANE_E, <LANE_W, <START_Y, <START_Y, <START_Y, <(START_Y - 64)
start_yh:  .byte >START_Y, >LANE_E, >LANE_E, >LANE_E, >LANE_W, >START_Y, >START_Y, >START_Y, >(START_Y - 64)
start_ang: .byte 0, 0, 0, 0, 128, 0, 0, 0, 0
start_col: .byte 13, 2, 7, 15, 14, 4, 6, 3, 8
.endif

; ---------------------------------------------------------------------------
frame:
        inc tick
        bne :+
        inc tick+1
:       jsr input
        jsr control
        jsr walkers
.ifdef HOVER
        jsr pilots
.endif
.ifdef MARSH
        jsr captains
.endif
        jsr PHYS_STEP
after_step:
.ifdef DEBRIS
        jsr crashes
.endif
        jsr shot_step
after_shots:
        jsr follow
        jsr submit
        lda tick                ; the status row: made on one frame, shown on
        and #7                  ; another, so the two costs never share one
        bne :+
        jmp hud_update
:       cmp #4
        bne :+
        jmp hud_show
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
        lda pb_mov,x            ; (in an aircraft fire is the climb: a tap with
        cmp #M_AIR              ; the stick pulled down gets out)
        beq @air
        cmp #M_PLANE
        bne :+
@air:   lda joy
        and #IN_DOWN
        beq @drive
:
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
; col_near), if it is a car, a boat or an aircraft; C=1 if in.  A boat
; brings in the water module, an aircraft the air module.
get_in:
        lda #22
        jsr col_near
        bcc @no
        lda pb_mov,y
        cmp #M_WHEELS
        beq :+
        cmp #M_HULL
        beq :+
        cmp #M_AIR
        beq :+
        cmp #M_PLANE
        beq :+
        cmp #M_AIRBOAT
        bne @no
:       sty camdx+1             ; in: the walker goes, the vehicle is the player's
        jsr PHYS_REMOVE
        ldx camdx+1
        stx player
        lda #0
        sta pb_in,x
        lda #1
        sta driving
        lda colour,x
        sta VIC_SPR0_COLOR
        ldy pb_mov,x            ; a boat brings the water module, an aircraft the air
        lda mod_of,y
        jsr use_module
        ldx player
        sec
        rts
@no:    ldx player
        clc
        rts
mod_of: .byte 0, 0, 0, 1, 2, 0, 2, 1    ; the module a mover needs: none, foot, wheels, hull, heli, thrown, plane, airboat

; use_module: A = 0 ground, 1 water, 2 air -> that physics module at $6000,
; unless it is there already.  The body tables above it stay as they are;
; the module then takes up every body's map cache in its own form.
use_module:
        cmp module
        beq in_place
        sta module
        tay
        lda mod_l,y
        sta b64_reu
        lda mod_m,y
        sta b64_reu+1
        lda mod_h,y
        sta b64_reu+2
        B64_SET16 b64_ptr, PHYS_BASE
        B64_SET16 b64_len, PHYS_SIZE
        jsr b64_fetch
swapped:
        jmp PHYS_RESUME
in_place:
        rts
mod_l:  .byte <SLOT_PHYSICS, <SLOT_WATER, <SLOT_AIR
mod_m:  .byte >SLOT_PHYSICS, >SLOT_WATER, >SLOT_AIR
mod_h:  .byte ^SLOT_PHYSICS, ^SLOT_WATER, ^SLOT_AIR

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

; get_out: a walker 18 pixels south of the vehicle, or else west, north or
; east, wherever its box is first clear of walls and water; none clear, the
; player stays aboard, as in an aircraft off the ground.  The vehicle
; coasts; leaving a boat or an aircraft brings the ground module back.
get_out:
        stx camdx+1
        lda pb_zh,x             ; an aircraft only once it is down on the ground
        beq :+
        rts
:       lda #3
        sta out_k
@try:   ldx camdx+1
        ldy out_k
        lda pb_xl,x
        clc
        adc out_dx,y
        sta phys_x
        lda pb_xh,x
        adc out_dxh,y
        sta phys_x+1
        lda pb_yl,x
        clc
        adc out_dy,y
        sta phys_y
        lda pb_yh,x
        adc out_dyh,y
        sta phys_y+1
        jsr land
        bcs @out
        dec out_k
        bpl @try
        ldx camdx+1
        rts
@out:   ldy out_k
        lda out_a,y
        sta phys_a
        ldx camdx+1
        lda #0
        sta pb_in,x
        lda #M_FOOT
        ldy #C_WALKER
        jsr PHYS_ADD
        bcc @no
        stx player
        lda #13
        sta colour,x
        sta VIC_SPR0_COLOR
        lda #0
        sta driving
        ldx camdx+1
        lda pb_mov,x
        cmp #M_HULL
        bcc @no
        lda #0                  ; off a boat or out of an aircraft: the ground module
        jsr use_module
@no:    ldx player
        rts
; the places tried, last first: east, north, west, south
out_dx:  .byte 18, 0, <-18, 0
out_dxh: .byte 0, 0, $FF, 0
out_dy:  .byte 0, <-18, 0, 18
out_dyh: .byte 0, $FF, 0, 0
out_a:   .byte 0, 192, 128, 64

; land: phys_x/y -> C=1 if a walker's box there (3 pixels each way) is
; clear of walls and water, from the collision module's col_tile
land:
        lda #3
        sta land_k
@c:     ldy land_k
        lda phys_x
        clc
        adc land_dx,y
        sta col_x0
        lda phys_x+1
        adc land_dxh,y
        sta col_x0+1
        lda phys_y
        clc
        adc land_dy,y
        sta col_y0
        lda phys_y+1
        adc land_dyh,y
        sta col_y0+1
        jsr col_tile
        and #P_SOLID | P_WATER
        bne @no
        dec land_k
        bpl @c
        sec
        rts
@no:    clc
        rts
land_dx:  .byte <-3, 3, <-3, 3
land_dxh: .byte $FF, 0, $FF, 0
land_dy:  .byte <-3, <-3, 3, 3
land_dyh: .byte $FF, $FF, 0, 0

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

.ifdef MARSH
; captains: every boat but the player's holds the throttle, the way it
; points (the speedboat west into the marsh, which it cannot cross)
captains:
        ldx #PHYS_NB-1
@c:     cpx player
        beq @n
        lda pb_mov,x
        cmp #M_HULL
        bne @n
        lda #IN_UP
        sta pb_in,x
@n:     dex
        bpl @c
        rts
.endif

.ifdef HOVER
; pilots: every helicopter but the player's holds HOVER_Z, climbing when
; under it and settling when over, until HOVER_UNTIL; then it settles
pilots:
        ldx #PHYS_NB-1
@p:     cpx player
        beq @n
        lda pb_mov,x
        cmp #M_AIR
        bne @n
        lda #0
        ldy tick+1
        cpy #>HOVER_UNTIL
        bcc :+
        bne @set
        ldy tick
        cpy #<HOVER_UNTIL
        bcs @set
:       ldy pb_zh,x
        cpy #HOVER_Z
        bcs @set
        lda #IN_FIRE
@set:   sta pb_in,x
@n:     dex
        bpl @p
        rts
.endif

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
        lda pb_agl,x            ; raised by half its height over what is under it
        lsr a
        sta camdx
        lda pb_yl,x
        sec
        sbc b64_cam_y
        clc
        adc #40
        sec
        sbc camdx
        sta VIC_SPR0_Y
        jsr submit_shadow
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
        jsr submit_debris
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

; submit_debris: each piece of debris, raised by half its height, in two
; greys; all in one slot (one frame)
submit_debris:
        lda db_live             ; none: nothing to draw
        bne :+
        rts
:       ldx #ND-1
@d:     lda db_t,x
        beq @n
        stx sb_x
        lda db_xl,x
        sta shx
        lda db_xh,x
        sta shx+1
        lda db_zh,x
        lsr a
        sta sb_z
        lda db_yl,x
        sec
        sbc sb_z
        sta shy
        lda db_yh,x
        sbc #0
        sta shy+1
        lda #42
        sta b64_spr_slot
        txa
        and #1
        clc
        adc #11                 ; dark grey, grey
        jsr submit_dot
        ldx sb_x
@n:     dex
        bpl @d
        rts

.ifdef DEBRIS
; crashes: the player's car hit hard this step (an impact of 16: a pixel a
; frame of change, in 16ths; the tape's rams measure 16 to 22), when the
; step before was not, throws out three pieces of debris: once a crash,
; however long it goes on pushing.  After the physics step and before the
; collision step, so a blast's mark is not one.  (Every crash in the tape
; is the player's; a game would look at every car, at a cost every frame.)
crashes:
        ldx player
        lda pb_mov,x
        cmp #M_WHEELS
        bne @no
        lda pb_hit,x
        ldy crash_t             ; the last step's
        sta crash_t
        cmp #16
        bcc @done
        cpy #16
        bcs @done
        lda pb_xl,x
        sta col_x0
        lda pb_xh,x
        sta col_x0+1
        lda pb_yl,x
        sta col_y0
        lda pb_yh,x
        sta col_y0+1
        lda #3
        ldy #1
        jmp debris_burst
@no:    lda #0
        sta crash_t
@done:  rts
.endif

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

shadow_base: .faraddr SLOT_HELISH16, SLOT_PLANESH16

; submit_frame: shx/shy (world), A = colour, sh_frame = a multicolour frame,
; b64_spr_slot -> that frame there
submit_frame:
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
        lda sh_frame
        sta b64_reu
        lda sh_frame+1
        sta b64_reu+1
        lda sh_frame+2
        sta b64_reu+2
        lda #B64_SPR_FLAG_MC
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
@xok:   lda pb_yl,x             ; sprite y = y - camera y + 40, less half its height
        sec
        sbc b64_cam_y
        sta camdx
        lda pb_yh,x
        sbc b64_cam_y+1
        bne sb_out
        lda pb_agl,x
        lsr a
        sta sb_z
        lda camdx
        clc
        adc #40
        bcs sb_out
        sec
        sbc sb_z
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
        ldx camdx
        jmp submit_shadow
sb_out: rts

; submit_shadow: X = body.  An aircraft in the air: its outline in black
; where it would stand (roofs are drawn at ground level, so over a roof too)
submit_shadow:
        lda pb_agl,x            ; on the ground (every body but an aircraft): none
        beq sb_out
        ldy #0
        lda pb_mov,x
        cmp #M_AIR
        beq :+
        ldy #3
        cmp #M_PLANE
        bne sb_out
:       sty veh_k
        lda pb_xl,x
        sta shx
        lda pb_xh,x
        sta shx+1
        lda pb_yl,x
        sta shy
        lda pb_yh,x
        sta shy+1
        lda pb_ang,x            ; its heading's frame of the shadow set
        clc
        adc #8
        lsr
        lsr
        lsr
        lsr
        ldy #0
        sty b64_reu+1
        lsr
        ror b64_reu+1
        lsr
        ror b64_reu+1
        sta b64_reu+2
        ldy veh_k
        lda b64_reu+1
        clc
        adc shadow_base,y
        sta sh_frame
        lda b64_reu+2
        adc shadow_base+1,y
        sta sh_frame+1
        lda shadow_base+2,y
        adc #0
        sta sh_frame+2
        txa                     ; slots 30-41, one a body
        clc
        adc #30
        sta b64_spr_slot
        lda #0
        jmp submit_frame

; frame_of: X = body -> b64_reu = its sprite frame: a car or a boat at one
; of 16 headings, a walker in one of two steps
frame_of:
        lda pb_mov,x
        cmp #M_FOOT             ; the commonest first
        beq @foot
        ldy #0
        cmp #M_WHEELS
        beq @veh
        ldy #3
        cmp #M_HULL
        beq @veh
        ldy #6
        cmp #M_AIR
        beq @veh
        ldy #9
        cmp #M_PLANE
        beq @veh
        ldy #12
        cmp #M_AIRBOAT
        bne @foot
@veh:   sty veh_k
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
        ldy veh_k
        lda b64_reu+1
        clc
        adc veh_base,y
        sta b64_reu
        lda b64_reu+2
        adc veh_base+1,y
        sta b64_reu+1
        lda veh_base+2,y
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
veh_base: .faraddr SLOT_CARS16, SLOT_BOATS16, SLOT_HELI16, SLOT_PLANE16, SLOT_AIRBOAT16

; ---------------------------------------------------------------------------
; hud_update: what the player is doing, into hudbuf
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
        beq @foot
        sta hudbuf,y
        iny
        bne :-
@foot:  jmp @show
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
        lda pb_mov,x            ; an aircraft: its height too, in pixels
        cmp #M_AIR
        beq :+
        cmp #M_PLANE
        bne @dmg
:       lda pb_zh,x
        jsr put_dec3
        ldy #3
:       lda txt_alt,y
        sta hudbuf+33,y
        dey
        bpl :-
        lda hudbuf+29
        sta hudbuf+37
        lda hudbuf+30
        sta hudbuf+38
        lda hudbuf+31
        sta hudbuf+39
@dmg:   lda pb_dmg,x
        jsr put_dec3
        lda pb_st,x
        and #ST_SKID
        beq @show
        lda pb_mov,x            ; a car skids; a boat throws up spray
        cmp #M_HULL
        beq @spray
        cmp #M_AIRBOAT
        beq @spray
        ldy #3
:       lda txt_skid,y
        sta hudbuf+35,y
        dey
        bpl :-
        bmi @show
@spray: ldy #4
:       lda txt_spray,y
        sta hudbuf+35,y
        dey
        bpl :-
@show:  rts

; hud_show: the status row as hud_update last made it
hud_show:
        B64_SET16 b64_val, hudbuf
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
txt_alt:   .byte "ALT "
txt_spray: .byte "SPRAY"
cls_names: .byte "SEDAN", 0, "SPORTS", 0, "TRUCK", 0, "BIKE", 0, "SPEEDBOAT", 0, "LAUNCH", 0, "JET SKI", 0
           .byte "HELICOPTER", 0, "PLANE", 0, "AIRBOAT", 0
cls_off:   .byte 0, 0, 6, 13, 19, 24, 34, 41, 49, 60, 66
tenths:    .byte "0112334456678899"

; ---------------------------------------------------------------------------
; the tape (AUTODRIVE): frames, then the stick
.ifdef AUTODRIVE
.ifdef PLANE
; walk to the plane and get in (the air module comes in); the throttle along
; the road; at flying speed, climb over the blocks and turn a full circle;
; back on the road's line, throttle back and sink onto it; brake; get out
; (the ground module comes back) and walk
tape_len:  .byte 40, 30, 1, 1, 110, 100, 30, 128, 30, 140, 110, 1, 1, 40, 60, 0
tape_joy:  .byte 0, IN_UP | IN_RIGHT, IN_FIRE, 0, IN_UP, IN_UP | IN_FIRE, IN_UP, IN_UP | IN_RIGHT, IN_UP, IN_DOWN
           .byte IN_DOWN, IN_DOWN | IN_FIRE, 0, IN_LEFT, 0
.elseif .defined(HOVER)
; wait for the helicopter to lift; face north, three shots at it, which pass
; beneath; a grenade under it, whose blast does not reach it; wait for it to
; settle on the pavement; three shots, which hit it
tape_len:  .byte 60, 2, 10, 1, 20, 1, 20, 1, 30, 1, 100, 180, 1, 20, 1, 20, 1, 60, 0
tape_joy:  .byte 0, IN_UP, 0, IN_UP | IN_FIRE, 0, IN_UP | IN_FIRE, 0, IN_UP | IN_FIRE, 0, IN_FIRE, 0, 0
           .byte IN_UP | IN_FIRE, 0, IN_UP | IN_FIRE, 0, IN_UP | IN_FIRE, 0
.elseif .defined(SKY)
; walk to the helicopter and get in (the air module comes in); climb, fly
; south over the block and brake; settle onto its roof; climb again, fly
; back north to the road and settle on it; get out (the ground module comes
; back) and walk
tape_len:  .byte 40, 30, 1, 1, 70, 20, 20, 12, 110, 30, 40, 14, 170, 1, 1, 40, 60, 0
tape_joy:  .byte 0, IN_UP | IN_RIGHT, IN_FIRE, 0, IN_FIRE, IN_DOWN | IN_FIRE, IN_DOWN, IN_UP, 0, IN_FIRE
           .byte IN_UP, IN_DOWN, 0, IN_DOWN | IN_FIRE, 0, IN_LEFT, 0
.elseif .defined(DEBRIS)
; the city's start: get into the sedan and drive into the parked cars, each
; crash throwing out debris; back off and get out; walk west, out of reach of
; the cars (a tap beside one gets in), turn east and toss a grenade at the
; wrecks, whose blast throws out more
tape_len:  .byte 40, 6, 1, 1, 100, 30, 40, 50, 1, 1, 25, 2, 5, 1, 150, 0
tape_joy:  .byte 0, IN_UP, IN_UP | IN_FIRE, 0, IN_UP, 0, IN_DOWN, 0, IN_FIRE, 0, IN_LEFT, IN_RIGHT, 0, IN_FIRE, 0
.elseif .defined(MARSH)
; walk south to the airboat and get in; the throttle south through the
; reeds; a quarter turn east, sliding wide, and on out of the marsh into the
; sea, past the speedboat pinned at its edge
tape_len:  .byte 30, 40, 1, 1, 100, 20, 110, 80, 0
tape_joy:  .byte 0, IN_DOWN, IN_FIRE, 0, IN_UP, IN_UP | IN_LEFT, IN_UP, 0
.elseif .defined(COAST)
; walk east to the water's edge and get into the speedboat (the water module
; comes in); out to sea and into the launch; turn away on the propeller's
; wash; turn south-west, sliding wide, and run into the beach; drift to a
; stop against it, get out onto the sand (the ground module comes back) and
; walk up the beach
tape_len:  .byte 40, 104, 1, 1, 110, 40, 40, 25, 80, 60, 1, 1, 60, 100, 0
tape_joy:  .byte 0, IN_RIGHT, IN_FIRE, 0, IN_UP, IN_UP | IN_RIGHT, IN_UP, IN_UP | IN_RIGHT, IN_UP, 0
           .byte IN_FIRE, 0, IN_LEFT, 0
.else
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
.endif

.segment "GAMETOP"
shx:    .res 2
shy:    .res 2
tapped: .res 1
sb_x:   .res 1
ring_r: .res 1
module: .res 1                  ; the physics module at $6000: 0 ground, 1 water
out_k:  .res 1
land_k: .res 1
veh_k:  .res 1
sb_z:   .res 1
sh_frame: .res 3
