; backlot-64 example: a script-driven cutscene.
;
; Everything per-frame is engine assembly: the still, block and object DMAs,
; the sprite multiplexer, the text band, the shimmer, and the VM that runs
; the scene's p-code (scene.s), which lives in the REU.  Nothing here runs
; per frame except that p-code.
;
; Scene: night outside the Club Bellamar.  A cruiser drives in as an object,
; eases to a stop with its wheels turning, its beacon flashes, an officer
; speaks, the car parks as a block pixel for pixel, then drives off.

.include "b64.inc"
.include "slots.inc"

.export game_main

.segment "GAMETOP"
replay_held:    .res 1

.segment "GAME"
game_main:
        jsr b64_init
        B64_SET24 b64_reu, SLOT_TILESET0
        jsr b64_load_tileset    ; for the font
        jsr b64_cut_begin
        jsr start
        lda #<frame
        ldx #>frame
        jsr b64_set_callback
        jmp b64_run

start:
        B64_SET24 b64_reu, SLOT_SCENE
        lda #0
        ldx #0
        jmp b64_vm_start

; fire on joystick 2 or the space bar replays the scene from the top
frame:
        lda b64_joy
        and #$10
        bne @pressed
        lda #$7F
        sta CIA1_PRA
        lda CIA1_PRB
        and #$10
        beq @pressed
        lda #0
        sta replay_held
        jmp b64_vm_tick
@pressed:
        lda replay_held
        bne :+
        lda #1
        sta replay_held
        jsr start
:       jmp b64_vm_tick
