; backlot-64 benchmark scripts, packed as SLOT_BENCH.  Each script sits at a
; fixed offset so the benchmark can start it by address:
;   $000  LOOP only (64 ops/tick)   $100  the drive body (71 ops/tick, 4 steps)   $200  ADD (65 ops/tick)

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
@l:     V_LOOP    CNT, @l               ; 64 taken jumps per tick: exactly 64 opcodes
        V_END
        .res $100-(*-s_loop)

; the cutscene drive loop body: 6 LDI, 4 iterations of 16 opcodes, then YIELD.
; 71 opcodes per tick, 4 iterations of the step.
s_drive:
@start: V_LDI     AX, 0
        V_LDI     TGT, 240*16
        V_LDI     VEL, 0
        V_LDI     WACC, 0
        V_LDI     WFR, 0
        V_LDI     CNT, 4
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
@done:  V_YIELD
        V_JMP     @start
        .res $200-(*-s_loop)

; 63 ADD then YIELD: 64 opcodes per tick plus the JMP that restarts it
s_add:
        V_LDI     V8, 1
@l:
.repeat 63
        V_ADD     V9, V8
.endrepeat
        V_YIELD
        V_JMP     @l
