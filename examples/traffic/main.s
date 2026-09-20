; backlot-64 example: traffic in Bellamar, for Priors-64.
;
; The player's car (hardware sprite 0, pinned: it never flickers) drives the
; city's road grid among up to 24 traffic cars on the multiplexer.  Every
; car keeps to its lane, turns at crossings at its new lane's line, stops at
; the lights, queues behind the car ahead, and keeps out of a crossing whose
; exit is jammed.  The roads are read from the world map's tile property
; bits (P_ROAD_*), one byte from the REU as a car nears each metatile, so
; the same code drives on any map whose road metatiles keep two lanes at 8
; and 24 pixels in.  This is the first cut of the path/road module
; (docs/PLAN.md 4.3) and lives in the example until the entity system does
; (roadmap step 14).
;
; The rule it keeps: a raster line shows at most eight sprites, and the
; player's car is always one of them, so traffic may put at most seven on
; any line.  The screen's world lines are counted in bands of 8, every live
; car (on screen or in the margin around it) holding the bands its 21-line
; sprite covers.  A car does not spawn into a full band, and a car moving up
; or down the screen waits before it enters one; cars driving east or west
; never change bands.  So an east-west street carries at most seven moving
; cars besides the player, and a north-south street is limited only by its
; length.  The HUD shows the busiest band and how many sprites the
; multiplexer has ever had to drop (the aim is none).
;
; Joystick 2: at a crossing, hold a direction to turn that way; pull
; against the car to brake; fire changes the traffic density (8, 16, 24).
; Without input for ten seconds the car drives itself like the traffic,
; obeying the lights and turning only right.
; Assemble with -D AUTODRIVE=1 to drive itself always (the check does).

.include "b64.inc"
.include "slots.inc"

.export game_main
.import spr_rejected

.assert SLOT_WORLD = 0, error, "mt_fetch assumes the world map starts the REU"

NCARS   = 24                    ; the traffic pool: the stock tier's sprite limit
PL      = NCARS                 ; the player's index in the car arrays
NC      = NCARS + 1
MARGIN  = 64                    ; cars live this far beyond the screen's edges
PCX     = 160                   ; the player's centre on the playfield
PCY     = 92
BAND_MAX = 7                    ; sprites traffic may put on a line
.ifndef EXT
EXT     = 17                    ; lines a car holds below its sprite: the multiplexer's lead
.endif                          ; (5 at 1 MHz) and 2 a sprite for a row of 7 on one line
BOT     = 11 + EXT              ; the last line a car holds, from its centre
G_AHEAD = 22                    ; the gap a car keeps in front: 6, and 16 frames of creep
G_BOX   = 60                    ; from a stop line: the crossing and 28 pixels beyond it
G_PLAYER = 18                   ; the player checks every 4 frames, closing at up to 3 a frame by hand
G_SPAWN = 16                    ; room around a new car
IDLE_AUTO = 500                 ; frames without input before the car drives itself

H_N     = 0
H_E     = 1
H_S     = 2
H_W     = 3
EX_NONE = $FF                   ; no turn pending
C_BLOCK = $01                   ; something is close ahead
C_WAIT  = $02                   ; held at a stop line
C_INX   = $04                   ; inside the crossing where it turns
C_PLAN  = $08                   ; just spawned: the way ahead is still to be read

.if .defined(STREET)            ; the band district, drawn to the reference image
START_X = 1220 * 32 + 16        ; on the road, the shopfronts above and the roofs below
START_Y = 1203 * 32 + 16
.elseif .defined(CITYENC)       ; the encoded district: the reference image itself
START_X = 1520 * 32 + 16
START_Y = 1203 * 32 + 16
.else
START_X = 1300 * 32 + 16        ; on the road at metatile row 1000, eastbound lane
START_Y = 1000 * 32 + 24
.endif

; zero page: the game's range
zt      = $70                   ; 8 bytes: metatile coordinates, temporaries
rnd     = $78                   ; 2
jy      = $7A                   ; the stick this frame (0 when the car drives itself)
pdx     = $7B                   ; the player's movement this frame
pdy     = $7C
ca_self = $60                   ; check_ahead
ca_reach = $61
ca_xl   = $62
ca_xh   = $63
ca_yl   = $64
ca_yh   = $65
ca_t    = $66                   ; the gap asked for
ca_d    = $67                   ; 2: a difference
ca_k    = $69
ca_hl   = $6A                   ; my half length along, half width across
ca_ha   = $6B
ca_pl   = $6C                   ; a crossing car's
ca_pa   = $6D
lim_t   = $58                   ; 2 each, parallel then crossing: across limit,
lim_l   = $5A                   ; along offset, along range
lim_h   = $5C
lim_2t  = $5E
ca_body = $6E                   ; 1 in check_body

.segment "GAMEHI"
c_xl:   .res NC                 ; the car's centre in world pixels
c_xh:   .res NC
c_yl:   .res NC
c_yh:   .res NC
c_hd:   .res NC                 ; heading 0-3 (N E S W), $FF = a free slot
c_nx:   .res NC                 ; property bits of the metatile ahead
c_ex:   .res NC                 ; the heading it turns to in the crossing ahead, or EX_NONE
c_tp:   .res NC                 ; where it turns: the travel position of its new lane
c_st:   .res NC                 ; C_* bits
c_col:  .res NC
c_run:  .res NC                 ; pixels it can move before car_step looks again
band:   .res 64                 ; cars holding each 8-line band of world y (mod 512)
tick:   .res 2
want:   .res 1                  ; the density: how many cars the spawner keeps alive
live:   .res 1
shown:  .res 1
busiest: .res 1
dropped: .res 2                 ; entries the multiplexer dropped, summed over frames
fbyte:  .res 1
p_cur:  .res 1                  ; property bits of the player's metatile
auto:   .res 1                  ; 1 = the player's car drives itself
idle:   .res 2
firewas: .res 1
cand:   .res 3                  ; choose_exit's candidates
cix:    .res 1
sp_x:   .res 2                  ; spawn_try's input
sp_y:   .res 2
sp_h:   .res 1
rx0:    .res 2                  ; the live region: screen plus margin, world pixels
rx1:    .res 2
ry0:    .res 2
ry1:    .res 2
mx0:    .res 2                  ; the same in whole metatiles
mx1:    .res 2
my0:    .res 2
my1:    .res 2
rowbuf: .res 16
hudbuf: .res 41

.segment "GAME"
game_main:
        jsr b64_init
.if .defined(STREET)
        B64_SET24 b64_reu, SLOT_TILESETBD
.elseif .defined(CITYENC)
        B64_SET24 b64_reu, SLOT_TILESETIM
.else
        B64_SET24 b64_reu, SLOT_TILESET0
.endif
        jsr b64_load_tileset
.if .defined(STREET) .or .defined(CITYENC)
        lda #0                  ; the band city: black, dark grey, light grey shared,
        sta VIC_BG_COLOR0       ; white the one colour a cell may add (docs/ART.md)
        lda #11
        sta VIC_BG_COLOR1
        lda #15
        sta VIC_BG_COLOR2
        lda #0
        sta VIC_BORDERCOLOR
.else
        lda #11                 ; Bellamar by day
        sta VIC_BG_COLOR0
        lda #15
        sta VIC_BG_COLOR1
        lda #1
        sta VIC_BG_COLOR2
        lda #11
        sta VIC_BORDERCOLOR
.endif

        lda #$A5
        sta rnd
        lda #$3C
        sta rnd+1
        ldx #NC-1
        lda #$FF
:       sta c_hd,x
        dex
        bpl :-
        ldx #63
        lda #0
:       sta band,x
        dex
        bpl :-
        sta tick
        sta tick+1
        sta live
        sta dropped
        sta dropped+1
        sta idle
        sta idle+1
        sta firewas
        lda #1
        sta auto
        lda #NCARS
        sta want
        lda #0
        sta ca_body
        sta sp_ready
        sta joy_test

        ; the player's car
        ldx #PL
        B64_SET16 zt, START_X
        lda zt
        sta c_xl,x
        lda zt+1
        sta c_xh,x
        B64_SET16 zt, START_Y
        lda zt
        sta c_yl,x
        lda zt+1
        sta c_yh,x
        lda #H_E
        sta c_hd,x
        lda #0
        sta c_st,x
        lda #$03                ; P_ROAD_E | P_ROAD_W: it starts on a road
        sta p_cur
        jsr plan_next
        B64_SET16 b64_cam_x, START_X - PCX
        B64_SET16 b64_cam_y, START_Y - PCY
        jsr b64_redraw

        ; sprite 0: the player's car, multicolour, at the screen's centre
        lda #PCX + 12
        sta VIC_SPR0_X
        lda #PCY + 40
        sta VIC_SPR0_Y
.if .defined(STREET) .or .defined(CITYENC)
        lda #7                  ; yellow: the one car the eye should follow
.else
        lda #13                 ; light green: no traffic car has it
.endif
        sta VIC_SPR0_COLOR
        lda #1
        sta VIC_SPR_ENA
        sta VIC_SPR_MCOLOR
        lda #0                  ; tyres and windows black, lamps white
        sta VIC_SPR_MCOLOR0
        lda #1
        sta VIC_SPR_MCOLOR1

        jsr region
        jsr populate
        jsr hud_update
        jsr hud_show
        lda #<frame
        ldx #>frame
        jsr b64_set_callback
        jmp b64_run

; ---------------------------------------------------------------------------
frame:
        inc tick
        bne :+
        inc tick+1
:       jsr input
        jsr player_step
        lda pdx
        ldx pdy
        jsr b64_move_camera
        jsr region
t_traffic:
        jsr traffic_step
t_spawn:
        lda tick                ; the costly periodic work, a piece a frame: a spawn
        and #3                  ; point is found (1), the way behind it checked (3),
        cmp #1                  ; then the way ahead and the car placed (0); the HUD
        bne :+                  ; is redrawn on a frame of its own (2, every 32nd)
        jsr spawner
        jmp @work
:       cmp #3
        bne :+
        lda sp_ready
        beq @work
        jsr spawn_behind
        jmp @work
:       cmp #0
        bne @work
        lda sp_ready
        cmp #2
        bne @work
        lda #0
        sta sp_ready
        jsr spawn_try
@work:
t_submit:
        jsr submit
t_after:
        lda spr_rejected        ; what the multiplexer could not show of the last list
        clc
        adc dropped
        sta dropped
        bcc :+
        inc dropped+1
:       lda tick
        and #31
        cmp #2
        bne :+
        jsr hud_update          ; the text on one frame,
        jmp frame_end
:       cmp #6
        bne frame_end
        jsr hud_show            ; onto the row four frames later
frame_end:                      ; the check times the callback to here
        rts

; input: the stick, or nothing when the car drives itself; fire changes the density
input:
.ifdef AUTODRIVE
        lda #0
        sta jy
        rts
.else
        lda joy_test            ; the check drives by hand through this byte
        bne :+
        lda b64_joy
:       sta joy_now
        and #$10
        tax
        eor firewas
        and #$10
        beq @nofire
        stx firewas
        txa
        beq @nofire             ; released
        lda want                ; 8 -> 16 -> 24 -> 8
        clc
        adc #8
        cmp #NCARS + 1
        bcc :+
        lda #8
:       sta want
        jsr hud_update
@nofire:
        lda joy_now
        and #$0F
        beq @idle
        sta jy
        lda #0
        sta auto
        sta idle
        sta idle+1
        rts
@idle:  sta jy
        inc idle
        bne :+
        inc idle+1
:       lda idle+1
        cmp #>IDLE_AUTO
        bcc :+
        lda idle
        cmp #<IDLE_AUTO
        bcc :+
        lda #1
        sta auto
:       rts
.endif

; ---------------------------------------------------------------------------
; the player: turns by the stick in a crossing.  Driving itself it keeps
; traffic's speed, a pixel a frame; by hand it has two.
player_step:
        lda #0
        sta pdx
        sta pdy
        lda auto
        bne player_one
        jsr player_one
player_one:
        ldx #PL
        lda auto
        bne @step
        jsr manual_turn
@step:  jsr car_step
        bcc @done
        ldy c_hd,x              ; it moved: so does the camera
        lda pdx
        clc
        adc step_dx,y
        sta pdx
        lda pdy
        clc
        adc step_dy,y
        sta pdy
@done:  rts

; manual_turn: in a crossing, at the line of the lane the stick points to
manual_turn:
        lda p_cur
        and #$0F
        cmp #$0F
        bne @no
        lda jy
        beq @no
        ldy #3
@d:     lda jy
        and joybit,y
        beq @next
        tya                     ; perpendicular to the heading?
        eor c_hd,x
        and #1
        beq @next
        jsr travel_pos
        cmp lane,y
        bne @next
        sty cix
        jsr car_mt              ; is there a road that way?
        ldy cix
        jsr step_mt
        jsr mt_fetch
        ldy cix
        and dirbit,y
        beq @no
        tya
        sta c_hd,x
        lda #EX_NONE
        sta c_ex,x
        jsr plan_next
        jmp merge_hold
@next:  dey
        bpl @d
@no:    rts

; merge_hold: the player's car has just turned into a lane.  A traffic car
; close behind it there looks ahead only every 16 frames, so it is told to
; hold now; it looks again at its next check, by when the player has pulled
; away at twice its speed.
merge_hold:
        ldx #PL
        lda c_hd,x
        pha
        eor #2                  ; look behind: the same lane, the other way
        sta c_hd,x
        lda #G_AHEAD
        jsr check_ahead
        pla
        sta c_hd,x
        bcc @done
        lda c_st,y              ; Y = the car found
        ora #C_BLOCK
        sta c_st,y
@done:  rts

; ---------------------------------------------------------------------------
; traffic_step: every car one step; every 8th frame per car, a car beyond the
; live region leaves
traffic_step:
        ldx #NCARS-1
@c:     lda c_hd,x
        bmi @next
        jsr car_step
        lda c_hd,x
        bmi @next               ; it left at the end of a road
        txa
        eor tick
        and #7
        bne @next
        jsr outside
        bcc @next
        jsr despawn
@next:  dex
        bpl @c
        rts

; car_step: X = car.  One pixel along its lane unless something holds it.
; C=1 if it moved.
car_step:
        cpx #PL                 ; the player's car always takes the full step
        beq @full
        lda c_run,x             ; nothing to look at for c_run pixels: just move,
        beq @full               ; unless it is held or this is its frame to look ahead
        lda c_st,x
        and #C_BLOCK | C_WAIT
        bne @full
        txa
        eor tick
        and #15
        beq @full
        dec c_run,x
        jmp step_px
@full:  lda c_st,x              ; new from the spawner: plan the way ahead first
        and #C_PLAN
        beq @planned
        lda tick
        and #3
        cmp #2
        beq :+
        clc                     ; not yet: it waits where it spawned
        rts
:       lda c_st,x
        and #<~C_PLAN
        sta c_st,x
        jsr plan_next
        clc
        rts
@planned:
        lda c_st,x              ; the turn point, inside the crossing
        and #C_INX
        beq @go
        jsr travel_pos
        cmp c_tp,x
        bne @go
        txa                     ; at the turn point: look every 4th frame
        eor tick
        and #3
        beq :+
        clc
        rts
:       lda c_hd,x              ; turn only if the new way is clear: a left turn
        pha                     ; crosses the oncoming lane, any turn can meet a
        lda c_ex,x              ; car still crossing, and the turned body reaches
        sta c_hd,x              ; back past the centre, so all of it is checked
        lda #G_AHEAD
        jsr check_body
        pla
        bcc :+
        sta c_hd,x              ; wait at the turn point
        clc
        rts
:       lda #EX_NONE
        sta c_ex,x
        lda c_st,x
        and #<~C_INX
        sta c_st,x
        jsr plan_next
        cpx #PL
        bne @go
        jsr merge_hold
@go:    jsr may_move
        bcs :+
        rts                     ; held
:       jsr travel_pos          ; about to leave the metatile: is there road beyond?
        ldy c_hd,x
        cmp edge_at,y
        bne @move
        lda c_nx,x
        and dirbit,y
        bne @enter
        cpx #PL
        beq @held
        jmp despawn             ; traffic leaves at the end of the road
@held:  clc
        rts
@enter: lda #1                  ; this step enters the next metatile
        .byte $2C               ; (bit abs: skip the next lda)
@move:  lda #0
        sta ca_k
        tya                     ; the band governor: only moves up or down change bands
        and #1
        bne @step
        cpx #PL
        beq @step               ; sprite 0 is outside the multiplexer
        jsr band_move
        bcs @step
        rts                     ; the band ahead is full: wait
@step:  jsr step_px
        lda ca_k
        beq :+
        jsr on_enter
:       jsr set_run
        sec
        rts

; step_px: X = car, one pixel along its heading.  C=1.
step_px:
        lda c_hd,x
        beq @n
        cmp #H_S
        beq @s
        bcs @w
        inc c_xl,x              ; east
        bne @done
        inc c_xh,x
        sec
        rts
@w:     lda c_xl,x
        bne :+
        dec c_xh,x
:       dec c_xl,x
        sec
        rts
@s:     inc c_yl,x
        bne @done
        inc c_yh,x
@done:  sec
        rts
@n:     lda c_yl,x
        bne :+
        dec c_yh,x
:       dec c_yl,x
        sec
        rts

; set_run: X = car.  c_run = the pixels it can move before car_step must
; look again: to its stop line, its turn point, the metatile's edge, or (up
; and down the screen) the next band boundary of its sprite.
set_run:
        jsr travel_pos
        sta zt                  ; pos
        ldy c_hd,x
        lda fwd,y
        sta zt+1                ; 1: the position rises with each step
        bne :+
        lda zt                  ; to the edge: 31 - pos, or pos
        jmp :++
:       lda #31
        sec
        sbc zt
:       sta zt+2                ; the run so far
        lda c_st,x
        and #C_INX
        beq @stop
        lda c_tp,x              ; the turn point
        jsr run_to
        jmp @band
@stop:  lda c_nx,x              ; the stop line, with a crossing ahead
        and #$0F
        cmp #$0F
        bne @band
        lda stop_at,y
        jsr run_to
@band:  cpx #PL
        beq @done
        lda c_hd,x
        and #1
        bne @done
        lda c_hd,x              ; up or down the screen: the next band boundaries
        beq @north
        lda #<-(BOT + 1)        ; south: a band gained when (y + BOT + 1) & 7 = 0,
        sec                     ; one released when (y - 9) & 7 = 0
        sbc c_yl,x
        and #7
        jsr run_min
        lda #9
        sec
        sbc c_yl,x
        and #7
        jsr run_min
        jmp @done
@north: lda c_yl,x              ; north: gained when (y - 10) & 7 = 0, released
        sec                     ; when (y + BOT) & 7 = 0
        sbc #10
        and #7
        jsr run_min
        lda c_yl,x
        clc
        adc #BOT
        and #7
        jsr run_min
@done:  lda zt+2
        sta c_run,x
        rts

; run_to: A = a position ahead in the metatile; the run is at most the
; distance to it, if it is ahead
run_to:
        sta zt+3
        lda zt+1
        beq @down
        lda zt+3                ; rising: target - pos, if not behind
        sec
        sbc zt
        bcc run_done
        jmp run_min
@down:  lda zt                  ; falling: pos - target, if not behind
        sec
        sbc zt+3
        bcc run_done
run_min:
        cmp zt+2
        bcs run_done
        sta zt+2
run_done:
        rts

; on_enter: X = car, just into the metatile whose properties are c_nx
on_enter:
        cpx #PL
        bne :+
        lda c_nx,x
        sta p_cur
:       lda c_nx,x
        and #$0F
        cmp #$0F
        bne @plan
        lda c_ex,x
        bmi @plan               ; straight through: look past the crossing now
        lda c_st,x              ; turning here: look ahead after the turn
        ora #C_INX
        sta c_st,x
        rts
@plan:  jmp plan_next

; may_move: X = car.  C=1 if it may take its step.
may_move:
        cpx #PL
        beq @player
        txa                     ; every 16 frames: anything close ahead?
        eor tick
        and #15
        bne @nochk
        lda #G_AHEAD
        jsr check_ahead
        jsr set_block
@nochk: lda c_st,x
        and #C_BLOCK
        bne @no
        jmp stop_line
@player:
.ifndef AUTODRIVE
        lda jy                  ; the stick against the car: brake
        ldy c_hd,x
        and joyback,y
        bne @no
.endif
        lda tick
        and #3
        bne :+
        lda #G_PLAYER
        jsr check_ahead
        jsr set_block
:       lda c_st,x
        and #C_BLOCK
        bne @no
        lda auto
        beq @yes                ; by hand the lights are the player's business
        jmp stop_line
@yes:   sec
        rts
@no:    clc
        rts

set_block:
        lda c_st,x
        and #<~C_BLOCK
        bcc :+
        ora #C_BLOCK
:       sta c_st,x
        rts

; stop_line: X = car.  C=1 unless it is at a crossing's stop line and must
; wait: for its light, or for room in and beyond the crossing.  It judges on
; arriving and then every 8 frames.
stop_line:
        lda c_st,x
        and #C_INX
        bne @go
        lda c_nx,x
        and #$0F
        cmp #$0F
        bne @go
        jsr travel_pos
        ldy c_hd,x
        cmp stop_at,y
        bne @go
        lda c_st,x
        and #C_WAIT
        beq @judge
        txa
        eor tick
        and #7
        bne @no
@judge: jsr light_ok
        bcc @wait
        lda #G_BOX
        jsr check_ahead
        bcs @wait
        lda c_st,x
        and #<~C_WAIT
        sta c_st,x
@go:    sec
        rts
@wait:  lda c_st,x
        ora #C_WAIT
        sta c_st,x
@no:    clc
        rts

; light_ok: X = car at a stop line.  C=1 if its light is green.  Each
; crossing runs a 512-frame cycle: east-west green for 192 frames, all red
; for 64, north-south green for 192, all red for 64 (a car entering on the
; last green frame clears the crossing in 56); neighbouring crossings are
; half a cycle apart.
light_ok:
        jsr car_mt
        ldy c_hd,x
        jsr step_mt             ; the crossing
        lda zt
        clc
        adc zt+2
        lsr
        lsr
        lsr
        clc
        adc tick+1
        and #1                  ; 0: the first half of the cycle (east-west)
        sta zt+4
        lda c_hd,x
        and #1                  ; 1: this car drives east or west
        eor zt+4
        beq @red
        lda tick
        cmp #192
        bcs @red
        sec
        rts
@red:   clc
        rts

; check_body: as check_ahead, but from this car's rear rather than its
; centre: for a car about to take up a new heading
check_body:
        ldy #1
        sty ca_body
        jsr check_ahead
        ldy #0
        sty ca_body
        rts

; check_ahead: X = car, A = the gap it wants clear in front of it.  C=1 if
; another car's body is in that gap, or overlaps this car ahead of its
; centre.  Bodies are the car art: 24 x 6 driving east or west, 12 x 15
; driving north or south.  So a car sees one crossing its path and one
; stopped ahead in its lane, but not one waiting at another stop line or
; driving the other lane.
check_ahead:
        stx ca_self
        sta ca_t
        lda c_xl,x
        sta ca_xl
        lda c_xh,x
        sta ca_xh
        lda c_yl,x
        sta ca_yl
        lda c_yh,x
        sta ca_yh
        lda c_hd,x              ; the limits for a parallel and a crossing car
        and #1
        tay
        lda half_along,y        ; my half length along the heading
        sta ca_hl
        lda half_across,y
        sta ca_ha
        tya
        eor #1
        tay
        lda half_along,y        ; a crossing car's half length along my heading
        sta ca_pl               ; is its half across its own; and the other way
        lda half_across,y
        sta ca_pa
        ; blocked if |across| < T and -L < along < my half + gap + L, L being the
        ; other car's half extent along my heading: tested as 0 < along + L < H
        lda c_hd,x
        and #1
        tay
        lda half_across,y
        asl
        sta lim_t               ; T parallel = 2 * half across
        asl
        sta lim_2t
        lda half_along,y
        sta lim_l               ; L parallel = its half along = mine
        asl
        clc
        adc half_along,y
        clc
        adc ca_t
        sta lim_h               ; H = my half + gap + twice its half = 3 * half along + gap
        lda ca_ha               ; crossing: T = my half across + its half along mine
        clc
        adc ca_pl
        sta lim_t+1
        asl
        sta lim_2t+1
        lda ca_pa               ; L = its half across = its extent along my heading
        sta lim_l+1
        clc
        adc ca_hl
        clc
        adc ca_t
        clc
        adc ca_pa
        sta lim_h+1             ; H = L + my half + gap + its half along my heading
        lda ca_body             ; check_body: the window starts at my rear
        beq @win
        lda lim_l
        clc
        adc ca_hl
        sta lim_l
        lda lim_h
        clc
        adc ca_hl
        sta lim_h
        lda lim_l+1
        clc
        adc ca_hl
        sta lim_l+1
        lda lim_h+1
        clc
        adc ca_hl
        sta lim_h+1
@win:   lda c_hd,x
        and #1
        beq :+
        jmp ahead_h
:       jmp ahead_v

; ahead_h: east or west.  across is y, along is x.
ahead_h:
        ldy #NC-1
@j:     cpy ca_self
        beq @n
        lda c_hd,y
        bmi @n
        and #1                  ; 1 = parallel (east-west too), 0 = crossing
        eor #1
        tax                     ; X = 0 parallel, 1 crossing
        lda c_yl,y              ; the low byte first: (across + T) mod 256 in (0, 2T)
        sec
        sbc ca_yl
        clc
        adc lim_t,x
        beq @n
        cmp lim_2t,x
        bcs @n
        lda c_yl,y              ; then the whole difference: within 256
        sec
        sbc ca_yl
        lda c_yh,y
        sbc ca_yh
        beq :+
        cmp #$FF
        bne @n
:
        lda c_xl,y              ; along
        sec
        sbc ca_xl
        sta ca_d
        lda c_xh,y
        sbc ca_xh
        sta ca_d+1
        stx ca_k
        ldx ca_self
        lda c_hd,x
        ldx ca_k
        cmp #H_E
        beq :+
        lda #0                  ; west: along = -(xj - xi)
        sec
        sbc ca_d
        sta ca_d
        lda #0
        sbc ca_d+1
        sta ca_d+1
:       lda ca_d                ; along + L in (0, H)
        clc
        adc lim_l,x
        sta ca_d
        lda ca_d+1
        adc #0
        bne @n
        lda ca_d
        beq @n
        cmp lim_h,x
        bcc @hit
@n:     dey
        bpl @j
        ldx ca_self
        clc
        rts
@hit:   ldx ca_self
        sec
        rts

; ahead_v: north or south.  across is x, along is y.
ahead_v:
        ldy #NC-1
@j:     cpy ca_self
        beq @n
        lda c_hd,y
        bmi @n
        and #1                  ; 0 = parallel (north-south too), 1 = crossing
        tax
        lda c_xl,y              ; the low byte first: (across + T) mod 256 in (0, 2T)
        sec
        sbc ca_xl
        clc
        adc lim_t,x
        beq @n
        cmp lim_2t,x
        bcs @n
        lda c_xl,y              ; then the whole difference: within 256
        sec
        sbc ca_xl
        lda c_xh,y
        sbc ca_xh
        beq :+
        cmp #$FF
        bne @n
:
        lda c_yl,y
        sec
        sbc ca_yl
        sta ca_d
        lda c_yh,y
        sbc ca_yh
        sta ca_d+1
        stx ca_k
        ldx ca_self
        lda c_hd,x
        ldx ca_k
        cmp #H_S
        beq :+
        lda #0                  ; north: along = -(yj - yi)
        sec
        sbc ca_d
        sta ca_d
        lda #0
        sbc ca_d+1
        sta ca_d+1
:       lda ca_d
        clc
        adc lim_l,x
        sta ca_d
        lda ca_d+1
        adc #0
        bne @n
        lda ca_d
        beq @n
        cmp lim_h,x
        bcc @hit
@n:     dey
        bpl @j
        ldx ca_self
        clc
        rts
@hit:   ldx ca_self
        sec
        rts

; ---------------------------------------------------------------------------
; the band governor.  band_of: A = high byte, zt = low byte of a world line
; -> Y = its band (the line / 8, mod 64)
band_of:
        and #1
        beq :+
        lda #32
:       sta zt+1
        lda zt
        lsr
        lsr
        lsr
        ora zt+1
        tay
        rts

; band_move: X = car moving north or south.  C=1 if the band its sprite is
; about to reach has room; the counts follow the move.
band_move:
        lda c_hd,x
        cmp #H_S
        beq @south
        lda c_yl,x              ; north: the top line y-10 becomes y-11
        sec
        sbc #10
        and #7
        bne @n2
        lda c_yl,x
        sec
        sbc #11
        sta zt
        lda c_yh,x
        sbc #0
        jsr band_of
        lda band,y
        cmp #BAND_MAX
        bcs @full
        adc #1
        sta band,y
@n2:    lda c_yl,x              ; the bottom line y+BOT becomes one less
        clc
        adc #BOT
        sta zt
        and #7
        bne @ok
        lda c_yh,x
        adc #0
        jsr band_of
        lda band,y
        sec
        sbc #1
        sta band,y
@ok:    sec
        rts
@full:  clc
        rts
@south: lda c_yl,x              ; south: the bottom line y+BOT becomes one more
        clc
        adc #BOT + 1
        sta zt
        and #7
        bne @s2
        lda c_yh,x
        adc #0
        jsr band_of
        lda band,y
        cmp #BAND_MAX
        bcs @full
        adc #1
        sta band,y
@s2:    lda c_yl,x              ; the top line y-10 becomes y-9
        sec
        sbc #9
        and #7
        bne @ok
        lda c_yl,x
        sec
        sbc #10
        sta zt
        lda c_yh,x
        sbc #0
        jsr band_of
        lda band,y
        sec
        sbc #1
        sta band,y
        sec
        rts

; bands_range: X = car -> zt+2 = its first band, zt+3 = its last
bands_range:
        lda c_yl,x
        sec
        sbc #10
        sta zt
        lda c_yh,x
        sbc #0
        jsr band_of
        sty zt+2
        lda c_yl,x
        clc
        adc #BOT
        sta zt
        lda c_yh,x
        adc #0
        jsr band_of
        sty zt+3
        rts

; bands_fit: C=1 if every band of car X has room
bands_fit:
        jsr bands_range
        ldy zt+2
@b:     lda band,y
        cmp #BAND_MAX
        bcs @no
        cpy zt+3
        beq @yes
        iny
        tya
        and #63
        tay
        jmp @b
@yes:   sec
        rts
@no:    clc
        rts

; bands_add / bands_sub: count car X in its bands, or take it out
bands_add:
        lda #1
        bne bands_by
bands_sub:
        lda #$FF
bands_by:
        sta zt+4
        jsr bands_range
        ldy zt+2
@b:     lda band,y
        clc
        adc zt+4
        sta band,y
        cpy zt+3
        beq @done
        iny
        tya
        and #63
        tay
        jmp @b
@done:  rts

; ---------------------------------------------------------------------------
; the map.  car_mt: X = car -> zt+0/1 = its metatile x, zt+2/3 = metatile y
car_mt:
        lda c_xl,x
        sta zt
        lda c_xh,x
        sta zt+1
        lda c_yl,x
        sta zt+2
        lda c_yh,x
        sta zt+3
        ldy #5
:       lsr zt+1
        ror zt
        lsr zt+3
        ror zt+2
        dey
        bne :-
        rts

; step_mt: Y = heading; the metatile coordinates in zt move one that way
step_mt:
        lda zt
        clc
        adc step_dx,y
        sta zt
        lda zt+1
        adc step_dxh,y
        sta zt+1
        lda zt+2
        clc
        adc step_dy,y
        sta zt+2
        lda zt+3
        adc step_dyh,y
        sta zt+3
        rts

; mt_fetch: the metatile at zt -> A = its property bits.  One byte of DMA:
; the map is (y << 11) | x, a byte per metatile.
mt_fetch:
        jsr mt_addr
        B64_SET16 b64_ptr, fbyte
        B64_SET16 b64_len, 1
        jsr b64_fetch
        ldy fbyte
        lda B64_PROPS,y
        rts

; plan_next: X = car.  The properties of the metatile ahead; if it is a
; crossing, the way out.
plan_next:
        jsr car_mt
        ldy c_hd,x
        jsr step_mt
        jsr mt_fetch
        sta c_nx,x
        lda #EX_NONE
        sta c_ex,x
        lda c_nx,x
        and #$0F
        cmp #$0F
        bne @done
        jmp choose_exit
@done:  rts

; choose_exit: X = car, zt = the crossing ahead.  Every car driving itself
; goes straight or turns right, the player's too: a right turn crosses no
; other lane, and a left turn waiting in the crossing sits across the lane
; the cars turning right from the other side want (they block each other
; for ever).  The ways are tried in a random order until one has road beyond
; the crossing.  By hand, the player turns either way with the stick instead
; (manual_turn), and can let go to drive on.
choose_exit:
        lda zt
        sta xc
        lda zt+1
        sta xc+1
        lda zt+2
        sta xc+2
        lda zt+3
        sta xc+3
        ldy #0
        sty cix
        cpx #PL
        bne :+
        lda auto
        bne :+
        rts                     ; by hand: c_ex stays EX_NONE
:       jsr rng
        cmp #80                 ; about a third turn right
        bcs @straight
        jsr cand_right
        jsr cand_ahead
        jmp @end
@straight:
        jsr cand_ahead
        jsr cand_right
@end:   lda #$FF
        sta cand+2
        jmp try_exits

; the candidate lists: each appends a heading to cand at cix
cand_ahead:
        lda c_hd,x
        jmp cand_put
cand_right:
        lda c_hd,x
        clc
        adc #1
        and #3
cand_put:
        ldy cix
        sta cand,y
        iny
        sty cix
        rts

; try_exits: X = car, xc = the crossing.  The first candidate with road
; beyond the crossing; straight on leaves c_ex at EX_NONE.
try_exits:
        lda #0
        sta cix
@t:     ldy cix
        cpy #3
        bcs @none
        lda cand,y
        bmi @none
        sta cur_c
        lda xc
        sta zt
        lda xc+1
        sta zt+1
        lda xc+2
        sta zt+2
        lda xc+3
        sta zt+3
        ldy cur_c
        jsr step_mt
        jsr mt_fetch
        ldy cur_c
        and dirbit,y
        bne @ok
        inc cix
        jmp @t
@ok:    tya
        cmp c_hd,x
        beq @none               ; straight on: no turn
        sta c_ex,x
        lda lane,y
        sta c_tp,x
@none:  rts

; ---------------------------------------------------------------------------
; the population.  despawn: X = car leaves
despawn:
        jsr bands_sub
        lda #$FF
        sta c_hd,x
        dec live
        rts

; outside: X = car.  C=1 if it is beyond the live region.
outside:
        lda c_xl,x
        cmp rx0
        lda c_xh,x
        sbc rx0+1
        bcc @out
        lda c_xl,x
        cmp rx1
        lda c_xh,x
        sbc rx1+1
        bcs @out
        lda c_yl,x
        cmp ry0
        lda c_yh,x
        sbc ry0+1
        bcc @out
        lda c_yl,x
        cmp ry1
        lda c_yh,x
        sbc ry1+1
        bcs @out
        clc
        rts
@out:   sec
        rts

; region: the live region from the camera, in world pixels
region:
        lda b64_cam_x
        sec
        sbc #MARGIN
        sta rx0
        lda b64_cam_x+1
        sbc #0
        sta rx0+1
        lda b64_cam_x
        clc
        adc #<(320 + MARGIN)
        sta rx1
        lda b64_cam_x+1
        adc #>(320 + MARGIN)
        sta rx1+1
        lda b64_cam_y
        sec
        sbc #MARGIN
        sta ry0
        lda b64_cam_y+1
        sbc #0
        sta ry0+1
        lda b64_cam_y
        clc
        adc #<(184 + MARGIN)
        sta ry1
        lda b64_cam_y+1
        adc #>(184 + MARGIN)
        sta ry1+1
        rts

; tiles: the metatiles wholly inside the live region, mx0..mx1 by my0..my1
tiles:
        lda rx0
        clc
        adc #31
        sta zt
        lda rx0+1
        adc #0
        sta zt+1
        jsr shr5
        sta mx0
        sty mx0+1
        lda rx1
        sta zt
        lda rx1+1
        sta zt+1
        jsr shr5
        sec
        sbc #1
        sta mx1
        tya
        sbc #0
        sta mx1+1
        lda ry0
        clc
        adc #31
        sta zt
        lda ry0+1
        adc #0
        sta zt+1
        jsr shr5
        sta my0
        sty my0+1
        lda ry1
        sta zt
        lda ry1+1
        sta zt+1
        jsr shr5
        sec
        sbc #1
        sta my1
        tya
        sbc #0
        sta my1+1
        rts

; shr5: zt/zt+1 / 32 -> A low, Y high
shr5:
        ldy #5
:       lsr zt+1
        ror zt
        dey
        bne :-
        lda zt
        ldy zt+1
        rts

; spawner: while the density is below the setting, one try: a random edge of
; the live region is scanned from a random point for a road crossing it, and
; that road gets a car driving inward, in its lane.  A top or bottom edge is
; one fetch of its row; a side is a fetch per metatile.
spawner:
        lda live
        cmp want
        bcc :+
        rts
:       jsr tiles
        jsr rng
        sta sp_h                ; bits 0-1: the edge
        lsr
        lsr
        and #15
        sta pop_i               ; where the scan starts
        lda sp_h
        and #2
        beq :+
        jmp spawn_side
:       lda mx0                 ; top or bottom: the row in one fetch
        sta zt
        lda mx0+1
        sta zt+1
        lda mx1
        sec
        sbc mx0
        clc
        adc #1
        sta pop_n
        lda my0                 ; edge 0 is the top, 1 the bottom
        sta zt+2
        lda my0+1
        sta zt+3
        lda sp_h
        and #1
        beq :+
        lda my1
        sta zt+2
        lda my1+1
        sta zt+3
:       jsr mt_addr
        B64_SET16 b64_ptr, rowbuf
        lda pop_n
        sta b64_len
        lda #0
        sta b64_len+1
        jsr b64_fetch
        ldx pop_n               ; from the start point, the first road running north-south
@r:     lda pop_i
        cmp pop_n
        bcc :+
        lda #0
        sta pop_i
:       ldy pop_i
        lda rowbuf,y
        tay
        lda B64_PROPS,y
        and #$0F
        cmp #$0C
        beq @found
        inc pop_i
        dex
        bne @r
        rts
@found: lda zt                  ; its metatile x
        clc
        adc pop_i
        sta zt
        bcc :+
        inc zt+1
:       lda sp_h
        and #1
        bne @bottom
        lda #H_S
        ldy #8
        jmp @vert
@bottom:
        lda #H_N
        ldy #24
@vert:  sta sp_h                ; x = mx * 32 + lane, y = my * 32 + 16
        sty zt+4
        jsr mt_to_px
        lda sp_x
        clc
        adc zt+4
        sta sp_x
        lda sp_y
        clc
        adc #16
        sta sp_y
        jmp spawn_ready

spawn_side:                     ; left or right: a fetch per metatile down the side
        ldy mx0
        lda mx0+1
        pha
        lda sp_h
        and #3
        tax
        pla
        cpx #3
        bne :+
        ldy mx1
        lda mx1+1
:       sty zt
        sta zt+1
        lda my1
        sec
        sbc my0
        clc
        adc #1
        sta pop_n
        ldx #4                  ; at most four fetches a try
@r:     lda pop_i
        cmp pop_n
        bcc :+
        lda #0
        sta pop_i
:       lda my0
        clc
        adc pop_i
        sta zt+2
        lda my0+1
        adc #0
        sta zt+3
        txa
        pha
        jsr mt_fetch
        tay
        pla
        tax
        tya
        and #$0F
        cmp #$03
        beq @found
        inc pop_i
        dex
        bne @r
        rts
@found: lda sp_h
        and #3
        cmp #3
        beq @right
        lda #H_E
        ldy #24
        jmp @horz
@right: lda #H_W
        ldy #8
@horz:  sta sp_h                ; x = mx * 32 + 16, y = my * 32 + lane
        sty zt+4
        jsr mt_to_px
        lda sp_x
        clc
        adc #16
        sta sp_x
        lda sp_y
        clc
        adc zt+4
        sta sp_y
spawn_ready:                    ; tried two frames later (frame)
        lda #1
        sta sp_ready
        rts

; mt_to_px: the metatile at zt -> sp_x, sp_y = its top-left in world pixels
mt_to_px:
        lda zt
        sta sp_x
        lda zt+1
        sta sp_x+1
        lda zt+2
        sta sp_y
        lda zt+3
        sta sp_y+1
        ldy #5
:       asl sp_x
        rol sp_x+1
        asl sp_y
        rol sp_y+1
        dey
        bne :-
        rts

; spawn_behind: the spawner's point, checked for a car close behind it on
; its line; sp_ready becomes 2 if there is none (spawn_try follows), else 0
spawn_behind:
        jsr spawn_slot
        bcc @no
        lda sp_h                ; the same line, the other way
        eor #2
        sta c_hd,x
        lda #G_SPAWN
        jsr check_ahead
        lda #$FF
        sta c_hd,x              ; the slot stays free until spawn_try
        bcs @no
        lda #2
        sta sp_ready
        rts
@no:    lda #0
        sta sp_ready
        rts

; spawn_slot: X = a free slot holding the spawn point, C=1; C=0 if none
spawn_slot:
        ldx #NCARS-1
:       lda c_hd,x
        bmi :+
        dex
        bpl :-
        clc
        rts
:       lda sp_x
        sta c_xl,x
        lda sp_x+1
        sta c_xh,x
        lda sp_y
        sta c_yl,x
        lda sp_y+1
        sta c_yh,x
        sec
        rts

; spawn_try: a car at sp_x, sp_y heading sp_h, if a slot is free, its bands
; have room, and no car is within G_SPAWN pixels along its line either way
; (the spawner's points were checked behind a frame earlier)
spawn_try:
        jsr spawn_slot
        bcs :+
        rts
:       lda pop_on              ; populate checks behind here; the spawner did already
        beq @ahead
        lda sp_h                ; behind it: the same line, the other way
        eor #2
        sta c_hd,x
        lda #G_SPAWN
        jsr check_ahead
        bcs @undo
@ahead: lda sp_h
        sta c_hd,x
        lda #G_SPAWN
        jsr check_ahead
        bcs @undo
        jsr bands_fit
        bcc @undo
        jsr bands_add
        lda #0
        sta c_st,x
        sta c_run,x
        jsr rng
        and #7
        tay
        lda traffic_col,y
        sta c_col,x
        inc live
        lda pop_on              ; placed by populate: plan now; by the spawner: on
        bne :+                  ; its first step, on a quiet frame
        lda #C_PLAN
        sta c_st,x
        lda #0
        sta c_nx,x
        lda #EX_NONE
        sta c_ex,x
        rts
:       jmp plan_next
@undo:  lda #$FF
        sta c_hd,x
        rts


; populate: at the start, cars on about half the road metatiles of the live
; region, each in a random one of its lanes
populate:
        lda #1
        sta pop_on
        jsr pop_all
        lda #0
        sta pop_on
        rts
pop_all:
        jsr tiles
        lda my0
        sta zt+2
        lda my0+1
        sta zt+3
@row:   lda mx0                 ; the row's metatiles in one fetch
        sta zt
        lda mx0+1
        sta zt+1
        lda mx1
        sec
        sbc mx0
        clc
        adc #1
        sta pop_n
        jsr mt_addr
        B64_SET16 b64_ptr, rowbuf
        lda pop_n
        sta b64_len
        lda #0
        sta b64_len+1
        jsr b64_fetch
        lda #0
        sta pop_i
@tile:  lda live
        cmp want
        bcc :+
        rts
:       ldy pop_i
        ldx rowbuf,y
        lda B64_PROPS,x
        and #$0F
        sta pop_p
        cmp #$03
        beq @road
        cmp #$0C
        bne @next
@road:  jsr rng
        and #2
        beq @next               ; about half of them
        jsr mt_to_px
        jsr rng
        and #1
        tay
        lda pop_p
        cmp #$03
        bne @v
        lda pop_h,y             ; east-west: E in the lane at 24, W at 8
        sta sp_h
        lda pop_lane,y
        clc
        adc sp_y
        sta sp_y
        lda sp_x
        clc
        adc #16
        sta sp_x
        jmp @try
@v:     lda pop_v,y             ; north-south: S in the lane at 8, N at 24
        sta sp_h
        lda pop_vlane,y
        clc
        adc sp_x
        sta sp_x
        lda sp_y
        clc
        adc #16
        sta sp_y
@try:   lda zt                  ; spawn_try uses zt
        pha
        lda zt+1
        pha
        lda zt+2
        pha
        lda zt+3
        pha
        jsr spawn_try
        pla
        sta zt+3
        pla
        sta zt+2
        pla
        sta zt+1
        pla
        sta zt
@next:  inc zt                  ; the next metatile along the row
        bne :+
        inc zt+1
:       inc pop_i
        lda pop_i
        cmp pop_n
        bcs :+
        jmp @tile
:       inc zt+2                ; the next row
        bne :+
        inc zt+3
:       lda my1
        cmp zt+2
        lda my1+1
        sbc zt+3
        bcc :+
        jmp @row
:       rts

; mt_addr: the metatile at zt -> b64_reu = its byte in the map
mt_addr:
        lda zt
        sta b64_reu
        lda zt+2
        asl
        asl
        asl
        ora zt+1
        sta b64_reu+1
        lda zt+3
        asl
        asl
        asl
        sta mt_t
        lda zt+2
        lsr
        lsr
        lsr
        lsr
        lsr
        ora mt_t
        sta b64_reu+2
        rts

; ---------------------------------------------------------------------------
; submit: the frame's sprite list: the player on sprite 0, every traffic car
; on screen on the multiplexer
submit:
        jsr b64_spr_begin
        ldx #PL
        lda c_hd,x
        jsr frame_addr
        jsr b64_spr_pinned
        lda #0
        sta shown
        ldx #NCARS-1
@c:     lda c_hd,x
        bmi @next
        lda c_xl,x              ; sprite x = centre x - camera x + 12
        sec
        sbc b64_cam_x
        sta zt
        lda c_xh,x
        sbc b64_cam_x+1
        sta zt+1
        lda zt
        clc
        adc #12
        sta b64_spr_x
        lda zt+1
        adc #0
        sta b64_spr_x+1
        beq @xok
        cmp #1
        bne @next
        lda b64_spr_x
        cmp #<344
        bcs @next
@xok:   lda c_yl,x              ; sprite y = centre y - camera y + 40
        sec
        sbc b64_cam_y
        sta zt
        lda c_yh,x
        sbc b64_cam_y+1
        bne @next
        lda zt
        clc
        adc #40
        bcs @next
        cmp #30
        bcc @next
        cmp #250
        bcs @next
        sta b64_spr_y
        stx zt+2
        lda c_hd,x
        jsr frame_addr
        ldx zt+2
        txa
        clc
        adc #1
        sta b64_spr_slot        ; slots 1-24
        lda c_col,x
        sta b64_spr_colour
        lda #B64_SPR_FLAG_MC
        sta b64_spr_flags
        jsr b64_spr_add
        ldx zt+2
        inc shown
@next:  dex
        bpl @c
        jmp b64_spr_end

; frame_addr: A = heading 0-3 -> b64_reu = its car frame in the sprite library
frame_addr:
        asl
        asl
        asl
        asl
        asl
        asl
        clc
        adc #<SLOT_SPRITES0
        sta b64_reu
        lda #>SLOT_SPRITES0
        adc #0
        sta b64_reu+1
        lda #^SLOT_SPRITES0
        adc #0
        sta b64_reu+2
        rts

; ---------------------------------------------------------------------------
; hud_update: CARS nn SHOWN nn  BUSIEST n/7  DROPS nnn
hud_update:
        ldy #63                 ; the busiest band
        lda #0
:       cmp band,y
        bcs :+
        lda band,y
:       dey
        bpl :--
        sta busiest
        ldy #40
:       lda hud_tpl,y
        sta hudbuf,y
        dey
        bpl :-
        lda live
        ldy #5
        jsr put_dec2
        lda shown
        ldy #14
        jsr put_dec2
        lda busiest
        clc
        adc #'0'
        sta hudbuf+26
        lda dropped             ; three digits, at most 999
        sta zt
        lda dropped+1
        sta zt+1
        cmp #>1000
        bcc @three
        bne @max
        lda zt
        cmp #<1000
        bcc @three
@max:   B64_SET16 zt, 999
@three: ldx #'0'
@h:     lda zt
        sec
        sbc #100
        tay
        lda zt+1
        sbc #0
        bcc :+
        sta zt+1
        sty zt
        inx
        jmp @h
:       stx hudbuf+37
        lda zt
        ldy #38
        jmp put_dec2

; hud_show: the formatted line onto the HUD row
hud_show:
        B64_SET16 b64_val, hudbuf
        ldx #0
        jmp b64_hud_text

; put_dec2: A = 0-99 -> two digits at hudbuf,y
put_dec2:
        ldx #'0'-1
        sec
:       inx
        sbc #10
        bcs :-
        adc #10 + '0'
        pha
        txa
        sta hudbuf,y
        pla
        sta hudbuf+1,y
        rts

; ---------------------------------------------------------------------------
; rng: A = a byte from a 16-bit maximal-length LFSR, Galois form.
; After Peter Alfke, Xilinx XAPP052 (the table of maximal-length taps).
; Changed: the 16-bit taps 16, 15, 13, 4 applied in Galois form, one step a call.
rng:
        asl rnd
        rol rnd+1
        bcc :+
        lda rnd
        eor #$11
        sta rnd
        lda rnd+1
        eor #$A0
        sta rnd+1
:       lda rnd
        rts

; travel_pos: X = car -> A = its position along its heading within the metatile
travel_pos:
        lda c_hd,x
        and #1
        beq :+
        lda c_xl,x
        and #31
        rts
:       lda c_yl,x
        and #31
        rts

; ---------------------------------------------------------------------------
; per heading N, E, S, W
dirbit:         .byte $08, $01, $04, $02        ; P_ROAD_N, E, S, W
lane:           .byte 24, 24, 8, 8              ; the lane's offset in its road
stop_at:        .byte 8, 20, 24, 12             ; the centre when the front reaches the crossing
edge_at:        .byte 0, 31, 31, 0              ; the last pixel before the next metatile
enter_at:       .byte 31, 0, 0, 31              ; the first pixel in a new one
fwd:            .byte 0, 1, 1, 0                ; 1: the travel position rises
half_along:     .byte 8, 12                     ; by (heading & 1): north-south, east-west
half_across:    .byte 6, 3
joybit:         .byte 1, 8, 2, 4
joyback:        .byte 2, 4, 1, 8
step_dx:        .byte 0, 1, 0, $FF
step_dxh:       .byte 0, 0, 0, $FF
step_dy:        .byte $FF, 0, 1, 0
step_dyh:       .byte $FF, 0, 0, 0
.if .defined(STREET) .or .defined(CITYENC)
; the band city is grey, so the traffic is too: white, light grey, dark grey
; and black, the only greys a sprite's own colour may be (docs/ART.md)
traffic_col:    .byte 1, 15, 11, 15, 1, 12, 11, 15
.else
traffic_col:    .byte 1, 15, 2, 6, 14, 7, 3, 4  ; never 13, the player's
.endif
pop_h:          .byte H_W, H_E
pop_lane:       .byte 8, 24
pop_v:          .byte H_S, H_N
pop_vlane:      .byte 8, 24
hud_tpl:        .byte "CARS 00 SHOWN 00  BUSIEST 0/7  DROPS 000", 0
.assert * - hud_tpl = 41, error, "the HUD line is 40 characters"

.segment "GAMEHI"
xc:     .res 4                  ; the crossing choose_exit is looking at
cur_c:  .res 1
mt_t:   .res 1
pop_n:  .res 1
pop_i:  .res 1
pop_p:  .res 1
sp_ready: .res 1                ; 1: a spawn point waits; 2: it is clear behind
pop_on: .res 1                  ; 1 while populate places cars
joy_test: .res 1                ; nonzero: used instead of the stick (the check)
joy_now: .res 1
