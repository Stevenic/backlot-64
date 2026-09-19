; backlot-64 example: a game written in p-code, its modules loaded by the VM
; (docs/MODULES.md section 9).
;
; The resident code below boots the engine, draws the street and starts
; the script (script.s); it knows nothing of physics, collision or AI.  The
; script calls them by address with SYS, naming each one's interface, and
; the VM loads the module providing it the first time, requirements first:
; the physics module, then the collision module and the AI (which require
; it).  People wander the pavement under the AI.  The script's second thread
; draws them with a game opcode, DRAW, whose handler is in the game's own
; module (ops.s, $3800); the first DRAW brings it in.  A third thread swaps
; the physics module for the water module and back, and asks for two loads
; the manager must refuse: one over the collision module the AI requires,
; and one over a pinned module.  The status row shows what is resident.
;
; The game's resident code must end below $3800, where its module goes.

.include "b64.inc"
.include "slots.inc"

.export game_main

PCX     = 160                   ; the street's middle on the playfield
PCY     = 92
START_X = 1300 * 32 + 16        ; the pavement south of the road at metatile row 1000
START_Y = 1001 * 32 + 16

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
        B64_SET16 b64_cam_x, START_X - PCX
        B64_SET16 b64_cam_y, START_Y - PCY
        jsr b64_redraw
        lda #0                  ; no player: the pinned sprite stays off
        sta VIC_SPR_ENA
        sta VIC_SPR_MCOLOR0
        lda #1
        sta VIC_SPR_MCOLOR1
script_start:
        B64_SET24 b64_reu, SLOT_MODSCRIPT
        lda #0
        tax
        jsr b64_vm_start
        lda #<b64_vm_tick       ; every frame: the script, and nothing else
        ldx #>b64_vm_tick
        jsr b64_set_callback
        jmp b64_run
game_end:

.assert game_end <= $3800, lderror, "the game's resident code runs into its module's place at $3800"
