; backlot-64 physics modules: what a game needs to use them (docs/PHYSICS.md).
; A module is pinned at $6000: ground (on foot, wheels), water (on foot,
; hulls) or air (on foot, helicopters), swapped by fetching another over it
; and calling PHYS_RESUME.  Set phys_world and phys_tiles (the tileset's REU
; address, for the air module's heights) once at the start.  Call them through the jump
; table below; the body tables are in the generated build/physics_syms.inc,
; at the same addresses for every module (include both):
;   phys_init             every body free
;   phys_add              A = mover, Y = class, phys_x/y/a -> X = body, C=1
;   phys_remove           X = body
;   phys_step             every body one frame
;   phys_push             X = body, phys_x/y = a velocity change (8.8)

PHYS_BASE       = $6000
PHYS_SIZE       = $1A00                 ; what a physics module loads: $6000-$79FF; the
                                        ; body tables above it ($7A00) survive a swap

PHYS_NB         = 12                    ; bodies

; the jump table every physics module starts with: call through it, so that
; a game keeps working when one module is swapped for another
PHYS_INIT       = PHYS_BASE + 0
PHYS_ADD        = PHYS_BASE + 3
PHYS_REMOVE     = PHYS_BASE + 6
PHYS_STEP       = PHYS_BASE + 9
PHYS_PUSH       = PHYS_BASE + 12
PHYS_RESUME     = PHYS_BASE + 15        ; after every fetch: the map caches again, in this module's form

M_FOOT          = 1                     ; movers
M_WHEELS        = 2
M_HULL          = 3
M_AIR           = 4
M_PLANE         = 6
M_AIRBOAT       = 7

C_WALKER        = 0                     ; classes (docs/PHYSICS.md section 4)
C_SEDAN         = 1
C_SPORTS        = 2
C_TRUCK         = 3
C_BIKE          = 4
C_SPEEDBOAT     = 5
C_LAUNCH        = 6
C_JETSKI        = 7
C_HELI          = 8
C_PLANE         = 9
C_AIRBOAT       = 10

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
