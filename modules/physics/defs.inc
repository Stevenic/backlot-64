; backlot-64 physics: what every physics module shares (docs/PHYSICS.md):
; constants, zero page, and the body tables at fixed addresses.
;
; A pinned module (pinned.cfg): loaded into the game's module region at
; $6000 when play starts.  Built so far: the core (numbers, the map under
; each body, walls, collisions between bodies, rest) and two movers, foot
; and wheels.  Water, air and thrown follow (docs/PHYSICS.md).
;
; Every routine that works on one body takes it in X and keeps it there.
; Zero page $80-$8F is the module's.



NB      = 12                    ; bodies
M_FOOT  = 1
M_WHEELS = 2

ST_SKID  = $01                  ; sliding: more sideways speed than grip can take
ST_DOWN  = $02                  ; on foot, knocked down
ST_WORLD = $04                  ; a collision changed the world velocity: the car's frame follows
ST_WALL  = $08                  ; hit a wall this frame
ST_SLEEP = $80

IN_UP    = $01
IN_DOWN  = $02
IN_LEFT  = $04
IN_RIGHT = $08
IN_FIRE  = $10

WALL     = P_SOLID | P_WATER    ; what stops feet and wheels (the hull mover will invert water)

t0      = $80
t1      = $81
t2      = $82
t3      = $83
t4      = $84
t5      = $85
mr_lo   = $86                   ; umul8's product
mr_hi   = $87
m16     = $88                   ; smul: the 8.8 operand
res     = $8A                   ; smul: the 8.8 product
ua      = $8C
ub      = $8D
sgn     = $8E
cur     = $8F                   ; the body being worked on

; the body tables, at fixed addresses that every physics module and the
; collision module share, so a module swap keeps every body where it was
PB_BASE = $7800
M_HULL   = 3                    ; movers still to come
M_AIR    = 4
M_THROWN = 5
.enum
        k_mov
        k_cls
        k_xf
        k_xl
        k_xh
        k_yf
        k_yl
        k_yh
        k_vxl
        k_vxh
        k_vyl
        k_vyh
        k_vll
        k_vlh
        k_vtl
        k_vth
        k_ang
        k_in
        k_st
        k_idle
        k_dmg
        k_hit
        k_surf
        k_tmr
        k_cmx
        k_cmy
        k_zl                    ; altitude, 8.8 (air)
        k_zh
        k_vzl
        k_vzh
        k_count
.endenum
pb_mov  = PB_BASE + k_mov * NB
pb_cls  = PB_BASE + k_cls * NB
pb_xf   = PB_BASE + k_xf * NB
pb_xl   = PB_BASE + k_xl * NB
pb_xh   = PB_BASE + k_xh * NB
pb_yf   = PB_BASE + k_yf * NB
pb_yl   = PB_BASE + k_yl * NB
pb_yh   = PB_BASE + k_yh * NB
pb_vxl  = PB_BASE + k_vxl * NB
pb_vxh  = PB_BASE + k_vxh * NB
pb_vyl  = PB_BASE + k_vyl * NB
pb_vyh  = PB_BASE + k_vyh * NB
pb_vll  = PB_BASE + k_vll * NB
pb_vlh  = PB_BASE + k_vlh * NB
pb_vtl  = PB_BASE + k_vtl * NB
pb_vth  = PB_BASE + k_vth * NB
pb_ang  = PB_BASE + k_ang * NB
pb_in   = PB_BASE + k_in * NB
pb_st   = PB_BASE + k_st * NB
pb_idle = PB_BASE + k_idle * NB
pb_dmg  = PB_BASE + k_dmg * NB
pb_hit  = PB_BASE + k_hit * NB
pb_surf = PB_BASE + k_surf * NB
pb_tmr  = PB_BASE + k_tmr * NB
pb_cmx  = PB_BASE + k_cmx * NB
pb_cmy  = PB_BASE + k_cmy * NB
pb_zl   = PB_BASE + k_zl * NB
pb_zh   = PB_BASE + k_zh * NB
pb_vzl  = PB_BASE + k_vzl * NB
pb_vzh  = PB_BASE + k_vzh * NB
cache   = PB_BASE + k_count * NB        ; 9 entries a body: the 3 x 3 metatiles' properties
phys_x  = cache + 9 * NB                ; phys_add and phys_push take their input here
phys_y  = phys_x + 2
phys_a  = phys_y + 2
phys_world = phys_a + 1                 ; the world map's REU address (SLOT_WORLD)
PB_END  = phys_world + 3
.assert PB_END <= $7C00, error, "the body tables outgrow their place"
