; backlot-64 sprite multiplexer.
;
; Hardware sprite 0 can be pinned for the one object that must never
; flicker (b64_spr_pinned; mux_first = 1); the other hardware sprites are
; multiplexed over up to 24 virtual sprites.  The game builds a list each
; frame with b64_spr_begin, b64_spr_add and b64_spr_end.
;
; b64_spr_end decides, in the main loop:
;  1. Sort.  The order survives from frame to frame and is re-sorted by y
;     with an insertion sort, which costs little when the game submits its
;     entities in the same order every frame and they move a few lines at
;     a time.  A change in the count starts again from submission order.
;  2. Allocate.  In y order each entry takes the hardware sprite freed
;     longest ago (round robin: every sprite is 21 lines tall).  If that
;     sprite's previous occupant ends too close to the entry's top for an
;     interrupt to move it in time, the entry is dropped, whole: a ninth
;     sprite on a line never cuts another short.
;  3. Group.  Consecutive entries share one raster interrupt while all of
;     their previous occupants end early enough to write every one of them
;     before the first is due.
; The interrupts copy: each accepted entry is one index byte, and a group
; runs through one routine per hardware sprite with that sprite's
; registers built in, each chaining to the next sprite's routine.  The
; routines are generated at start into the free RAM above the sprite slots
; (mux_gen), so the resident engine holds one template.  A chain interrupt
; that finds the next group already due runs it at once.
;
; After Lasse Öörni (Cadaver), c64gameframework (screen.s UF_SortLoop,
; raster.s, aligneddata.s sprIrqAdvanceTbl): the persistent sort order,
; grouped interrupts, running the next group directly when late, and
; ninth-sprite rejection.  Changed: the order is re-sorted every frame from
; the last one rather than fully sorted only when the count changes; groups
; are formed from when each previous occupant ends rather than from a
; fixed five-line window with an advance table; rejection and grouping are
; decided in the main loop; and the interrupt code is generated per
; hardware sprite into RAM outside the engine.  Measured against this
; engine's previous multiplexer in docs/JOURNAL.md; not against the source.

.include "b64.inc"

.export b64_spr_vblank
.export mux_chain
.export mux_schedule
.export spr_slots_reset
.export spr_init
.export spr_limit
.export spr_ready
.export mux_first
.export mux_rout, spr_rejected, mux_b_y, mux_acc   ; for the checks
mux_rout        = ROUT
.ifndef B64_PROFILE
.export mux_irq, mux_irq_rti
.endif
mux_b_y         = b_y
mux_acc         = acc
.import split_done
.import split_line
.import cut_active
.import b64_irq                 ; the general interrupt handler

LEAD_BASE       = 3             ; lines from a group's interrupt to its first write, with slack

; the multiplexer's RAM above the 25 sprite slots (B64_MUXTAB): two halves
; of B64_MAX_SPRITES entries each, the build half and the shown half
N2              = 2*B64_MAX_SPRITES
M               = B64_MUXTAB
b_xlo           = M             ; per entry, in submission order
b_xhi           = M + N2
b_y             = M + 2*N2
b_ptr           = M + 3*N2      ; the sprite pointer: slot + B64_SPR_BASE
b_col           = M + 4*N2
b_flg           = M + 5*N2
acc             = M + 6*N2      ; per accepted entry, in y order: its entry index
g_line          = M + 7*N2      ; per group: the raster line of its interrupt; 255 after the last
g_pos           = M + 8*N2      ; per group: the list position of its first entry
g_cnt           = M + 9*N2      ; per group: its entries
rr_lo           = M + 10*N2     ; per list position: the routine for its hardware sprite
rr_hi           = M + 11*N2
rr_bit          = M + 12*N2     ; per list position: that sprite's bit
.assert M + 13*N2 + 1 <= ROUT, error, "the multiplexer's tables run into its routines"
ROUT            = $5A00         ; 8 generated routines, 64 bytes apart, on a page
.assert ROUT + 8*64 <= B64_MUXTAB_END, error, "multiplexer RAM overflows its area"
.assert (ROUT & $FF) = 0, error, "mux_gen assumes the routines start on a page"

; the allocation loop's state lives in the shared zero-page scratch
A_LIM   = b64_tmp               ; the current group can take an entry that comes free by this line
A_GX    = b64_tmp+1             ; the current group's index (list half base + group)
A_Y     = b64_tmp+2             ; the entry's y
A_POS   = b64_tmp+3             ; sorted position
A_HW    = b64_tmp+4             ; the hardware sprite next in turn
A_FREE  = b64_tmp+5             ; the line that sprite comes free (0 = first use)
A_OUT   = b64_tmp+6             ; the list position the next accepted entry takes

; offsets in the routine template
T_Y     = 7                     ; low byte of sta VIC_SPR0_Y + 2h
T_X     = 13
T_COL   = 19
T_PTR   = 25                    ; low byte of the pointer store; +1 is aimed at the shown screen
T_CLR   = 35                    ; and #~bit
T_SET   = 39                    ; ora #bit
T_NEXT  = 49                    ; jmp to the next sprite's routine
T_LEN   = 52

.segment "LOWRAM"
spr_ready:      .res 1          ; 1 = a finished list waits for the next vblank
spr_limit:      .res 1          ; entries b64_spr_add accepts a frame: set by the platform probe
ord:            .res B64_MAX_SPRITES    ; sorted order (entries 0..n-1), kept from frame to frame
ord_n:          .res 1          ; the count the order was built for
free_at:        .res 8          ; per hardware sprite: the first line after its occupant is shown
slot_lo:        .res B64_SPR_SLOTS      ; per slot: the REU address it holds
slot_hi:        .res B64_SPR_SLOTS
slot_bk:        .res B64_SPR_SLOTS
mux_first:      .res 1          ; first hardware sprite the multiplexer may use: 1 (sprite 0 pinned) or 0
hw_count:       .res 1          ; 8 - mux_first
rr_first:       .res 1          ; mux_first the routines were generated for ($FF = never)
flg_or:         .res 1          ; flags of the list being built, ORed and ANDed
flg_and:        .res 1
bld_n:          .res 1          ; the finished list: entries accepted, groups, $D015,
bld_g:          .res 1          ; entries dropped, and whether every entry shares one
bld_ena:        .res 1          ; set of flags (then $D01C/$D01B are written once)
bld_rej:        .res 1
bld_same:       .res 1
shw_ena:        .res 1
shw_same:       .res 1
spr_rejected:   .res 1          ; entries dropped from the list being shown (for the checks)
pin_mask:       .res 1          ; the register bits the multiplexer leaves alone
cur_hw:         .res 1          ; allocation state in b64_spr_end
grp:            .res 1
grp_y:          .res 1
grp_n:          .res 1

.segment "RODATA"
bit_set:        .byte $01, $02, $04, $08, $10, $20, $40, $80
; masks[k] = 2^k - 1 for k hardware sprites in use (0..8)
ena_mask:       .byte $00, $01, $03, $07, $0F, $1F, $3F, $7F, $FF
; one entry into one hardware sprite: X = list position, mux_cnt = entries
; left in the group.  mux_gen copies it once per sprite and fills in the
; bytes marked with T_ offsets.
template:
        ldy acc,x               ; +0
        lda b_y,y               ; +3
        sta VIC_SPR0_Y          ; +6   T_Y
        lda b_xlo,y             ; +9
        sta VIC_SPR0_X          ; +12  T_X
        lda b_col,y             ; +15
        sta VIC_SPR0_COLOR      ; +18  T_COL
        lda b_ptr,y             ; +21
        sta B64_SPR_PTR_A       ; +24  T_PTR
        lda b_xhi,y             ; +27
        lsr                     ; +30
        lda VIC_SPR_HI_X        ; +31
        and #$FF                ; +34  T_CLR
        bcc :+                  ; +36
        ora #$00                ; +38  T_SET
:       sta VIC_SPR_HI_X        ; +40
        inx                     ; +43
        dec mux_cnt             ; +44
        beq :+                  ; +46
        jmp ROUT                ; +48  T_NEXT
:       rts                     ; +51
template_end:
.assert template_end - template = T_LEN, error, "template offsets are stale"

.segment "CODE"

; ---------------------------------------------------------------------------
b64_spr_begin:
        FTRACE 4
:       lda spr_ready           ; the previous list must be taken first
        bne :-
        FTRACE 5
        sta spr_count_b
        sta flg_or
        lda #$FF
        sta flg_and
        rts

b64_spr_add:
        ldx spr_count_b
        cpx spr_limit
        bcs @full
        ldx b64_spr_slot
        cpx #B64_SPR_SLOTS
        bcs @full               ; no such slot: refuse rather than write past the table
        inc spr_count_b
        jsr slot_load
        lda spr_count_b
        clc
        adc spr_base_b
        tax
        dex
        lda b64_spr_x
        sta b_xlo,x
        lda b64_spr_x+1
        sta b_xhi,x
        lda b64_spr_y
        sta b_y,x
        lda b64_spr_slot
        clc
        adc #B64_SPR_BASE
        sta b_ptr,x
        lda b64_spr_colour
        sta b_col,x
        lda b64_spr_flags
        sta b_flg,x
        ora flg_or
        sta flg_or
        lda b64_spr_flags
        and flg_and
        sta flg_and
@full:  rts

; spr_init: at start.  The routines are generated by the first b64_spr_end.
spr_init:
        lda #$FF
        sta rr_first
        lda #B64_SPR_STOCK
        sta spr_limit
; forget every slot's contents so the next add fetches; empty lists
spr_slots_reset:
        lda #0
        sta g_cnt               ; both halves: an empty group 0, then the end
        sta g_cnt+B64_MAX_SPRITES
        sta shw_ena
        lda #255
        sta g_line+1
        sta g_line+B64_MAX_SPRITES+1
        lda #0
        sta spr_ready
        sta ord_n
        sta bld_n
        sta bld_g
        sta spr_count_s
        sta spr_rejected
        lda #$FF
        ldx #B64_SPR_SLOTS-1
:       sta slot_lo,x
        sta slot_hi,x
        sta slot_bk,x
        dex
        bpl :-
        rts

; b64_spr_pinned: b64_reu = frame source for hardware sprite 0 (slot 0)
b64_spr_pinned:
        ldx #0
        jsr slot_load
        lda #0
        sta b64_spr0_frame
        rts

; slot_load: X = slot, b64_reu = frame address.  Fetches 64 bytes into the
; slot's VIC RAM if the address differs from what the slot holds.
slot_load:
        lda b64_reu
        cmp slot_lo,x
        bne @load
        lda b64_reu+1
        cmp slot_hi,x
        bne @load
        lda b64_reu+2
        cmp slot_bk,x
        bne @load
        rts
@load:  FTRACE 12
        lda b64_reu
        sta slot_lo,x
        lda b64_reu+1
        sta slot_hi,x
        lda b64_reu+2
        sta slot_bk,x
        ; C64 address = B64_SPRITES + slot*64
        txa
        lsr
        lsr
        clc
        adc #>B64_SPRITES
        sta b64_ptr+1
        txa
        and #3
        asl
        asl
        asl
        asl
        asl
        asl                     ; (slot & 3) << 6
        sta b64_ptr
        lda #64
        sta b64_len
        lda #0
        sta b64_len+1
        jmp b64_fetch

; ---------------------------------------------------------------------------
; mux_gen: the routine for every hardware sprite from the template, each
; jumping to the next sprite's, the last back to mux_first's; and per list
; position, which routine and which bit.  Runs when mux_first changes.
; Uses b64_tmp+0..+3.
mux_gen:
        lda mux_first
        sta rr_first
        lda #8
        sec
        sbc mux_first
        sta hw_count
        lda #<ROUT
        sta b64_tmp
        lda #>ROUT
        sta b64_tmp+1
        ldx #0                  ; hardware sprite
@spr:   ldy #T_LEN-1
:       lda template,y
        sta (b64_tmp),y
        dey
        bpl :-
        txa
        asl
        ldy #T_X
        sta (b64_tmp),y         ; $D000 + 2h
        ora #1
        ldy #T_Y
        sta (b64_tmp),y         ; $D001 + 2h
        txa
        clc
        adc #<VIC_SPR0_COLOR
        ldy #T_COL
        sta (b64_tmp),y
        txa
        clc
        adc #<B64_SPR_PTR_A
        ldy #T_PTR
        sta (b64_tmp),y
        lda bit_set,x
        ldy #T_SET
        sta (b64_tmp),y
        eor #$FF
        ldy #T_CLR
        sta (b64_tmp),y
        ; the next sprite's routine: 64 bytes on, or back to the first
        ldy #T_NEXT
        lda b64_tmp
        clc
        adc #64
        sta b64_tmp+2
        lda b64_tmp+1
        adc #0
        sta b64_tmp+3
        cpx #7
        bne :+
        lda mux_first           ; the last wraps to mux_first's routine
        asl
        asl
        asl
        asl
        asl
        asl
        clc
        adc #<ROUT
        sta b64_tmp+2
        lda #>ROUT
        adc #0
        sta b64_tmp+3
:       lda b64_tmp+2
        sta (b64_tmp),y
        iny
        lda b64_tmp+3
        sta (b64_tmp),y
        lda b64_tmp
        clc
        adc #64
        sta b64_tmp
        bcc :+
        inc b64_tmp+1
:       inx
        cpx #8
        bne @spr
        ; per list position: routine and bit, both halves
        ldx #0
@half:  ldy mux_first
@pos:   tya                     ; routine = ROUT + 64h: (h & 3) * 64 low, h / 4 high
        and #3
        lsr
        ror
        ror                     ; (h & 3) << 6
        sta rr_lo,x
        tya
        lsr
        lsr
        clc
        adc #>ROUT
        sta rr_hi,x
        lda bit_set,y
        sta rr_bit,x
        inx
        cpx #B64_MAX_SPRITES
        beq @half               ; the second half starts the turn again
        cpx #N2
        beq @done
        iny
        cpy #8
        bne @pos
        beq @half
@done:  rts

; ---------------------------------------------------------------------------
; b64_spr_end: sort, allocate, reject and group.  Uses b64_tmp+0..+7.
b64_spr_end:
        FTRACE 10
        lda mux_first
        cmp rr_first
        beq :+
        jsr mux_gen
:       lda #0
        sta bld_g
        sta bld_rej
        ; the build half's y column, for the sort and the allocation below
        lda #<b_y
        clc
        adc spr_base_b
        sta @ky+1
        sta @py+1
        sta @ey+1
        lda #>b_y
        adc #0
        sta @ky+2
        sta @py+2
        sta @ey+2
        ldx spr_count_b
        bne :+
        jmp @empty
:       ; 1. the order: kept, unless the count changed
        cpx ord_n
        beq @sort
        stx ord_n
        dex
:       txa
        sta ord,x
        dex
        bpl :-
@sort:  ldx #1
@outer: cpx spr_count_b
        bcs @sorted
        lda ord,x
        sta b64_tmp             ; key
        tay
@ky:    lda b_y,y
        sta b64_tmp+1           ; key y
        stx b64_tmp+2           ; i
@inner: ldy ord-1,x
@py:    lda b_y,y
        cmp b64_tmp+1
        bcc @place              ; ord[j-1] < key: stays
        beq @place              ; equal: stays, the sort is stable
        tya
        sta ord,x
        dex
        bne @inner
@place: lda b64_tmp
        sta ord,x
        ldx b64_tmp+2
        inx
        jmp @outer
@sorted:
        ; 2-3. allocate, reject, group
        lda flg_or
        cmp flg_and
        beq :+
        lda #0
        beq :++
:       lda #1
:       sta bld_same
        lda mux_first
        sta A_HW
        ldx #7
        lda #0
:       sta free_at,x
        dex
        bpl :-
        sta grp
        ldx spr_base_b
        stx A_OUT
        stx A_GX                ; group 0: every sprite's first entry
        sta g_cnt,x
        txa
        sta g_pos,x
        ldx #0
@each:  stx A_POS
        ldy ord,x               ; Y = the entry, 0..n-1
@ey:    lda b_y,y
        sta A_Y
        ldx A_HW
        lda free_at,x
        sta A_FREE              ; the line its hardware sprite comes free: 0 = never used
        beq @first
        clc
        adc #LEAD_BASE+1
        bcs @reject             ; past line 255: nothing more fits on this sprite
        cmp A_Y
        bcc @accept             ; free + lead <= y: an interrupt can move it in time
        beq @accept
@reject:
        inc bld_rej
        jmp @next
@first: ; the sprite's first use this frame: group 0, written in the blank
        tya
        clc
        adc spr_base_b
        ldy A_OUT
        sta acc,y
        lda A_Y
        clc
        adc #22                 ; shown on lines y+1..y+21: free from y+22
        sta free_at,x
        ldx spr_base_b
        inc g_cnt,x
        jmp @gend
@accept:
        tya
        clc
        adc spr_base_b
        ldy A_OUT
        sta acc,y               ; list position -> entry
        lda A_Y                 ; the new occupant is shown on lines y+1..y+21: free from y+22
        clc
        adc #22
        bcc :+
        lda #255
:       sta free_at,x
        ; join the current group if it can still write this one in time for
        ; its first entry, else start a new group
        lda grp
        beq @newgrp             ; still in group 0: the first reuse starts group 1
        lda A_FREE
        cmp A_LIM
        beq :+
        bcs @newgrp             ; comes free too late for this group
:       dec A_LIM               ; one more entry to write: one line less to spare
        ldx A_GX
        sta g_line,x            ; the group waits for its latest occupant to end
        inc g_cnt,x
        jmp @gend
@newgrp:
        inc grp
        inc A_GX
        lda A_Y
        sec
        sbc #LEAD_BASE+2        ; lines a second entry would need
        bcs :+
        lda #0
:       sta A_LIM
        ldx A_GX
        lda A_FREE
        sta g_line,x
        lda #1
        sta g_cnt,x
        lda A_OUT
        sta g_pos,x
@gend:  inc A_OUT
        ; next hardware sprite, round robin
        ldx A_HW
        inx
        cpx #8
        bne :+
        ldx mux_first
:       stx A_HW
@next:  ldx A_POS
        inx
        cpx spr_count_b
        bcs @finish
        jmp @each
@finish:
        ldx A_GX
        lda #255
        sta g_line+1,x          ; after the last group
        lda A_OUT
        sec
        sbc spr_base_b
        sta bld_n
        lda grp
        clc
        adc #1
        sta bld_g
        ; enable the pinned sprite 0 (when mux_first is 1) and every
        ; hardware sprite the first group uses
        lda bld_n
        cmp hw_count
        bcc :+
        lda hw_count
:       clc
        adc mux_first
        tax
        lda ena_mask,x
        sta bld_ena
        jmp @ready
@empty: lda #0
        sta bld_n
        ldx spr_base_b
        sta g_cnt,x             ; group 0 is empty
        lda #255
        sta g_line+1,x
        lda #1
        sta bld_g
        ldx mux_first           ; only the pinned sprite, if there is one
        lda ena_mask,x
        sta bld_ena
@ready: lda #1
        sta spr_ready
        rts

; ---------------------------------------------------------------------------
; run_group: X = group (absolute).  Its entries go into their sprites
; through the generated routines; when the list mixes flags, the $D01C and
; $D01B bits of each follow.
run_group:
        lda g_cnt,x
        beq @done
        sta mux_cnt
        lda g_pos,x
        tax
        stx mux_tmp2            ; the group's first list position
        lda rr_lo,x
        sta @j+1
        lda rr_hi,x
        sta @j+2
@j:     jsr ROUT
        lda shw_same
        bne @done
        jmp run_flags
@done:  rts

; run_flags: mixed flags, bit by bit for the positions mux_tmp2 up to X
run_flags:
        stx mux_tmp             ; one past the last
        ldx mux_tmp2
@f:     ldy acc,x
        lda b_flg,y
        lsr
        lda VIC_SPR_MCOLOR
        ora rr_bit,x
        bcs :+
        eor rr_bit,x
:       sta VIC_SPR_MCOLOR
        lda b_flg,y
        lsr
        lsr
        lda VIC_SPR_BG_PRIO
        ora rr_bit,x
        bcs :+
        eor rr_bit,x
:       sta VIC_SPR_BG_PRIO
        inx
        cpx mux_tmp
        bne @f
        rts

; ---------------------------------------------------------------------------
; mux_schedule: the next group's line and handler, or the general handler
; for the split and the blank.  While the chain runs, the interrupt vector
; points straight at mux_irq, so a group costs no dispatch.  (Profile builds
; keep the general handler throughout: the probe's timer shares the vector.)
; mux_next is the absolute index of the next group; its line is 255 after
; the last.  mux_split is the line the chain must hand over at.
mux_schedule:
        lda split_done
        bne :+
        lda split_line
        bne :++
:       lda #250
:       sta mux_split
        ldx mux_next
        lda g_line,x
        cmp #250
        bcs @vb
        sta irq_line
.ifndef B64_PROFILE
        cmp mux_split
        bcs @gen                ; the split comes first: the general handler takes it, then schedules again
        sta VIC_HLINE
        lda #<mux_irq
        sta $FFFE
        lda #>mux_irq
        sta $FFFF
        rts
@gen:   lda irq_line
.endif
        jsr gen_vector
        jmp set_raster
@vb:    lda #255
        sta irq_line
        jsr gen_vector
        jmp set_raster
gen_vector:
        pha
        lda #<b64_irq
        sta $FFFE
        lda #>b64_irq
        sta $FFFF
        pla
        rts

.ifndef B64_PROFILE
; mux_irq: the chain's own interrupt handler.  Runs the group that is due,
; sets the next group's line, and runs that one at once if the raster is
; already there; hands the vector back for the split and the blank.
mux_irq:
        pha
        txa
        pha
        tya
        pha
@grp:   ldx mux_next
        lda g_cnt,x
        sta mux_cnt
        lda g_pos,x
        tax
        stx mux_tmp2
        lda rr_lo,x
        sta @j+1
        lda rr_hi,x
        sta @j+2
@j:     jsr ROUT
        lda shw_same
        bne :+
        jsr run_flags
:       inc mux_next
        ldx mux_next
        lda g_line,x            ; 255 after the last group
        cmp mux_split
        bcs @hand
        sta irq_line
        sta VIC_HLINE
        cmp VIC_HLINE           ; the raster there or past it: the interrupt won't come, run the group now
        beq @grp
        bcc @grp
        bcs @out
@hand:  jsr mux_schedule        ; the general handler for the split or the blank
@out:   lda #1
        sta VIC_IRR
        pla
        tay
        pla
        tax
        pla
mux_irq_rti:                    ; exported for the checks
        rti
.endif

; set the raster compare to A, but never past the HUD split while it is pending
set_raster:
        ldx split_done
        bne :+
        cmp split_line
        bcc :+
        lda split_line
:       sta VIC_HLINE
        rts

; ---------------------------------------------------------------------------
; b64_spr_vblank: take a finished list, write its first group, start the chain.
b64_spr_vblank:
        lda #0
        sta split_done
        lda cut_active
        beq :+
        lda #B64_CUT_SPLIT
        bne :++
:       lda scr_ys
        clc
        adc #B64_SPLIT_BASE
:       sta split_line
        lda spr_ready           ; only a finished list is shown
        beq @keep
        FTRACE 7
        lda #0
        sta spr_ready
        lda spr_base_b
        ldx spr_base_s
        sta spr_base_s
        stx spr_base_b
        lda bld_n
        sta spr_count_s
        lda bld_ena
        sta shw_ena
        lda bld_rej
        sta spr_rejected
        lda bld_same
        sta shw_same
@keep:  lda rr_first
        cmp #$FF
        bne :+
        rts                     ; no list has ever been built: nothing to show
:       ldx mux_first
        lda bit_set,x           ; the pinned sprite's bit, if any: 1 when mux_first is 1, else 0
        sec
        sbc #1
        sta pin_mask
        ; aim the routines' pointer stores at the screen being shown
        lda cut_active
        beq :+
        lda #>B64_SPR_PTR_C
        bne @aim
:       lda scr_front
        beq :+
        lda #>B64_SPR_PTR_B
        bne @aim
:       lda #>B64_SPR_PTR_A
@aim:
.repeat 8, h
        sta ROUT + 64*h + T_PTR + 1
.endrepeat
        lda shw_ena
        sta VIC_SPR_ENA
        lda shw_same
        beq @mixed
        ; one set of flags for every multiplexed sprite: $D01C and $D01B once,
        ; from the first entry's flags
        lda pin_mask
        eor #$FF
        sta mux_tmp             ; the multiplexed sprites' bits
        lda spr_count_s
        beq @mixed
        ldy spr_base_s
        ldx acc,y
        lda b_flg,x
        sta mux_tmp2
        lsr
        lda VIC_SPR_MCOLOR
        and pin_mask
        bcc :+
        ora mux_tmp
:       sta VIC_SPR_MCOLOR
        lda mux_tmp2
        lsr
        lsr
        lda VIC_SPR_BG_PRIO
        and pin_mask
        bcc :+
        ora mux_tmp
:       sta VIC_SPR_BG_PRIO
@mixed: ldx spr_base_s
        stx mux_next
        jsr run_group           ; group 0: every sprite's first entry
        inc mux_next
        jmp mux_schedule

; chain interrupt through the general handler (profile builds, and the
; blank's catch-up): run the group that is due, then any already due too
mux_chain:
@again: ldx mux_next
        lda g_line,x
        cmp #250
        bcs @done               ; past the last group
        jsr run_group
        inc mux_next
        jsr mux_schedule
        lda irq_line
        cmp #255
        beq @done
        cmp VIC_HLINE
        bcc @again
        beq @again
@done:  rts
