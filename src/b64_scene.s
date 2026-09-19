; backlot-64: what stays resident of the cutscene (docs/MODULES.md).
;
; The cutscene is a module (modules/cut) since 2026-09-19: its 2.7 KB of code
; and 0.8 KB of state are in the REU during play.  A scene starts with
; b64_cut_begin, which stashes region A (a game's collision or AI modules,
; an overlay), fetches the cutscene module there and hands over to it; it
; ends with b64_cut_end, which lets the module restore the playfield and
; puts region A back as it was.  The engine's interrupts and main loop reach
; the module only through its jump table, and only while cut_active is set.

.include "b64.inc"
.include "slots.inc"


CUT_REGION_STASH = SLOT_SCRATCH + $A000     ; region A's 6 KB during a scene (after game RAM's 8 KB)
CUT_SLOT = SLOT_CUT

; cut_active (set by the module once it has the display, cleared before it
; goes) lives at a fixed address in src/b64_api.s, for modules
.segment "CODE"
; b64_cut_begin: region A stashed, the cutscene module fetched into it, and
; the scene's VIC layout (game RAM stashed too, by the module)
b64_cut_begin:
        B64_SET16 b64_ptr, CUT_BASE
        B64_SET16 b64_len, CUT_REGION
        B64_SET24 b64_reu, CUT_REGION_STASH
        jsr b64_stash
        B64_SET16 b64_ptr, CUT_BASE
        B64_SET16 b64_len, CUT_SIZE
        B64_SET24 b64_reu, CUT_SLOT
        jsr b64_fetch
        jsr CUT_BEGIN
        jmp b64_vm_ops          ; game opcodes in modules wait for the scene's end

; b64_cut_end: the module restores game RAM and the playfield's layout (and
; clears cut_active first, so no interrupt enters it again); then region A
; comes back as it was
b64_cut_end:
        jsr CUT_END
        B64_SET16 b64_ptr, CUT_BASE
        B64_SET16 b64_len, CUT_REGION
        B64_SET24 b64_reu, CUT_REGION_STASH
        jsr b64_fetch
        jmp b64_vm_ops          ; and are back
