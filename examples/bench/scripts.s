; backlot-64 benchmark scripts, packed as SLOT_BENCH.  Each script sits at a
; fixed offset so the benchmark can start it by address:
;   $000  LOOP only        $100  the drive body        $200  ADD only

.include "b64.inc"

.segment "SCRIPT"

CNT = 0
AX  = 1
VEL = 2
TGT = 3
REM = 4
WACC = 6
WFR = 7
V8  = 8
V9  = 9

s_loop:
        V_LDI     CNT, 10000
@l:     V_LOOP    CNT, @l
        V_END
        .res $100-(*-s_loop)

; the cutscene drive loop body (see examples/cutscene), without the YIELD,
; so one tick runs it back to back
s_drive:
        V_LDI     CNT, 10000
        V_LDI     AX, 0
        V_LDI     TGT, 240*16
        V_LDI     VEL, 0
        V_LDI     WACC, 0
        V_LDI     WFR, 0
@l:     V_MOV     REM, TGT
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
@frame: V_LOOP    CNT, @l
@done:  V_END
        .res $200-(*-s_loop)

s_add:
        V_LDI     V8, 1
@l:     V_ADD     V9, V8
        V_JMP     @l
