; backlot-64 example: the Club Bellamar scene as p-code.
;
; Assembled at offset 0 with script.cfg and packed into the REU as SLOT_SCENE.
; Nothing in this file is resident: the VM reads it through the page cache.

.include "b64.inc"
.include "slots.inc"

; ---------------------------------------------------------------------------
; The scene as p-code.  Positions are in 1/16 pixel so speeds can be
; fractional; the draw thread converts to sprite pixels.
.segment "SCRIPT"

; variables
AX      = 0                     ; actor x, 1/16 px
AY      = 1                     ; actor y, px
VEL     = 2                     ; 1/16 px per frame
TGT     = 3                     ; drive target, 1/16 px
REM     = 4                     ; distance left
T       = 5
WACC    = 6                     ; distance since the last wheel frame
WFR     = 7                     ; wheel frame 0-3
SX      = 8                     ; sprite x, px
LX      = 9                     ; lamp x
LY      = 10                    ; lamp y
CAR     = 11                    ; 1 = draw the actor
BEACON  = 12                    ; 1 = flash the light bar

script:
        V_STILL   SLOT_NIGHTSET
        V_OBJECT  SLOT_CRUISEROBJ
        V_SHIMMER 1
        V_LDI     CAR, 0
        V_LDI     BEACON, 0
        V_LDI     WFR, 0
        V_LDI     WACC, 0
        V_SPAWN   draw
        V_TEXT    21, 2, "CLUB BELLAMAR, 2:14 AM"
        V_WAIT    60
        V_LDI     AX, 0*16               ; off the left edge, cell-aligned y
        V_LDI     AY, 162
        V_LDI     CAR, 1
        V_LDI     TGT, 240*16           ; x = 240 = 24 + 27*8: cell 27
        V_CALL    drive
        V_LDI     BEACON, 1
        V_TEXT    22, 2, "OFFICER: STEP OUT OF THE VEHICLE."
        V_WAIT    120
        V_PARK    27, 14                ; waits for the vblank that can do it
        V_LDI     CAR, 0                ; same frame: the sprites leave as the block lands
        V_LDI     BEACON, 0
        V_TEXT    23, 2, "(THE ENGINE CUTS OUT.)"
        V_WAIT    150
        V_UNPARK  27, 14
        V_LDI     CAR, 1
        V_LDI     BEACON, 1
        V_CLEARTEXT
        V_LDI     TGT, 430*16
        V_CALL    drive
        V_LDI     CAR, 0
        V_LDI     BEACON, 0
        V_WAIT    60
        V_END

; drive: ease X to TGT.  Accelerate 1/8 px per frame to 2 px, ease out over
; the last 16 px at rem/8 px per frame (never under 1/4 px), snap at the
; target.  Wheels advance one frame every 2.5 px.
drive:
        V_LDI     VEL, 0
@step:  V_MOV     REM, TGT
        V_SUB     REM, AX
        V_JEQI    REM, 0, @done
        V_ADDI    VEL, 2
        V_MINI    VEL, 32
        V_JGEI    REM, 16*16, @move
        V_MOV     VEL, REM
        V_SHR     VEL, 3
        V_MAXI    VEL, 4
@move:  V_ADD     AX, VEL
        V_MIN     AX, TGT
        V_ADD     WACC, VEL
        V_JLTI    WACC, 40, @frame
        V_SUBI    WACC, 40
        V_ADDI    WFR, 1
        V_ANDI    WFR, 3
        V_OBJANIM WFR
@frame: V_YIELD
        V_JMP     @step
@done:  V_LDI     WFR, 0                ; at rest the wheels show frame 0: what the block was cut from
        V_OBJANIM WFR
        V_RET

; draw: every frame, the actor's sprite grid and its light bar.  The bar is
; a red lamp for 4 frames then a blue one, 12 px apart, 6 px above the roof.
draw:
        V_JEQI    CAR, 0, @none
        V_MOV     SX, AX
        V_SHR     SX, 4
        V_OBJSPR  1, SX, AY
        V_JEQI    BEACON, 0, @none
        V_FRAME   T
        V_ANDI    T, 7
        V_MOV     LY, AY
        V_SUBI    LY, 6
        V_MOV     LX, SX
        V_JGEI    T, 4, @blue
        V_ADDI    LX, 40
        V_SPRITE  23, LX, LY, 2, SLOT_LAMP
        V_JMP     @none
@blue:  V_ADDI    LX, 52
        V_SPRITE  23, LX, LY, 6, SLOT_LAMP
@none:  V_YIELD
        V_JMP     draw
