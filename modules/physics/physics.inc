; backlot-64 physics module: what a game needs to use it (docs/PHYSICS.md).
; The module is pinned at $6000.  Its entry points and body tables are in the
; generated build/physics_syms.inc (include both):
;   phys_init             every body free
;   phys_add              A = mover, Y = class, phys_x/y/a -> X = body, C=1
;   phys_remove           X = body
;   phys_step             every body one frame
;   phys_push             X = body, phys_x/y = a velocity change (8.8)

PHYS_BASE       = $6000
PHYS_SIZE       = $1800                 ; what a physics module loads: $6000-$77FF; the
                                        ; body tables above it ($7800) survive a swap

PHYS_NB         = 12                    ; bodies

M_FOOT          = 1                     ; movers
M_WHEELS        = 2

C_WALKER        = 0                     ; classes (docs/PHYSICS.md section 4)
C_SEDAN         = 1
C_SPORTS        = 2
C_TRUCK         = 3
C_BIKE          = 4

ST_SKID         = $01                   ; pb_st bits
ST_DOWN         = $02
ST_WORLD        = $04
ST_WALL         = $08
ST_SLEEP        = $80

IN_UP           = $01                   ; pb_in bits: throttle, brake / reverse,
IN_DOWN         = $02                   ; steer, handbrake; on foot the directions
IN_LEFT         = $04                   ; and run
IN_RIGHT        = $08
IN_FIRE         = $10

SURF_ROAD       = 0                     ; pb_surf
SURF_PAVEMENT   = 1
SURF_ROUGH      = 2
SURF_WATER      = 3
