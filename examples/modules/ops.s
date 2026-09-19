; backlot-64 example: the game's own module, the handlers of its two game
; opcodes (docs/MODULES.md section 9).
;
; A game opcode (80-127) is the game's, not the engine's: the manifest's op
; lines name the module and the entry of its jump table that serves each,
; and the VM loads the module the first time one runs.  A compiler would
; emit modules like this one from the hot spans of a game's scripts; this
; one is written by hand.  It runs at $3800, in the top half of the game's
; resident area, and reads the physics module's body tables at $7A00 (they
; stay when the physics module is swapped).
;
; A handler is entered with Y = the script offset past its opcode.  It
; reads operands with VM_FETCH (these two have none), saves Y in vm_pc
; before it calls into the engine, and leaves by jmp vm_back (Y from vm_pc)
; or vm_next (Y as it is), or jmp vm_yield to give up the frame.

.include "b64.inc"
.include "slots.inc"
.include "../../modules/physics/physics.inc"
.include "physics_syms.inc"

.segment "OVERLAY"
        jmp op_draw             ; entry 0: DRAW
        jmp op_show             ; entry 1: SHOW

; DRAW: every body on screen onto the multiplexer, walkers stepping every
; 8 pixels, cars at their heading
op_draw:
        sty vm_pc
        ldx #PHYS_NB-1
@b:     lda pb_mov,x
        beq @n
        stx cur
        jsr body
        ldx cur
@n:     dex
        bpl @b
        jmp vm_back

; body: X = a body -> onto the multiplexer if it is on screen
body:   lda pb_xl,x             ; sprite x = x - camera x + 12
        sec
        sbc b64_cam_x
        sta b64_spr_x
        lda pb_xh,x
        sbc b64_cam_x+1
        sta b64_spr_x+1
        lda b64_spr_x
        clc
        adc #12
        sta b64_spr_x
        lda b64_spr_x+1
        adc #0
        sta b64_spr_x+1
        beq @xok
        cmp #1
        bne @off
        lda b64_spr_x
        cmp #<344
        bcs @off
@xok:   lda pb_yl,x             ; sprite y = y - camera y + 40
        sec
        sbc b64_cam_y
        tay
        lda pb_yh,x
        sbc b64_cam_y+1
        bne @off
        tya
        clc
        adc #40
        bcs @off
        cmp #30
        bcc @off
        cmp #250
        bcs @off
        sta b64_spr_y
        lda colour,x
        sta b64_spr_colour
        inx
        stx b64_spr_slot        ; slots 1-12, the body's own
        dex
        lda #B64_SPR_FLAG_MC
        sta b64_spr_flags
        lda pb_mov,x
        cmp #M_FOOT
        bne @car
        lda pb_xl,x             ; a walker: the step, every 8 pixels walked
        eor pb_yl,x
        and #8
        beq :+
        lda #64
:       clc
        adc #<(SLOT_SPRITES0 + 4 * 64)
        sta b64_reu
        lda #>(SLOT_SPRITES0 + 4 * 64)
        adc #0
        sta b64_reu+1
        lda #^(SLOT_SPRITES0 + 4 * 64)
        adc #0
        sta b64_reu+2
        jmp b64_spr_add
@car:   lda pb_ang,x            ; a car: one of 16 headings, 64 bytes each
        clc
        adc #8
        lsr a
        lsr a
        lsr a
        lsr a
        tay
        lda h_lo,y
        clc
        adc #<SLOT_CARS16
        sta b64_reu
        lda h_hi,y
        adc #>SLOT_CARS16
        sta b64_reu+1
        lda #^SLOT_CARS16
        adc #0
        sta b64_reu+2
        jmp b64_spr_add
@off:   rts

; SHOW: the status row: which module provides each interface
op_show:
        sty vm_pc
        ldx #39
        lda #' '
:       sta line,x
        dex
        bpl :-
        lda #0
        sta line+40
        lda #IF_PHYS            ; the physics: which of the three
        jsr b64_mod_find
        ldy #0
        bcc :+
        txa
        tay
:       tya
        asl a
        asl a
        asl a
        tay                     ; 8 characters a name
        ldx #0
:       lda phys_names,y
        sta line,x
        iny
        inx
        cpx #8
        bne :-
        ldy #0                  ; then the rest, each there or not
@if:    sty cur
        lda if_ids,y
        jsr b64_mod_find
        ldy cur
        bcc @nx
        lda if_col,y
        tax
        tya
        asl a
        asl a
        tay
        lda if_names,y
        sta line,x
        lda if_names+1,y
        sta line+1,x
        lda if_names+2,y
        sta line+2,x
        lda if_names+3,y
        sta line+3,x
        ldy cur
@nx:    iny
        cpy #3
        bne @if
        lda #<line
        sta b64_val
        lda #>line
        sta b64_val+1
        ldx #0
        jsr b64_hud_text
        jmp vm_back

phys_names:
        .byte "PHYS -- "            ; none
        .byte "GROUND  ", "WATER   ", "AIR     "
if_ids:   .byte IF_COL, IF_AI, IF_DEMO
if_col:   .byte 9, 14, 18
if_names: .byte "COL ", "AI  ", "OPS "
h_lo:   .repeat 16, i
        .byte <(i * 64)
        .endrepeat
h_hi:   .repeat 16, i
        .byte >(i * 64)
        .endrepeat
colour: .byte 4, 3, 8, 10, 7, 14, 2, 5, 6, 12, 13, 15

.assert MOD_PHYS_GROUND = 1 && MOD_PHYS_WATER = 2 && MOD_PHYS_AIR = 3, error, "phys_names follows the manifest's order"

cur:    .res 1
line:   .res 41
