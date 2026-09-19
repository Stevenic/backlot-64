; backlot-64 physics, water: on foot and in boats (docs/PHYSICS.md).
;
; A pinned module (pinned.cfg), loaded into the game's module region at
; $6000 in place of the ground module when the player takes to the water,
; and swapped back on landing.  Both assemble the same core (core.s); the
; body tables live above the module at fixed addresses (defs.inc), so the
; swap keeps every body where it was.  Cars hold still while this module is
; in (they have no mover here) and take up from rest when the ground module
; returns.

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
.include "frame.s"
.include "hull.s"

; the movers this module carries, by mover number (the address less one)
mover_tab:  .word hold-1, foot-1, hold-1, hull-1, hold-1, hold-1, hold-1
; what each mover counts as a wall: (properties & and) ^ eor, non-zero
wall_and:   .byte 0, WALL, WALL, P_WATER, 0, WALL, WALL
wall_eor:   .byte 0, 0, 0, P_WATER, 0, 0, 0

.include "tables.s"
.include "private.s"
