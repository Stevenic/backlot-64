; backlot-64 showcase: baked lighting, streamed from the REU.
;
; Day falls to night over a sunset still through 32 precomputed colour
; maps, each landed in the vertical blank as 1.6 KB of DMA; the bitmap
; never changes.  Then the night street: the cruiser drives in and its
; light bar, declared in the object file with a pattern and a radius,
; lights the surfaces near it from maps baked for every position, in step
; with the lamp sprites the engine draws for it.  All of it is this p-code
; and one LIGHTS opcode.

.include "b64.inc"
.include "slots.inc"

.segment "SCRIPT"

AX      = 0
AY      = 1
VEL     = 2
TGT     = 3
REM     = 4
T       = 5
WACC    = 6
WFR     = 7
SX      = 8
LX      = 9
LY      = 10
CAR     = 11
STEP    = 13

script:
        V_STILL   SLOT_DAYSET
        V_LDI     CAR, 0
        V_LDI     WFR, 0
        V_LDI     WACC, 0
        V_SPAWN   draw
        V_TEXT    21, 2, "BELLAMAR, 6:40 PM"
        V_TEXT    22, 2, "32 COLOUR MAPS, 1.6 KB EACH, STREAMED"
        V_WAIT    90
        ; dusk: states 0..31, one every 8 frames (the blank applies a state
        ; only on base-phase frames, every 8th), about five seconds
        V_LDI     STEP, 0
@dusk:  V_LIGHT   SLOT_DAYLIGHT, STEP
        V_WAIT    8
        V_ADDI    STEP, 1
        V_JLTI    STEP, 32, @dusk
        V_WAIT    60
        V_CLEARTEXT
        V_TEXT    21, 2, "CLUB BELLAMAR, 2:14 AM"
        V_STILL   SLOT_NIGHTSET
        V_OBJECT  SLOT_CRUISEROBJ
        V_SHIMMER 1
        V_WAIT    60
        V_LDI     AX, 0
        V_LDI     AY, 162
        V_LDI     CAR, 1
        V_LDI     TGT, 240*16
        V_LIGHTS  SLOT_NIGHTLIGHT, SLOT_LAMP, 1   ; the cruiser's own lights, on
        V_CALL    drive
        V_TEXT    22, 2, "THE LIGHTS ARE PART OF THE CAR"
        V_WAIT    200
        V_LIGHTS  SLOT_NIGHTLIGHT, SLOT_LAMP, 0   ; off: the set as it is
        V_WAIT    16
        V_PARK    27, 14
        V_LDI     CAR, 0
        V_TEXT    23, 2, "(PARKED AS A BLOCK. NOTHING MOVED.)"
        V_WAIT    200
        V_END

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
@done:  V_LDI     WFR, 0
        V_OBJANIM WFR
        V_RET

; draw: the actor.  Its light bar and the light it throws on the set are
; the object's own: LIGHTS in the main thread turns them on, and the
; engine draws the lamps and lands the maps from the object's patterns.
draw:
        V_JEQI    CAR, 0, @none
        V_MOV     SX, AX
        V_SHR     SX, 4
        V_OBJSPR  1, SX, AY
@none:  V_YIELD
        V_JMP     draw
