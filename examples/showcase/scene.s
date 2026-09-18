; backlot-64 showcase: baked lighting, streamed from the REU.
;
; Day falls to night over the Club Bellamar street through 32 precomputed
; colour maps, each landed in the vertical blank as 1.6 KB of DMA; the
; bitmap never changes.  Then the night set with the neon on, the cruiser
; drives in, and a red and blue strobe washes the whole scene in step with
; its light bar: two more colour maps.  All of it is this p-code.

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
BEACON  = 12
STEP    = 13
STROBE  = 14                    ; 0 off, 1 on: the draw thread lights the scene with the lamp

script:
        V_STILL   SLOT_DAYSET
        V_LDI     CAR, 0
        V_LDI     BEACON, 0
        V_LDI     STROBE, 0
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
        V_LDI     BEACON, 1
        V_LDI     STROBE, 1
        V_CALL    drive
        V_TEXT    22, 2, "THE LAMP LIGHTS ONLY WHAT IS NEAR IT"
        V_WAIT    200
        V_LDI     STROBE, 0
        V_LDI     STEP, 0
        V_LIGHT   SLOT_NIGHTLIGHT, STEP     ; back to the plain night
        V_LDI     BEACON, 0
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

; lampstate: STEP = 2 * (lamp position 0-19) from the car's x, so the
; state that follows is the map lit around this lamp (b64light.py beacon:
; lamp cell x = 2p + 5; the lamp sits 46 px right of the car's left edge)
lampstate:
        V_MOV     STEP, SX
        V_ADDI    STEP, 6
        V_SHR     STEP, 4
        V_MINI    STEP, 19
        V_SHL     STEP, 1
        V_RET

; draw: the actor, its light bar, and when STROBE is on, the surfaces
; near the lamp lit to match: red for 8 frames, blue for 8, each map
; landing on the base-phase blank of its half
draw:
        V_JEQI    CAR, 0, @none
        V_MOV     SX, AX
        V_SHR     SX, 4
        V_OBJSPR  1, SX, AY
        V_JEQI    BEACON, 0, @none
        V_FRAME   T
        V_ANDI    T, 15
        V_MOV     LY, AY
        V_SUBI    LY, 6
        V_MOV     LX, SX
        V_JGEI    T, 8, @blue
        V_ADDI    LX, 40
        V_SPRITE  23, LX, LY, 2, SLOT_LAMP
        V_JEQI    STROBE, 0, @none
        V_JNEI    T, 0, @none
        V_CALL    lampstate
        V_ADDI    STEP, 1                   ; the red map for this lamp position
        V_LIGHT   SLOT_NIGHTLIGHT, STEP
        V_JMP     @none
@blue:  V_ADDI    LX, 52
        V_SPRITE  23, LX, LY, 6, SLOT_LAMP
        V_JEQI    STROBE, 0, @none
        V_JNEI    T, 8, @none
        V_CALL    lampstate
        V_ADDI    STEP, 2                   ; the blue map
        V_LIGHT   SLOT_NIGHTLIGHT, STEP
@none:  V_YIELD
        V_JMP     draw
