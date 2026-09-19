; backlot-64 AI: what the module and a game share (docs/AI.md).
;
; The module sits in region A beside the collision module ($8D00, ai.cfg) and
; calls it; the brains live at a fixed address in the game's hot state, one
; row a physics body, so a game and its scripts read and set them directly.

AI_BASE   = $8D00               ; the jump table
AI_INIT   = AI_BASE + 0         ; every brain empty, no events
AI_SET    = AI_BASE + 3         ; X = body, A = behaviour, Y = target body ($FF: the point ai_px/py)
AI_STEP   = AI_BASE + 6         ; every brain one tick: before the physics step
AI_NOISE  = AI_BASE + 9         ; ai_px/py = where, A = radius, X = who made it ($FF none)
AI_EVENT  = AI_BASE + 12        ; C=1 if one was waiting: A = what, X = body, Y = the other body

; behaviours (ab_beh)
B_NONE    = 0                   ; no brain: the game or the player drives it
B_IDLE    = 1
B_WANDER  = 2
B_GOTO    = 3                   ; to the point ab_tx/ty
B_FOLLOW  = 4                   ; the body ab_tgt
B_FLEE    = 5                   ; from ab_tgt, or the point if $FF
B_PURSUE  = 6                   ; ab_tgt, where it will be
B_ATTACK  = 7                   ; ab_tgt: pursue, and fire when in sight and in range
B_SEARCH  = 8                   ; where ab_tgt was last seen

; teams (ab_team)
T_CIVIL   = 0                   ; panics at a shot, spreads it
T_POLICE  = 1                   ; responds to a shot by the heat the game sets (ai_heat)
T_PLAYER  = 2

; events (AI_EVENT)
E_SAW     = 1                   ; X saw its target Y
E_LOST    = 2                   ; X lost sight of Y
E_HEARD   = 3                   ; X heard a noise made by Y
E_PANIC   = 4                   ; X panicked (Y: who scared it, $FF a noise)
E_ARRIVED = 5                   ; X reached its point
E_GAVEUP  = 6                   ; X searched and gave up on Y
E_FIRED   = 7                   ; X fired at Y

; the brains: a row of NB (12) a field, from AB_BASE
AB_BASE   = $E100
AB_NB     = 12
ab_beh    = AB_BASE + 0 * AB_NB
ab_tgt    = AB_BASE + 1 * AB_NB     ; a body, or $FF for the point
ab_txl    = AB_BASE + 2 * AB_NB     ; the point, 16-bit world pixels
ab_txh    = AB_BASE + 3 * AB_NB
ab_tyl    = AB_BASE + 4 * AB_NB
ab_tyh    = AB_BASE + 5 * AB_NB
ab_lxl    = AB_BASE + 6 * AB_NB     ; where it last saw its target
ab_lxh    = AB_BASE + 7 * AB_NB
ab_lyl    = AB_BASE + 8 * AB_NB
ab_lyh    = AB_BASE + 9 * AB_NB
ab_see    = AB_BASE + 10 * AB_NB    ; bit 7: sees its target now
ab_alert  = AB_BASE + 11 * AB_NB    ; 0 calm; alert sees every way; fades a tick at a time
ab_team   = AB_BASE + 12 * AB_NB
ab_tmr    = AB_BASE + 13 * AB_NB    ; the behaviour's own timer, ticks
ab_cool   = AB_BASE + 14 * AB_NB    ; ticks until it may fire again
ab_dir    = AB_BASE + 15 * AB_NB    ; the heading it wants (wander keeps its own)
AB_END    = AB_BASE + 16 * AB_NB

; the module's inputs, at fixed addresses after the brains
ai_px     = AB_END                  ; a point: AI_SET's with Y = $FF, AI_NOISE's
ai_py     = AB_END + 2
ai_heat   = AB_END + 4              ; the police's response: 0 patrol, 1 pursue, 2 attack
