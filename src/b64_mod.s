; backlot-64: the module manager (docs/MODULES.md section 9).
;
; Modules live in the REU and run at the address they were linked for.  The
; packer's module table (reu.manifest's module lines, slot MODTAB) says
; where each goes, what interface it provides and which it requires; this
; keeps it in RAM with each module's state.  The rule it keeps: a module is
; never evicted while a resident module requires what it provides, or while
; it is pinned.
;
;   b64_mod_need   A = module: load it now, its requirements first (the
;                  default provider of each unmet one); C=1 resident, C=0
;                  refused, mod_err saying why: the module in the way, $FF a
;                  requirement nothing provides at the version needed (or
;                  a bad number), $FE a scene has the display
;   b64_mod_find   A = interface -> X = the resident module providing it, C=1
;   b64_mod_default  A = interface -> X = its default provider, C=1
;   b64_mod_queue  A = module: load it at the next service
;   b64_mod_service  from the main loop after the game callback: one load;
;                  a refusal is left in mod_fail for the VM to report
;   b64_mod_pin / b64_mod_unpin  A = module: held resident while pinned
;
; Making room: every resident module that overlaps the new one must be
; evictable (nothing resident requires it, no pins), or be a provider of
; the same interface at no newer a version: the new one then takes over its
; dependents, and its swap entry runs (the physics modules' resume).  A
; refusal evicts nothing (requirements loaded on the way stay).  Providers
; of one interface share a base address (the packer sees to it), so only
; one is ever resident.
;
; The table also names the game opcodes a module's handlers serve (the
; manifest's op lines); after every load the VM points them at their
; handlers, or at its loader while their module is away (b64_vm_ops).

.include "b64.inc"
.include "slots.inc"

.export b64_mod_init, b64_mod_need, b64_mod_find, b64_mod_default, b64_mod_queue, b64_mod_service
.export b64_mod_pin, b64_mod_unpin
.export mod_state, mod_refs, mod_pins, mod_prov, mod_fail, mod_log, mod_logn
.import mod_err                 ; at B64_MOD_ERR (src/b64_api.s), where scripts can read it
.export gop_if, gop_lo, gop_hi

MT_FLAGS = 1                    ; the table's fields (tools/b64pack.py)
MT_REU   = 2
MT_BASE  = 5
MT_SIZE  = 7
MT_PROV  = 9
MT_PVER  = 10
MT_REQ1  = 11
MT_REQ2  = 13
MT_SWAP  = 15

.segment "LOWRAM"
mod_tab:        .res 256        ; module n at 16 * n; +0: the count
gop_if:         .res VM_GAME_OPS ; then the game opcodes, fetched with it
gop_lo:         .res VM_GAME_OPS
gop_hi:         .res VM_GAME_OPS
mod_state:      .res 16         ; bit 7: resident
mod_refs:       .res 16         ; resident modules that require what it provides
mod_pins:       .res 16
mod_prov:       .res 16         ; per interface: the resident module providing it, 0 none
mod_queue:      .res 1          ; a module to load at the next service, 0 none
mod_fail:       .res 1          ; the last queued load refused, until the VM reports it
mod_log:        .res 16         ; the modules loaded, in order (for the tests)
mod_logn:       .res 1
mod_depth:      .res 1          ; requirements being loaded, nested
rq_if:          .res 1
rq_ver:         .res 1
rm_id:          .res 1          ; making room: the module, its range, a provider it replaces
rm_b:           .res 2
rm_e:           .res 2
rm_swap:        .res 1
mod_vec:        .res 2          ; a swap entry, called through

.segment "CODE"
b64_mod_init:
        B64_SET24 b64_reu, SLOT_MODTAB
        B64_SET16 b64_ptr, mod_tab
        B64_SET16 b64_len, 256 + 3 * VM_GAME_OPS
        jsr b64_fetch
        ldx #15
        lda #0
:       sta mod_state,x
        sta mod_refs,x
        sta mod_pins,x
        sta mod_prov,x
        dex
        bpl :-
        sta mod_queue
        sta mod_logn
        sta mod_err
        sta mod_fail
        sta mod_depth
        rts

; entry: A = module -> Y = its row in the table
entry:  asl a
        asl a
        asl a
        asl a
        tay
        rts

b64_mod_pin:
        tax
        inc mod_pins,x
        rts
b64_mod_unpin:
        tax
        lda mod_pins,x
        beq :+
        dec mod_pins,x
:       rts

b64_mod_queue:
        ldx mod_queue           ; one at a time: a request waits for the last
        bne :+
        sta mod_queue
:       rts

b64_mod_service:
        lda cut_active          ; a scene has the display: loads wait for its end
        bne @done
        lda mod_queue
        beq @done
        ldx #0
        stx mod_queue
        pha
        jsr b64_mod_need
        pla
        bcs @done
        sta mod_fail
@done:  rts

; b64_mod_find: A = interface -> X = the resident module providing it, C=1
b64_mod_find:
        and #15
        tax
        lda mod_prov,x
        tax
        beq @no
        sec
        rts
@no:    clc
        rts

; b64_mod_default: A = interface -> X = its default provider, C=1
b64_mod_default:
        sta b64_tmp
        ldx mod_tab
        beq @no
@m:     txa
        jsr entry
        lda mod_tab+MT_PROV,y
        cmp b64_tmp
        bne @n
        lda mod_tab+MT_FLAGS,y
        and #1
        bne @yes
@n:     dex
        bne @m
@no:    clc
        rts
@yes:   sec
        rts

; ---------------------------------------------------------------------------
; b64_mod_need: A = module -> C=1 resident (loaded if it was not)
b64_mod_need:
        tax
        beq @bad
        dex
        cpx mod_tab             ; modules are 1 to the count
        inx
        bcs @bad
        lda mod_state,x
        bpl :+
        sec
        rts
:       lda cut_active          ; region A is the scene's until it ends
        beq :+
        lda #$FE
        sta mod_err
        clc
        rts
:       lda mod_depth           ; requirements nest two or three deep; a loop is refused
        cmp #4
        bcc :+
@bad:   lda #$FF
        sta mod_err
        clc
        rts
:       inc mod_depth
        txa
        pha                     ; the module, across the requirements' loads
        ldy #MT_REQ1
        jsr require
        bcc @fail
        pla
        pha
        ldy #MT_REQ2
        jsr require
        bcc @fail
        pla
        pha
        tax
        jsr make_room
        bcc @fail
        pla
        tax
        jsr load
        dec mod_depth
        jsr b64_vm_ops          ; the game opcodes whose handlers came or went
        sec
        rts
@fail:  pla
        dec mod_depth
        clc
        rts

; require: A = module, Y = which requirement -> C=1 when a resident module
; provides it at the version needed, loading its default provider if none
; does
require:
        sty rq_if
        jsr entry
        tya
        clc
        adc rq_if
        tay
        lda mod_tab,y
        bne :+
        sec                     ; no requirement there
        rts
:       sta rq_if
        lda mod_tab+1,y
        sta rq_ver
        lda rq_if
        jsr b64_mod_find
        bcc @load
        txa                     ; a provider is resident: new enough?
        jsr entry
        lda mod_tab+MT_PVER,y
        cmp rq_ver
        bcs @ok
@none:  lda #$FF
        sta mod_err
        clc
        rts
@load:  lda rq_if
        jsr b64_mod_default
        bcc @none
        txa
        jsr entry
        lda mod_tab+MT_PVER,y
        cmp rq_ver
        bcc @none
        txa
        jmp b64_mod_need        ; (its own requirements first)
@ok:    sec
        rts

; make_room: X = module -> C=1 when every resident module overlapping it is
; evictable (evicted now) or a provider of the same interface it replaces
; (rm_swap, taken over in load); C=0 and mod_err = the one in the way
make_room:
        stx rm_id
        txa
        jsr entry
        lda mod_tab+MT_BASE,y
        sta rm_b
        clc
        adc mod_tab+MT_SIZE,y
        sta rm_e
        lda mod_tab+MT_BASE+1,y
        sta rm_b+1
        adc mod_tab+MT_SIZE+1,y
        sta rm_e+1
        lda #0
        sta rm_swap
        ldx mod_tab             ; first see that nothing in the way must stay
@c:     cpx rm_id
        beq @cn
        lda mod_state,x
        bpl @cn
        jsr overlaps
        bcc @cn
        lda mod_pins,x          ; pinned: stays, whatever would replace it
        bne @stay
        jsr same_if
        bcc :+
        stx rm_swap
        jmp @cn
:       lda mod_refs,x
        beq @cn
@stay:  stx mod_err
        clc
        rts
@cn:    dex
        bne @c
        ldx mod_tab             ; then evict what may go
@e:     cpx rm_id
        beq @en
        cpx rm_swap
        beq @en
        lda mod_state,x
        bpl @en
        jsr overlaps
        bcc @en
        jsr evict
@en:    dex
        bne @e
        sec
        rts

; overlaps: X = a module -> C=1 if its range meets rm_b-rm_e.  Keeps X.
overlaps:
        txa
        jsr entry
        lda mod_tab+MT_BASE,y   ; its base < rm_e?
        cmp rm_e
        lda mod_tab+MT_BASE+1,y
        sbc rm_e+1
        bcs @no
        lda mod_tab+MT_BASE,y   ; and rm_b < its base + size?
        clc
        adc mod_tab+MT_SIZE,y
        sta b64_tmp
        lda mod_tab+MT_BASE+1,y
        adc mod_tab+MT_SIZE+1,y
        sta b64_tmp+1
        lda rm_b
        cmp b64_tmp
        lda rm_b+1
        sbc b64_tmp+1
        bcs @no
        sec
        rts
@no:    clc
        rts

; same_if: X = a resident module -> C=1 if it provides the interface rm_id
; provides, at no newer a version (rm_id can take over its dependents).
; Keeps X.
same_if:
        lda rm_id
        jsr entry
        lda mod_tab+MT_PROV,y
        beq @no                 ; providing nothing: nothing to take over
        sta b64_tmp
        lda mod_tab+MT_PVER,y
        sta b64_tmp+1
        txa
        jsr entry
        lda mod_tab+MT_PROV,y
        cmp b64_tmp
        bne @no
        lda b64_tmp+1           ; the new one's version >= the old one's
        cmp mod_tab+MT_PVER,y
        bcc @no
        sec
        rts
@no:    clc
        rts

; evict: X = a resident module -> gone; what it required loses a dependent.
; Keeps X.
evict:
        lda #0
        sta mod_state,x
        sta mod_refs,x          ; (a provider replaced has handed its dependents on)
        txa
        pha
        jsr entry
        lda mod_tab+MT_PROV,y   ; no longer its interface's provider
        and #15
        sta b64_tmp
        lda mod_tab+MT_REQ1,y
        pha
        lda mod_tab+MT_REQ2,y
        pha
        ldy b64_tmp
        txa
        cmp mod_prov,y
        bne :+
        lda #0
        sta mod_prov,y
:       pla
        jsr unref
        pla
        jsr unref
        pla
        tax
        rts
unref:  beq @done               ; A = an interface (0 none): its provider loses a dependent
        jsr b64_mod_find
        bcc @done
        lda mod_refs,x
        beq @done
        dec mod_refs,x
@done:  rts

; load: X = module, the room made -> fetched and resident; a provider it
; replaced hands over its dependents and goes; what it requires gains a
; dependent; its swap entry runs if it replaced one
load:
        txa
        pha
        jsr entry
        lda mod_tab+MT_REU,y
        sta b64_reu
        lda mod_tab+MT_REU+1,y
        sta b64_reu+1
        lda mod_tab+MT_REU+2,y
        sta b64_reu+2
        lda mod_tab+MT_BASE,y
        sta b64_ptr
        sta mod_vec
        lda mod_tab+MT_BASE+1,y
        sta b64_ptr+1
        sta mod_vec+1
        lda mod_tab+MT_SIZE,y
        sta b64_len
        lda mod_tab+MT_SIZE+1,y
        sta b64_len+1
        jsr b64_fetch
        pla
        tax
        lda mod_logn            ; the log, for the tests
        and #15
        tay
        txa
        sta mod_log,y
        inc mod_logn
        ldy rm_swap             ; a provider replaced: its dependents are ours
        beq @reqs
        lda mod_refs,y
        sta mod_refs,x
        txa
        pha
        tya
        tax
        jsr evict
        pla
        tax
@reqs:  lda #$80                ; resident, and its interface's provider (a module
                                ; that provides nothing writes slot 0, which nothing reads)
        sta mod_state,x
        txa
        pha
        jsr entry
        lda mod_tab+MT_PROV,y
        and #15
        tay
        txa
        sta mod_prov,y
        pla
        pha
        jsr entry
        lda mod_tab+MT_REQ1,y
        pha
        lda mod_tab+MT_REQ2,y
        jsr addref
        pla
        jsr addref
        pla
        tax
        lda rm_swap             ; and the swap entry
        beq @done
        txa
        jsr entry
        lda mod_tab+MT_SWAP,y
        cmp #$FF
        beq @done
        sta b64_tmp             ; base + entry * 3
        asl a
        adc b64_tmp
        clc
        adc mod_vec
        sta mod_vec
        bcc :+
        inc mod_vec+1
:       txa
        pha
        jsr call_vec
        pla
        tax
@done:  rts
addref: beq @done               ; A = an interface: its provider gains a dependent
        jsr b64_mod_find
        bcc @done
        inc mod_refs,x
@done:  rts
call_vec:
        jmp (mod_vec)
