; backlot-64 example: the game of examples/modules, all of it p-code.
;
; Assembled at offset 0 with script.cfg and packed as SLOT_MODSCRIPT.  It
; calls the physics, collision and AI modules by address with SYS, naming
; the interface whose module must be resident (docs/MODULES.md section 9);
; reads and writes their tables with LDB and STB; draws with the game's own
; opcodes, DRAW and SHOW (ops.s); and asks for loads with NEED.  None of it
; says where a module comes from or when: the VM loads what is missing, its
; requirements first.

.include "b64.inc"
.include "slots.inc"
.include "../../modules/physics/physics.inc"
.include "physics_syms.inc"
.include "collision_syms.inc"
.include "../../modules/ai/ai.inc"

.segment "SCRIPT"

START_X = 1300 * 32 + 16        ; the pavement south of the road at metatile row 1000
START_Y = 1001 * 32 + 16
LANE_W  = 1000 * 32 + 8

; variables (shared by every thread, so each thread keeps to its own)
T       = 0                     ; thread 0: scratch
N       = 1                     ; a row of the table below
B       = 2                     ; the body PHYS_ADD made
MV      = 3                     ; its mover
CL      = 4                     ; its class
K       = 5                     ; ticks stepped
DT      = 6                     ; thread 1: scratch
LT      = 7                     ; thread 2: scratch
; the loads, for the check (1 resident, 0 refused; the reasons from B64_MOD_ERR)
R_AI    = 10                    ; NEED MOD_AI: the collision module, then the AI
R_WATER = 11                    ; NEED MOD_PHYS_WATER: the swap
R_OVL   = 12                    ; NEED MOD_OVERLAY1: refused, the collision module is in the way
R_OVLE  = 13                    ; why: MOD_COLLISION
R_GND   = 14                    ; NEED MOD_PHYS_GROUND: back
R_PIN   = 15                    ; NEED MOD_PHYS_WATER with the ground module pinned: refused
R_PINE  = 16                    ; why: MOD_PHYS_GROUND
R_DONE  = 17                    ; 1 when the loader is done
R_TICK  = 18                    ; the frame (its low byte) the setup finished on

script:
        V_SPAWN   loader
        ; the physics: nothing provides PHYS yet, so this SYS has the
        ; default provider (the ground module) loaded and runs again
        V_SYS     IF_PHYS, PHYS_INIT, VM_NONE, VM_NONE, VM_NONE, VM_NONE
        V_LDI     T, <SLOT_WORLD
        V_STB     T, phys_world, VM_NONE
        V_LDI     T, >SLOT_WORLD
        V_STB     T, phys_world+1, VM_NONE
        V_LDI     T, ^SLOT_WORLD
        V_STB     T, phys_world+2, VM_NONE
        V_LDI     T, <SLOT_TILESET0
        V_STB     T, phys_tiles, VM_NONE
        V_LDI     T, >SLOT_TILESET0
        V_STB     T, phys_tiles+1, VM_NONE
        V_LDI     T, ^SLOT_TILESET0
        V_STB     T, phys_tiles+2, VM_NONE
        ; the AI, which requires the physics and the collision modules: the
        ; collision module comes first, then the AI
        V_NEED    MOD_AI, R_AI
        V_SYS     IF_COL, col_init, VM_NONE, VM_NONE, VM_NONE, VM_NONE
        V_SYS     IF_AI, AI_INIT, VM_NONE, VM_NONE, VM_NONE, VM_NONE
        ; the bodies, each with a brain
        V_LDI     N, 0
@add:   V_LDT     MV, t_mov, N
        V_JEQI    MV, 0, @added
        V_LDT     T, t_xl, N
        V_STB     T, phys_x, VM_NONE
        V_LDT     T, t_xh, N
        V_STB     T, phys_x+1, VM_NONE
        V_LDT     T, t_yl, N
        V_STB     T, phys_y, VM_NONE
        V_LDT     T, t_yh, N
        V_STB     T, phys_y+1, VM_NONE
        V_LDT     T, t_ang, N
        V_STB     T, phys_a, VM_NONE
        V_LDT     CL, t_cls, N
        V_SYS     IF_PHYS, PHYS_ADD, MV, B, CL, VM_NONE      ; A = mover, Y = class -> X = body
        V_LDI     T, T_CIVIL
        V_STB     T, ab_team, B
        V_LDT     T, t_beh, N
        V_STB     T, ab_beh, B
        V_ADDI    N, 1
        V_JMP     @add
@added: V_FRAME   R_TICK
        V_SPAWN   draw
        ; every frame: the AI, then the physics, each through its interface
@loop:  V_SYS     IF_AI, AI_STEP, VM_NONE, VM_NONE, VM_NONE, VM_NONE
        V_SYS     IF_PHYS, PHYS_STEP, VM_NONE, VM_NONE, VM_NONE, VM_NONE
        V_ADDI    K, 1
        V_YIELD
        V_JMP     @loop

; thread 1: the bodies onto the multiplexer every frame, with the game's
; own opcode; the modules on the status row every eighth
draw:   V_OP      OP_DRAW
        V_FRAME   DT
        V_ANDI    DT, 7
        V_JNEI    DT, 0, @y
        V_OP      OP_SHOW
@y:     V_YIELD
        V_JMP     draw

; thread 2: loads by the clock
loader: V_WAIT    150
        V_NEED    MOD_PHYS_WATER, R_WATER   ; takes the ground module's place and its two dependents
        V_WAIT    100
        V_NEED    MOD_OVERLAY1, R_OVL       ; region A at $8000: the collision module, which the AI requires
        V_LDB     R_OVLE, B64_MOD_ERR, VM_NONE
        V_WAIT    100
        V_NEED    MOD_PHYS_GROUND, R_GND
        V_LDI     LT, MOD_PHYS_GROUND       ; pinned, the ground module stays whatever asks
        V_SYS     0, API_MOD_PIN, LT, VM_NONE, VM_NONE, VM_NONE
        V_NEED    MOD_PHYS_WATER, R_PIN
        V_LDB     R_PINE, B64_MOD_ERR, VM_NONE
        V_LDI     LT, MOD_PHYS_GROUND
        V_SYS     0, API_MOD_UNPIN, LT, VM_NONE, VM_NONE, VM_NONE
        V_LDI     R_DONE, 1
        V_END

; the bodies: six people on the pavement, a car parked in the lane
t_mov:  .byte M_FOOT, M_FOOT, M_FOOT, M_FOOT, M_FOOT, M_FOOT, M_WHEELS, 0
t_cls:  .byte C_WALKER, C_WALKER, C_WALKER, C_WALKER, C_WALKER, C_WALKER, C_SEDAN
t_xl:   .byte <(START_X - 60), <(START_X - 20), <(START_X + 30), <(START_X + 80), <(START_X + 120), <(START_X - 110), <(START_X + 40)
t_xh:   .byte >(START_X - 60), >(START_X - 20), >(START_X + 30), >(START_X + 80), >(START_X + 120), >(START_X - 110), >(START_X + 40)
t_yl:   .byte <START_Y, <(START_Y + 6), <START_Y, <(START_Y + 6), <START_Y, <(START_Y + 4), <LANE_W
t_yh:   .byte >START_Y, >(START_Y + 6), >START_Y, >(START_Y + 6), >START_Y, >(START_Y + 4), >LANE_W
t_ang:  .byte 0, 128, 0, 128, 0, 64, 128
t_beh:  .byte B_WANDER, B_WANDER, B_WANDER, B_WANDER, B_WANDER, B_WANDER, B_IDLE
