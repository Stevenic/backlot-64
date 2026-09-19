; backlot-64 physics, air: on foot and helicopters (docs/PHYSICS.md).
;
; A pinned module (pinned.cfg), fetched over the ground module at $6000 when
; the player takes off and swapped back on landing, like the water module.
; The core is assembled with AIR, which folds each building's height into
; the map cache (from the tileset's heights table, phys_tiles), makes a
; solid metatile a wall to an aircraft only below its height, and lets
; bodies at different heights pass.  Call phys_resume after the fetch.

AIR = 1

.include "b64.inc"
.include "defs.inc"

.export phys_init, phys_add, phys_remove, phys_step, phys_push, phys_resume
.export phys_x, phys_y, phys_a, phys_world, phys_tiles
.export pb_mov, pb_cls, pb_xf, pb_xl, pb_xh, pb_yf, pb_yl, pb_yh
.export pb_vxl, pb_vxh, pb_vyl, pb_vyh, pb_vll, pb_vlh, pb_vtl, pb_vth
.export pb_ang, pb_in, pb_st, pb_dmg, pb_hit, pb_surf, pb_tmr, pb_idle, pb_hw
.export pb_zl, pb_zh, pb_vzl, pb_vzh, pb_agl
.export phys_sine

.segment "OVERLAY"
        jmp phys_init           ; +0
        jmp phys_add            ; +3
        jmp phys_remove         ; +6
        jmp phys_step           ; +9
        jmp phys_push           ; +12
        jmp phys_resume         ; +15

.include "core.s"
.include "foot.s"
.include "heli.s"

; the movers this module carries, by mover number (the address less one)
mover_tab:  .word hold-1, foot-1, hold-1, hold-1, heli-1, hold-1
; what each mover counts as a wall: (properties & and) ^ eor, non-zero; for
; an aircraft (wall_alt bit 7) a solid metatile standing higher than it
wall_and:   .byte 0, WALL, WALL, P_WATER, 0, WALL
wall_eor:   .byte 0, 0, 0, P_WATER, 0, 0
wall_alt:   .byte 0, 0, 0, 0, $80, 0

.include "tables.s"
.include "private.s"
