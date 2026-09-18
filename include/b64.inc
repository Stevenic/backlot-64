; backlot-64 public include: zero page map, constants, hardware.
; Games assemble against this.  Everything the engine exports is b64_*.

.include "c64.inc"

; ---------------------------------------------------------------------------
; VIC bank 1 layout
; ---------------------------------------------------------------------------
B64_SCREEN_A    = $4000
B64_SCREEN_B    = $4400
B64_CHARSET     = $4800
B64_SPRITES     = $5000
B64_MTCHARS     = $A000         ; 256 metatiles x 16 cell indices
B64_MTCOLS      = $B000         ; 256 metatiles x 16 cell colours
B64_PROPS       = $C000         ; 256 property bytes
B64_COLOR_RAM   = $D800
B64_SPR_PTR_A   = B64_SCREEN_A + $3F8
B64_SPR_PTR_B   = B64_SCREEN_B + $3F8
B64_SPR_PTR_C   = $5C00 + $3F8       ; the cutscene bitmap's colour-cell screen
B64_SPR_BASE    = (B64_SPRITES - $4000) / 64

; REU registers
REU_STATUS      = $DF00
REU_CMD         = $DF01
REU_C64_LO      = $DF02
REU_C64_HI      = $DF03
REU_ADDR_LO     = $DF04
REU_ADDR_HI     = $DF05
REU_BANK        = $DF06
REU_LEN_LO      = $DF07
REU_LEN_HI      = $DF08
REU_IRQ         = $DF09
REU_CTRL        = $DF0A

; Ultimate 64 / C64 Ultimate extras (all optional; see docs/ULTIMATE.md)
B64_TURBO_EN    = $D030         ; bit 0: turbo enable
B64_TURBO_CTRL  = $D031         ; bits 0-3 speed index, bit 7 badlines off; $FF when absent
B64_UA_BASE     = $DF20         ; Ultimate Audio channel 0; channel n at +n*32
B64_UCI_CTRL    = $DF1C         ; command interface control (write) / status (read)
B64_UCI_STATUS  = $DF1C
B64_UCI_CMD     = $DF1D         ; command byte (write) / id $C9 (read)
B64_UCI_ID      = $DF1D
B64_UCI_RESPDATA = $DF1E
B64_UCI_STATDATA = $DF1F

; overlay windows (see src/b64_overlay.s)
B64_OVERLAY_A   = $8000         ; region A, 8 KB
B64_VM_TABLE    = $C900         ; the VM's page-aligned vector table (copied from RODATA at script start)
B64_OVERLAY_B   = $CA00         ; region B, 1.5 KB

; b64_plat bits
B64_PLAT_REU    = $01           ; an REU answers
B64_PLAT_REU16  = $02           ; and it is 16 MB
B64_PLAT_TURBO  = $04           ; $D031 turbo control present
B64_PLAT_AUDIO  = $08           ; Ultimate Audio mapped at $DF20
B64_PLAT_UCI    = $10           ; command interface mapped at $DF1C

; the game heap in the REU: everything above the packed assets
B64_HEAP8       = $600000       ; 8 MB REU: $600000-$7EFFFF (SCRATCH is $7F0000)
B64_HEAP8_END   = $7F0000
B64_HEAP16      = $800000       ; 16 MB REU: the whole upper half
B64_HEAP16_END  = $FF0000       ; $FF0000-$FFFFFF is the size probe's scratch
REU_CMD_FETCH   = $91           ; execute, immediate, REU -> C64
REU_CMD_STASH   = $90           ; execute, immediate, C64 -> REU

; property bits
P_SOLID         = $80
P_WATER         = $40
P_SIDEWALK      = $20
P_DOOR          = $10
P_ROAD_E        = $01
P_ROAD_W        = $02
P_ROAD_S        = $04
P_ROAD_N        = $08

; font: chars 192..255 hold ASCII 32..95.  The c64 target maps 'A'-'Z' to
; PETSCII in string literals; undo that so .byte "TEXT" is ASCII.
B64_FONT_BASE   = 192
.repeat 26, i
.charmap 65 + i, 65 + i
.endrepeat

; the scrolling playfield is rows 0-22; rows 23-24 are the fixed HUD
B64_PLAY_ROWS   = 23

; raster lines
B64_VBLANK_LINE = 255
; HUD split: the IRQ fires on the last line of playfield row 22, which is
; 231 + YSCROLL, and sets YSCROLL to 7 so row 23's badline always lands on
; line 239.  The 0-7 idle lines in between show the idle byte at $7FFF,
; which the engine keeps at 0 (solid background 0).  Games must not use $7FFF.
B64_SPLIT_BASE  = 231
B64_HUD_LINE    = 239
B64_IDLE_BYTE   = $7FFF
; cutscene: the text band starts at row 20 (line 211); the split fires on line 209
B64_CUT_SPLIT   = 209

; ---------------------------------------------------------------------------
; VM p-code.  Scripts are bytes in the REU: an opcode (a doubled index, so the
; byte is the offset into a page-aligned vector table), then its operands.
; They run through the page cache; nothing of a script is resident.
;   v, w   a variable index 0-31 (16-bit unsigned variables shared by all threads)
;   imm    a 16-bit immediate;  n an 8-bit immediate
;   addr   a 16-bit offset from the start of the script (assemble scripts at 0)
;   slot   a 24-bit REU address
; Up to 8 threads run round-robin once per frame, each until it yields or
; spends its instruction budget.  Thread 0 is the script started by
; b64_vm_start; SPAWN starts the others.  The engine opens and closes the
; sprite list around the tick, so a thread that submits sprites just runs
; OBJSPR/SPRITE then YIELD every frame.
; ---------------------------------------------------------------------------
VM_OP_END       = 0            ; stop this thread (thread 0: the scene holds)
VM_OP_WAIT      = 2            ; n: sleep n frames
VM_OP_YIELD     = 4            ; continue next frame
VM_OP_JMP       = 6            ; addr
VM_OP_SPAWN     = 8            ; addr: start a thread there
VM_OP_CALL      = 10           ; addr (two levels deep per thread)
VM_OP_RET       = 12
VM_OP_LOOP      = 14           ; v, addr: v -= 1; jump if v != 0
VM_OP_LDI       = 16           ; v, imm
VM_OP_MOV       = 18           ; v, w: v = w
VM_OP_ADD       = 20           ; v, w: v += w
VM_OP_ADDI      = 22           ; v, imm
VM_OP_SUB       = 24           ; v, w
VM_OP_SUBI      = 26           ; v, imm
VM_OP_AND       = 28           ; v, w
VM_OP_ANDI      = 30           ; v, imm
VM_OP_MIN       = 32           ; v, w: v = min(v, w)
VM_OP_MINI      = 34           ; v, imm
VM_OP_MAX       = 36           ; v, w
VM_OP_MAXI      = 38           ; v, imm
VM_OP_SHR       = 40           ; v, n: v >>= n
VM_OP_SHL       = 42           ; v, n
VM_OP_JLT       = 44           ; v, w, addr: jump if v < w (unsigned)
VM_OP_JLTI      = 46           ; v, imm, addr
VM_OP_JGE       = 48           ; v, w, addr
VM_OP_JGEI      = 50           ; v, imm, addr
VM_OP_JEQ       = 52           ; v, w, addr
VM_OP_JEQI      = 54           ; v, imm, addr
VM_OP_JNE       = 56           ; v, w, addr
VM_OP_JNEI      = 58           ; v, imm, addr
VM_OP_LDT       = 60           ; v, addr, w: v = byte table addr[w & 255]
VM_OP_FRAME     = 62           ; v: v = frame counter
VM_OP_JOY       = 64           ; v: v = joystick 2 bits
; engine primitives (the syscall bridge)
VM_OP_STILL     = 66           ; slot: load a set
VM_OP_OBJECT    = 68           ; slot: load an object
VM_OP_SHIMMER   = 70           ; n: 0 off / 1 on
VM_OP_TEXT      = 72           ; row, col, string, 0
VM_OP_CLEARTEXT = 74
VM_OP_BLIT      = 76           ; slot, cx, cy
VM_OP_RESTORE   = 78           ; cx, cy, w, h
VM_OP_PARK      = 80           ; cx, cy: blocks until the vblank that can do it, then queues it
VM_OP_UNPARK    = 82           ; cx, cy: same
VM_OP_OBJSPR    = 84           ; slot, vx, vy: submit the object's sprite grid at (vx, vy)
VM_OP_OBJANIM   = 86           ; v: the object's animation frame
VM_OP_SPRITE    = 88           ; slot, vx, vy, colour, slot24: submit one sprite
VM_OP_PCM       = 90           ; ch, slot24, len24, rate16, vol, pan: play a sample (Ultimate Audio; no-op elsewhere)
VM_OP_LIGHT     = 92           ; slot24, v: apply lighting state v (2 KB each) of the file at slot at the next base-phase blank
VM_OP_LIGHTS    = 94           ; lightfile24, lamp24, n: n = 1 the engine lights the set from the object's own lights each frame it is drawn; 0 off
VM_OP_COUNT     = 48            ; opcodes are stored doubled: byte = 2 * index into a page-aligned table
; (the constants above are the doubled bytes); script macros: one line per instruction
.macro V_END
        .byte VM_OP_END
.endmacro
.macro V_WAIT n
        .byte VM_OP_WAIT, n
.endmacro
.macro V_YIELD
        .byte VM_OP_YIELD
.endmacro
.macro V_JMP dst
        .byte VM_OP_JMP, <(dst), >(dst)
.endmacro
.macro V_SPAWN dst
        .byte VM_OP_SPAWN, <(dst), >(dst)
.endmacro
.macro V_CALL dst
        .byte VM_OP_CALL, <(dst), >(dst)
.endmacro
.macro V_RET
        .byte VM_OP_RET
.endmacro
.macro V_LOOP v, dst
        .byte VM_OP_LOOP, v, <(dst), >(dst)
.endmacro
.macro V_LDI v, i
        .byte VM_OP_LDI, v, <(i), >(i)
.endmacro
.macro V_MOV v, w
        .byte VM_OP_MOV, v, w
.endmacro
.macro V_ADD v, w
        .byte VM_OP_ADD, v, w
.endmacro
.macro V_ADDI v, i
        .byte VM_OP_ADDI, v, <(i), >(i)
.endmacro
.macro V_SUB v, w
        .byte VM_OP_SUB, v, w
.endmacro
.macro V_SUBI v, i
        .byte VM_OP_SUBI, v, <(i), >(i)
.endmacro
.macro V_AND v, w
        .byte VM_OP_AND, v, w
.endmacro
.macro V_ANDI v, i
        .byte VM_OP_ANDI, v, <(i), >(i)
.endmacro
.macro V_MIN v, w
        .byte VM_OP_MIN, v, w
.endmacro
.macro V_MINI v, i
        .byte VM_OP_MINI, v, <(i), >(i)
.endmacro
.macro V_MAX v, w
        .byte VM_OP_MAX, v, w
.endmacro
.macro V_MAXI v, i
        .byte VM_OP_MAXI, v, <(i), >(i)
.endmacro
.macro V_SHR v, n
        .byte VM_OP_SHR, v, n
.endmacro
.macro V_SHL v, n
        .byte VM_OP_SHL, v, n
.endmacro
.macro V_JLT v, w, dst
        .byte VM_OP_JLT, v, w, <(dst), >(dst)
.endmacro
.macro V_JLTI v, i, dst
        .byte VM_OP_JLTI, v, <(i), >(i), <(dst), >(dst)
.endmacro
.macro V_JGE v, w, dst
        .byte VM_OP_JGE, v, w, <(dst), >(dst)
.endmacro
.macro V_JGEI v, i, dst
        .byte VM_OP_JGEI, v, <(i), >(i), <(dst), >(dst)
.endmacro
.macro V_JEQ v, w, dst
        .byte VM_OP_JEQ, v, w, <(dst), >(dst)
.endmacro
.macro V_JEQI v, i, dst
        .byte VM_OP_JEQI, v, <(i), >(i), <(dst), >(dst)
.endmacro
.macro V_JNE v, w, dst
        .byte VM_OP_JNE, v, w, <(dst), >(dst)
.endmacro
.macro V_JNEI v, i, dst
        .byte VM_OP_JNEI, v, <(i), >(i), <(dst), >(dst)
.endmacro
.macro V_LDT v, t, w
        .byte VM_OP_LDT, v, <(t), >(t), w
.endmacro
.macro V_FRAME v
        .byte VM_OP_FRAME, v
.endmacro
.macro V_JOY v
        .byte VM_OP_JOY, v
.endmacro
.macro V_STILL s
        .byte VM_OP_STILL, <(s), >(s), ^(s)
.endmacro
.macro V_OBJECT s
        .byte VM_OP_OBJECT, <(s), >(s), ^(s)
.endmacro
.macro V_SHIMMER n
        .byte VM_OP_SHIMMER, n
.endmacro
.macro V_TEXT row, col, str
        .byte VM_OP_TEXT, row, col, str, 0
.endmacro
.macro V_CLEARTEXT
        .byte VM_OP_CLEARTEXT
.endmacro
.macro V_BLIT s, cx, cy
        .byte VM_OP_BLIT, <(s), >(s), ^(s), cx, cy
.endmacro
.macro V_RESTORE cx, cy, w, h
        .byte VM_OP_RESTORE, cx, cy, w, h
.endmacro
.macro V_PARK cx, cy
        .byte VM_OP_PARK, cx, cy
.endmacro
.macro V_UNPARK cx, cy
        .byte VM_OP_UNPARK, cx, cy
.endmacro
.macro V_OBJSPR slot, vx, vy
        .byte VM_OP_OBJSPR, slot, vx, vy
.endmacro
.macro V_OBJANIM v
        .byte VM_OP_OBJANIM, v
.endmacro
.macro V_SPRITE slot, vx, vy, colour, s
        .byte VM_OP_SPRITE, slot, vx, vy, colour, <(s), >(s), ^(s)
.endmacro
.macro V_PCM ch, s, len, rate, vol, pan
        .byte VM_OP_PCM, ch, <(s), >(s), ^(s), <(len), >(len), ^(len), <(rate), >(rate), vol, pan
.endmacro
.macro V_LIGHT s, v
        .byte VM_OP_LIGHT, <(s), >(s), ^(s), v
.endmacro
.macro V_LIGHTS f, lamp, n
        .byte VM_OP_LIGHTS, <(f), >(f), ^(f), <(lamp), >(lamp), ^(lamp), n
.endmacro

; ---------------------------------------------------------------------------
; Zero page, engine-owned $02-$53
; ---------------------------------------------------------------------------
b64_cam_x       = $02           ; 16-bit world pixels, camera top-left
b64_cam_y       = $04
b64_ptr         = $06           ; generic pointer / DMA C64 address
b64_reu         = $08           ; 24-bit REU address
b64_len         = $0B           ; 16-bit DMA length
b64_val         = $0D           ; 24-bit scratch value (bench result, numbers)
b64_frame       = $10           ; frame counter, incremented by the engine IRQ
b64_joy         = $11           ; joystick 2 bits, active high: up=1 down=2 left=4 right=8 fire=16
b64_tmp         = $12           ; 8 bytes scratch $12-$19

; scroller state (private to the engine, listed so games can read cam/scroll)
scr_front       = $1A           ; 0 = screen A displayed, 1 = screen B
scr_pending     = $1B           ; bit0: scroll regs pending, bit1: flip + colour work pending
scr_off_lo      = $1C           ; signed 16-bit shift offset dx + 40*dy
scr_off_hi      = $1D
scr_xs          = $1E           ; next XSCROLL
scr_ys          = $1F           ; next YSCROLL
scr_newcol      = $20           ; $FF or column to fill (0 / 39)
scr_newrow      = $21           ; $FF or row to fill (0 / 24)
scr_cx          = $22           ; 16-bit camera char x for the next frame
scr_cy          = $24
scr_ocx         = $26           ; previous frame's camera char x
scr_ocy         = $28
scr_p           = $2A           ; fill pointer (buffer)
scr_q           = $2C           ; fill pointer (metatile lib)
scr_wx          = $2E           ; world char x
scr_wy          = $30           ; world char y
scr_mx          = $32           ; metatile x
scr_my          = $34           ; metatile y
scr_i           = $36
scr_k           = $37
scr_sub         = $38
scr_back_hi     = $39           ; high byte of the back buffer
b64_cb          = $3A           ; game per-frame callback
vm_pc           = $50           ; VM: offset of the running thread within its script, lo
vm_pch          = $51           ; VM: offset hi
vm_page         = $52           ; VM: pointer to the cached page holding the offset (engine ZP ends at $53)
scr_last_frame  = $3C
bench_max       = $3D           ; 3 bytes: worst measured cycles
b64_spr0_frame  = $40           ; pinned sprite 0 frame, written to both buffers on flip

; sprite multiplexer (hardware sprites 1-7 multiplexed; sprite 0 is pinned)
spr_count_b     = $41           ; entries in the list being built
spr_count_s     = $42           ; entries in the list being shown
spr_base_b      = $43           ; 0 or 24: base of the build list in the arrays
spr_base_s      = $44
mux_next        = $45           ; next sorted position to assign during the chain
mux_hw          = $46           ; next hardware sprite to assign, 1-7
b64_spr_flags   = $47           ; b64_spr_add input: bit0 multicolour, bit1 behind playfield
mux_tmp         = $48
irq_line        = $49           ; raster line the next chain IRQ is set for
b64_spr_x       = $4A           ; b64_spr_add input: 16-bit VIC x
b64_spr_y       = $4C           ; b64_spr_add input: VIC y
b64_spr_slot    = $4D           ; b64_spr_add input: sprite slot 1-24 (slot 0 is the pinned sprite)
b64_spr_colour  = $4E           ; b64_spr_add input
mux_tmp2        = $4F

B64_SPR_FLAG_MC   = $01
B64_SPR_FLAG_PRIO = $02
B64_MAX_SPRITES   = 24
B64_SPR_SLOTS     = 25          ; slot 0 pinned + 24 multiplexed; 64 bytes each at B64_SPRITES

; ---------------------------------------------------------------------------
; Macros
; ---------------------------------------------------------------------------
.macro B64_SET16 dst, val
        lda #<(val)
        sta dst
        lda #>(val)
        sta dst+1
.endmacro

.macro B64_SET24 dst, val
        lda #<(val)
        sta dst
        lda #>(val)
        sta dst+1
        lda #^(val)
        sta dst+2
.endmacro

; ---------------------------------------------------------------------------
; Engine entry points
; ---------------------------------------------------------------------------
.global b64_init                ; bank out ROMs, VIC bank 1, clear screens, IRQ
.global b64_set_callback        ; A/X = lo/hi of the game's per-frame routine
.global b64_run                 ; never returns
.global b64_fetch               ; b64_reu, b64_ptr, b64_len: REU -> C64
.global b64_stash               ; b64_reu, b64_ptr, b64_len: C64 -> REU
.global b64_reu_present         ; returns C=1 if an REU answers
.global b64_load_tileset        ; b64_reu = tileset slot address
.global b64_load_sprites        ; b64_reu = sprite bank address
.global b64_move_camera         ; A = dx, X = dy (signed, -8..8)
.global b64_redraw              ; full rebuild from the camera
.global b64_scroll_prepare      ; called by the engine after the callback
.global b64_text                ; A = row, X = col, b64_ptr = ASCII string (0-terminated)
.global b64_number              ; A = row, X = col, b64_val = 16-bit value, 5 digits
.global b64_spr_begin           ; clear this frame's virtual sprite list
.global b64_spr_add             ; b64_spr_x/y/slot/colour/flags, b64_reu = frame source -> list entry
.global b64_spr_pinned          ; b64_reu = frame source for the pinned sprite 0
.global b64_spr_end             ; sort by y; shown from the next vblank
.global b64_cut_begin           ; stash game RAM, switch to the cutscene VIC layout
.global b64_cut_end             ; restore game RAM and the playfield layout
.global b64_cut_still           ; b64_reu = still slot: load the set
.global b64_cut_blit            ; b64_reu = block slot, A = cell x, X = cell y
.global b64_cut_restore         ; A = cell x, X = cell y, Y = w, b64_val = h: restore from the still
.global b64_cut_text            ; A = row 20-24, X = col, b64_val = string
.global b64_cut_clear_text
.global b64_obj_load            ; b64_reu = object slot: header and section addresses
.global b64_obj_sprites         ; b64_spr_x/y = top-left VIC position, X = first slot: submit the grid
.global b64_obj_anim            ; A = frame of the object's animation (wheels); sprites it touches use that frame
.global b64_obj_park            ; A = cell x, X = cell y: blit the object's block at the next vblank
.global b64_obj_unpark          ; A = cell x, X = cell y: restore the still there at the next vblank
.global b64_cut_light           ; b64_reu = a 2 KB lighting state (tools/b64light.py): applied at the next base-phase blank
.global b64_obj_lights          ; b64_reu = baked lighting file, b64_val = lamp frame, A = 1/0: light the set from the object's lights
.global b64_vm_start            ; b64_reu = script base in the REU, A/X = entry offset: kill all threads, run it as thread 0
.global b64_vm_tick             ; once per frame from the game callback: run every ready thread
.global b64_page_get            ; A/X = REU page number lo/hi -> A = high byte of its 256-byte copy in RAM
.global b64_page_flush          ; forget every cached page
.global b64_overlay_load        ; b64_reu = slot, b64_len = length: DMA an overlay into region A unless resident; C = 1 if fetched
.global b64_overlay_reset       ; forget what is resident
.global b64_plat_probe          ; called by b64_init: fills b64_plat, b64_reu_mb, sizes the VM budget and the heap
.global b64_plat                ; B64_PLAT_* bits
.global b64_reu_mb              ; 0, 8 or 16
.global b64_turbo_set           ; A = $D031 value; no-op without the register
.global b64_turbo_fast          ; index 15, badlines off
.global b64_turbo_slow          ; 1 MHz, badlines on: the reference machine
.global b64_heap_alloc          ; b64_val = 24-bit length -> b64_reu, C = 1
.global b64_heap_reset
.global b64_pcm_play            ; X = ch, b64_reu = sample, b64_val = len24, b64_tmp = rate16, +2 vol, +3 pan
.global b64_pcm_loop
.global b64_pcm_stop            ; X = ch
.global b64_pcm_volume          ; X = ch, A = 0-63
.global b64_uci_load            ; b64_ptr = name, b64_reu = address, b64_val = len24: file -> REU, C = 1 ok
.global b64_hud_clear
.global b64_hud_text            ; X = column, b64_val = string pointer
.global b64_hud_number          ; X = column, b64_val = 16-bit value
.global b64_bench_begin
.global b64_bench_end           ; b64_val = elapsed cycles (24-bit)
.global b64_bench_show          ; prints last and max at row 0

; instrumentation: a probe build (-DB64_PROFILE) records events at every
; FTRACE point, samples the program counter each vertical blank, counts
; opcodes and times the tick into a block at $F800 (src/b64_probe.s).
; Without the define every hook is empty.
.macro FTRACE tag
.ifdef B64_PROFILE
        php
        pha
        lda #tag
        jsr probe_event
        pla
        plp
.endif
.endmacro
.macro PROBE_CALL routine
.ifdef B64_PROFILE
        jsr routine
.endif
.endmacro
.ifdef B64_PROFILE
.global probe_event
.global probe_sample
.global probe_tick_begin
.global probe_tick_end
.global probe_init
.global probe_vm_active
.global probe_vm_pc
.global probe_opcount_lo
.global probe_opcount_hi
.endif
