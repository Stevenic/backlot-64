; backlot-64: the VM.  Byte-code threads with 16-bit variables, timers,
; branches, table lookups and a syscall bridge to the engine's primitives.
; Everything a scene or a mission decides is p-code; the engine only
; supplies the per-frame work the p-code asks for.
;
; Scripts live in the REU and run through the page cache.  A thread's
; position is a 16-bit offset from the script base (vm_pch:vm_pc); vm_page
; points at the cached copy of the page the offset is in, and Y is the
; offset's low byte while a thread runs.
;
; Dispatch after Linus Åkesson, Å-machine (src/6502/engine.s fetchnext):
; the opcode byte is a doubled index, fetched with an absolute,Y load whose
; page byte is patched when the page changes, and stored straight into the
; low byte of a jmp (vector) through a page-aligned table.  17 cycles from
; one opcode to the next.  Changed: the budget is charged on taken jumps
; only, since a thread can only run long by jumping back, and the table is
; padded with END so no bounds check is needed.
; Operand fetch after the same source: one indirect load, with the page
; wrap handled per byte on the rare path.  Changed from this VM's first
; version, which copied straddling instructions into a buffer; measured a
; wash in cycles and more code.
; Immediate forms share the register handler through a hidden variable
; (VM_T), a departure from SCUMM v0's parameter bits; measured in
; docs/PRIOR-ART.md.  See CREDITS.md.
;
; Convention inside an op: Y = offset lo, past the opcode.  Read operands
; with FETCH.  Ops that need Y for something else save it with sty vm_pc
; and finish with jmp back.  An op ends with jmp vm_next, or jmp vm_yield
; to give the frame up.

.include "b64.inc"

.import shim_on

.export b64_vm_start
.export b64_vm_tick
.export vm_budget_max

VM_THREADS      = 8
VM_VARS         = 32
VM_T            = 32            ; hidden variable: the immediate of every xxxI opcode

; FETCH: A = next operand byte.  9 cycles on the common path.
.macro FETCH
        lda (vm_page),y
        iny
        bne :+
        jsr vm_wrap
:
.endmacro

.segment "LOWRAM"
vm_lo:          .res VM_VARS+1
vm_hi:          .res VM_VARS+1
th_on:          .res VM_THREADS
th_pclo:        .res VM_THREADS
th_pchi:        .res VM_THREADS
th_wait:        .res VM_THREADS
th_sp:          .res VM_THREADS ; 0, 2, 4
th_stk:         .res VM_THREADS*4
vm_base:        .res 3          ; REU address of the script
vm_cur:         .res 1
vm_budget:      .res 1
vm_budget_max:  .res 1
vm_x:           .res 1
vm_line:        .res 41         ; TEXT copies its string here

.segment "CODE"

; b64_vm_start: b64_reu = script base, A/X = entry offset.  Every thread
; stops; thread 0 starts at the entry.
b64_vm_start:
        sta th_pclo
        stx th_pchi
.ifdef VM_TRACE
        lda #0
        sta $E0FF
.endif
        lda b64_reu
        sta vm_base
        lda b64_reu+1
        sta vm_base+1
        lda b64_reu+2
        sta vm_base+2
        ldx #VM_THREADS-1
        lda #0
@clear: sta th_on,x
        sta th_wait,x
        sta th_sp,x
        dex
        bpl @clear
        lda #1
        sta th_on
        rts

; b64_vm_tick: once per frame.  Sleeping threads count down; ready threads
; run until they yield, wait, end, or spend the jump budget.
b64_vm_tick:
        jsr b64_spr_begin
        ldx #0
@thread:
        stx vm_cur
        lda th_on,x
        beq @next
        lda th_wait,x
        beq @run
        dec th_wait,x
        jmp @next
@run:   lda th_pclo,x
        sta vm_pc
        lda th_pchi,x
        sta vm_pch
        jsr vm_resolve
        lda vm_budget_max
        sta vm_budget
        ldy vm_pc
        jsr vm_exec             ; returns when the thread yields
        ldx vm_cur
        lda vm_pc
        sta th_pclo,x
        lda vm_pch
        sta th_pchi,x
@next:  ldx vm_cur
        inx
        cpx #VM_THREADS
        bcc @thread
        jmp b64_spr_end

; ---------------------------------------------------------------------------
; the dispatch loop.  vm_next and vm_exec: Y = offset lo of the next opcode.
vm_next:
vm_exec:
        lda $C100,y             ; the page byte is patched by vm_resolve
vm_fetch_hi = *-1
        iny
        beq vm_exec_wrap
vm_go:  sta vm_jmp+1            ; doubled opcode = low byte of the vector
vm_jmp: jmp (vm_optab)          ; page-aligned: the high byte never changes
vm_exec_wrap:
        pha
        jsr vm_advance
        pla
        jmp vm_go

; vm_yield: give the frame up with Y = offset lo.  Returns to the tick.
vm_yield:
        sty vm_pc
        rts

; back: an op saved Y in vm_pc and called into the engine
back:   ldy vm_pc
        jmp vm_next

; vm_setpc: A/X = new offset lo/hi.  Charges the budget; a jump within the
; current page keeps vm_page.
vm_setpc:
        sta vm_pc
        cpx vm_pch
        beq @same
        stx vm_pch
        jsr vm_resolve
@same:  dec vm_budget
        beq vm_out
        ldy vm_pc
        jmp vm_next
vm_out: rts                     ; budget spent: vm_pc holds the resume point

; vm_advance: the offset wrapped to the next page.  Y = 0 on exit.
vm_advance:
        inc vm_pch
        ; fall through
; vm_resolve: vm_page = the cached page holding vm_pch, patched into the
; opcode fetch as well.  Clobbers A, X, Y.
vm_resolve:
        lda vm_base+1
        clc
        adc vm_pch
        tay
        lda vm_base+2
        adc #0
        tax
        tya
        jsr b64_page_get
        sta vm_page+1
        sta vm_fetch_hi
        lda #0
        sta vm_page
        tay
        rts

; vm_wrap: called from FETCH on the rare wrap.  Preserves A and X; Y = 0.
vm_wrap:
        pha
        txa
        pha
        jsr vm_advance
        pla
        tax
        pla
        rts

; vm_repage: after a page-cache lookup that may have evicted our page.
; Y (the offset lo) is preserved.
vm_repage:
        sty vm_pc
        jsr vm_resolve
        ldy vm_pc
        rts

; ---------------------------------------------------------------------------
; control
op_end:
        ldx vm_cur
        lda #0
        sta th_on,x
        jmp vm_yield
op_yield:
        jmp vm_yield
op_wait:
        FETCH
        ldx vm_cur
        sta th_wait,x
        jmp vm_yield
op_jmp:
take:   FETCH
        sta b64_tmp
        FETCH
        tax
        lda b64_tmp
        jmp vm_setpc
skip2:  iny
        bne :+
        jsr vm_wrap
:       iny
        bne :+
        jsr vm_wrap
:       jmp vm_next
op_spawn:
        FETCH
        sta b64_val
        FETCH
        sta b64_val+1
        ldx #1
@find:  lda th_on,x
        beq @got
        inx
        cpx #VM_THREADS
        bcc @find
        jmp vm_next             ; no free thread: dropped
@got:   lda b64_val
        sta th_pclo,x
        lda b64_val+1
        sta th_pchi,x
        lda #0
        sta th_wait,x
        sta th_sp,x
        lda #1
        sta th_on,x
        jmp vm_next
op_call:
        FETCH
        sta b64_val
        FETCH
        sta b64_val+1
        ; the return offset is Y in page vm_pch
        sty b64_tmp+1
        lda vm_pch
        sta b64_tmp
        ldx vm_cur
        lda th_sp,x
        cmp #4
        bcs @go                 ; too deep: jump without a return
        jsr stack_index
        lda b64_tmp+1
        sta th_stk,y
        lda b64_tmp
        sta th_stk+1,y
        inc th_sp,x
        inc th_sp,x
@go:    lda b64_val
        ldx b64_val+1
        jmp vm_setpc
op_ret:
        ldx vm_cur
        lda th_sp,x
        beq @none
        dec th_sp,x
        dec th_sp,x
        jsr stack_index
        lda th_stk,y
        ldx th_stk+1,y
        jmp vm_setpc
@none:  jmp vm_next
; stack_index: X = thread -> Y = thread*4 + sp
stack_index:
        txa
        asl
        asl
        clc
        adc th_sp,x
        tay
        rts
op_loop:
        FETCH
        tax
        lda vm_lo,x
        bne :+
        dec vm_hi,x
:       dec vm_lo,x
        lda vm_lo,x
        ora vm_hi,x
        beq @out
        jmp take
@out:   jmp skip2

; ---------------------------------------------------------------------------
; data.  Register forms take X = v, Y = w with the offset saved in vm_pc;
; immediate forms load the hidden variable T and share the register code.

; VW: v -> X, w -> Y; the offset is saved
.macro VW
        FETCH
        sta vm_x
        FETCH
        sty vm_pc
        tay
        ldx vm_x
.endmacro
; VI: v -> X, imm -> T, Y = T; the offset is saved
.macro VI
        FETCH
        sta vm_x
        FETCH
        sta vm_lo+VM_T
        FETCH
        sta vm_hi+VM_T
        sty vm_pc
        ldx vm_x
        ldy #VM_T
.endmacro

op_ldi:
        VI
mov_xy: lda vm_lo,y
        sta vm_lo,x
        lda vm_hi,y
        sta vm_hi,x
        jmp back
op_mov:
        VW
        jmp mov_xy
op_addi:
        VI
        jmp add_xy
op_add:
        VW
add_xy: clc
        lda vm_lo,x
        adc vm_lo,y
        sta vm_lo,x
        lda vm_hi,x
        adc vm_hi,y
        sta vm_hi,x
        jmp back
op_subi:
        VI
        jmp sub_xy
op_sub:
        VW
sub_xy: sec
        lda vm_lo,x
        sbc vm_lo,y
        sta vm_lo,x
        lda vm_hi,x
        sbc vm_hi,y
        sta vm_hi,x
        jmp back
op_andi:
        VI
        jmp and_xy
op_and:
        VW
and_xy: lda vm_lo,x
        and vm_lo,y
        sta vm_lo,x
        lda vm_hi,x
        and vm_hi,y
        sta vm_hi,x
        jmp back
op_mini:
        VI
        jmp min_xy
op_min:
        VW
min_xy: jsr cmp_xy
        bcc @keep
        jmp mov_xy              ; v >= w: v = w
@keep:  jmp back
op_maxi:
        VI
        jmp max_xy
op_max:
        VW
max_xy: jsr cmp_xy
        bcs @keep
        jmp mov_xy              ; v < w: v = w
@keep:  jmp back
op_shr:
        VW
        cpy #0
        bne @l
        jmp back
@l:     lsr vm_hi,x
        ror vm_lo,x
        dey
        bne @l
        jmp back
op_shl:
        VW
        cpy #0
        bne @l
        jmp back
@l:     asl vm_lo,x
        rol vm_hi,x
        dey
        bne @l
        jmp back
; cmp_xy: C = (v >= w), Z = (v == w), unsigned 16-bit
cmp_xy: lda vm_hi,x
        cmp vm_hi,y
        bne :+
        lda vm_lo,x
        cmp vm_lo,y
:       rts

; branches: after the compare, Y = offset of the address operand
op_jlti:
        VI
        jmp jlt_xy
op_jlt:
        VW
jlt_xy: jsr cmp_xy
        php                     ; ldy would clobber the flags
        ldy vm_pc
        plp
        bcc @t
        jmp skip2
@t:     jmp take
op_jgei:
        VI
        jmp jge_xy
op_jge:
        VW
jge_xy: jsr cmp_xy
        php
        ldy vm_pc
        plp
        bcs @t
        jmp skip2
@t:     jmp take
op_jeqi:
        VI
        jmp jeq_xy
op_jeq:
        VW
jeq_xy: jsr cmp_xy
        php
        ldy vm_pc
        plp
        beq @t
        jmp skip2
@t:     jmp take
op_jnei:
        VI
        jmp jne_xy
op_jne:
        VW
jne_xy: jsr cmp_xy
        php
        ldy vm_pc
        plp
        bne @t
        jmp skip2
@t:     jmp take

; LDT v, addr, w: v = byte at script offset addr + w
op_ldt:
        FETCH
        sta vm_x
        FETCH
        sta b64_val
        FETCH
        sta b64_val+1
        FETCH
        sty vm_pc
        tax
        lda vm_lo,x
        clc
        adc b64_val
        sta b64_val
        lda vm_hi,x
        adc b64_val+1
        clc
        adc vm_base+1
        tay
        lda vm_base+2
        adc #0
        tax
        tya
        jsr b64_page_get
        sta b64_ptr+1
        lda #0
        sta b64_ptr
        ldy b64_val
        lda (b64_ptr),y
        ldx vm_x
        jsr set_byte
        ldy vm_pc
        jsr vm_repage           ; the lookup may have replaced our page
        jmp vm_next
set_byte:
        sta vm_lo,x
        lda #0
        sta vm_hi,x
        rts
op_frame:
        FETCH
        tax
        lda b64_frame
        jsr set_byte
        jmp vm_next
op_joy:
        FETCH
        tax
        lda b64_joy
        jsr set_byte
        jmp vm_next

; ---------------------------------------------------------------------------
; syscalls.  The offset is saved before calling into the engine.
.macro SLOT
        FETCH
        sta b64_reu
        FETCH
        sta b64_reu+1
        FETCH
        sta b64_reu+2
.endmacro

op_still:
        SLOT
        sty vm_pc
        jsr b64_cut_still
        jmp back
op_object:
        SLOT
        sty vm_pc
        jsr b64_obj_load
        jmp back
op_shimmer:
        FETCH
        sta shim_on
        jmp vm_next
op_text:
        FETCH
        pha                     ; row
        FETCH
        sta vm_x                ; column
        ldx #0
@copy:  FETCH
        sta vm_line,x
        cmp #0
        beq @end
        inx
        cpx #40
        bne @copy
        lda #0
        sta vm_line,x
:       FETCH                   ; skip the rest of an overlong string
        cmp #0
        bne :-
@end:   sty vm_pc
        lda #<vm_line
        sta b64_val
        lda #>vm_line
        sta b64_val+1
        ldx vm_x
        pla
        jsr b64_cut_text
        jmp back
op_cleartext:
        sty vm_pc
        jsr b64_cut_clear_text
        jmp back
op_blit:
        SLOT
        FETCH
        sta b64_tmp
        FETCH
        tax
        sty vm_pc
        lda b64_tmp
        jsr b64_cut_blit
        jmp back
op_restore:
        FETCH
        sta b64_tmp
        FETCH
        sta b64_tmp+1
        FETCH
        sta b64_tmp+2
        FETCH
        sta b64_val
        sty vm_pc
        lda b64_tmp
        ldx b64_tmp+1
        ldy b64_tmp+2
        jsr b64_cut_restore
        jmp back
; park and unpark wait for a frame whose vblank is in the shimmer's base
; phase, so the block and the still it was composited on agree.  Until then
; the opcode re-runs next frame.
op_park:
        jsr park_phase
        bcs park_retry
        FETCH
        sta b64_tmp
        FETCH
        tax
        sty vm_pc
        lda b64_tmp
        jsr b64_obj_park
        jmp back
; back to the opcode (Y is one past it, possibly across a page)
park_retry:
        tya
        sec
        sbc #1
        sta vm_pc
        bcs :+
        dec vm_pch
:       rts
op_unpark:
        jsr park_phase
        bcs park_retry
        FETCH
        sta b64_tmp
        FETCH
        tax
        sty vm_pc
        lda b64_tmp
        jsr b64_obj_unpark
        jmp back
; C = 1 if this frame's vblank is not the right phase
park_phase:
        lda b64_frame
        clc
        adc #1
        and #4
        beq @ok
        sec
        rts
@ok:    clc
        rts
op_objspr:
        FETCH
        sta vm_x
        jsr spr_xy
        ldx vm_x
        jsr b64_obj_sprites
        jmp back
op_objanim:
        FETCH
        tax
        lda vm_lo,x
        jsr b64_obj_anim
        jmp vm_next
op_sprite:
        FETCH
        sta b64_spr_slot
        jsr spr_xy
        ldy vm_pc
        FETCH
        sta b64_spr_colour
        SLOT
        sty vm_pc
        lda #0
        sta b64_spr_flags
        jsr b64_spr_add
        jmp back
; PCM ch, slot24, len24, rate16, vol, pan
op_pcm:
        FETCH
        sta vm_x
        SLOT
        FETCH
        sta b64_val
        FETCH
        sta b64_val+1
        FETCH
        sta b64_val+2
        FETCH
        sta b64_tmp
        FETCH
        sta b64_tmp+1
        FETCH
        sta b64_tmp+2
        FETCH
        sta b64_tmp+3
        sty vm_pc
        ldx vm_x
        jsr b64_pcm_play
        jmp back
; spr_xy: operands vx, vy -> b64_spr_x/y; the offset is saved
spr_xy:
        FETCH
        tax
        lda vm_lo,x
        sta b64_spr_x
        lda vm_hi,x
        sta b64_spr_x+1
        FETCH
        tax
        sty vm_pc
        lda vm_lo,x
        sta b64_spr_y
        rts

; ---------------------------------------------------------------------------
; the vector table: 128 words on a page boundary, indexed by the doubled
; opcode byte; unused entries are END
.segment "VMTAB"
vm_optab:
        .word op_end, op_wait, op_yield, op_jmp, op_spawn, op_call, op_ret, op_loop
        .word op_ldi, op_mov, op_add, op_addi, op_sub, op_subi, op_and, op_andi
        .word op_min, op_mini, op_max, op_maxi, op_shr, op_shl
        .word op_jlt, op_jlti, op_jge, op_jgei, op_jeq, op_jeqi, op_jne, op_jnei
        .word op_ldt, op_frame, op_joy
        .word op_still, op_object, op_shimmer, op_text, op_cleartext, op_blit, op_restore
        .word op_park, op_unpark, op_objspr, op_objanim, op_sprite, op_pcm
.repeat 128-VM_OP_COUNT
        .word op_end
.endrepeat
