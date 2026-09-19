; backlot-64: the engine's entries for modules (docs/MODULES.md), at a fixed
; address in every build of the engine ($2F00, b64.cfg's API segment), so a
; module linked once works with any build: the plain one, the profiling one,
; the multiplexer's test one.  A module writes `jsr b64_fetch` as usual and
; tools/b64overlay.py links it to this table's entry for b64_fetch.  The
; engine variables modules read live here too, at fixed addresses: the
; platform bits, and the VM's variables, which a game opcode's handler reads
; and writes.
;
; Append only: an entry's place is its address, and a module linked against
; it keeps working until it is linked again.  Entries fill $2F00-$2F9F (53
; of them); the variables start at $2FA0 (B64_API_DATA).  Scripts reach an
; entry through SYS 0 with its address, B64_API + 3 * n (the API_* list in
; include/b64.inc, checked against this table at link time).

.include "b64.inc"

.export b64_plat, b64_reu_mb, mux_first, cut_active, mod_err, vm_lo, vm_hi

.segment "API"
api_first:
api_b64_set_callback:   jmp b64_set_callback
api_b64_fetch:          jmp b64_fetch
api_b64_stash:          jmp b64_stash
api_b64_reu_present:    jmp b64_reu_present
api_b64_load_tileset:   jmp b64_load_tileset
api_b64_load_sprites:   jmp b64_load_sprites
api_b64_move_camera:    jmp b64_move_camera
api_b64_redraw:         jmp b64_redraw
api_b64_scroll_prepare: jmp b64_scroll_prepare
api_b64_spr_begin:      jmp b64_spr_begin
api_b64_spr_add:        jmp b64_spr_add
api_b64_spr_pinned:     jmp b64_spr_pinned
api_b64_spr_end:        jmp b64_spr_end
api_b64_cut_begin:      jmp b64_cut_begin
api_b64_cut_end:        jmp b64_cut_end
api_reu_advance_len:    jmp reu_advance_len
api_b64_vm_start:       jmp b64_vm_start
api_b64_vm_tick:        jmp b64_vm_tick
api_b64_page_get:       jmp b64_page_get
api_b64_page_flush:     jmp b64_page_flush
api_b64_overlay_load:   jmp b64_overlay_load
api_b64_overlay_reset:  jmp b64_overlay_reset
api_b64_turbo_set:      jmp b64_turbo_set
api_b64_turbo_fast:     jmp b64_turbo_fast
api_b64_turbo_slow:     jmp b64_turbo_slow
api_b64_heap_alloc:     jmp b64_heap_alloc
api_b64_heap_reset:     jmp b64_heap_reset
api_b64_hud_clear:      jmp b64_hud_clear
api_b64_hud_text:       jmp b64_hud_text
api_b64_hud_number:     jmp b64_hud_number
api_b64_boot_halt:      jmp b64_boot_halt
api_b64_bench_begin:    jmp b64_bench_begin
api_b64_bench_end:      jmp b64_bench_end
; the module manager (src/b64_mod.s)
api_b64_mod_need:       jmp b64_mod_need
api_b64_mod_queue:      jmp b64_mod_queue
api_b64_mod_find:       jmp b64_mod_find
api_b64_mod_pin:        jmp b64_mod_pin
api_b64_mod_unpin:      jmp b64_mod_unpin
api_b64_vm_op_set:      jmp b64_vm_op_set
; a game opcode's handler (src/b64_vm.s): operands through FETCH's wrap,
; and one of the three ways back
api_vm_wrap:            jmp vm_wrap
api_vm_next:            jmp vm_next
api_vm_back:            jmp vm_back
api_vm_yield:           jmp vm_yield
api_entries_end:

.assert api_b64_mod_need = API_MOD_NEED, lderror, "API_MOD_NEED is not the table's"
.assert api_b64_mod_queue = API_MOD_QUEUE, lderror, "API_MOD_QUEUE is not the table's"
.assert api_b64_mod_pin = API_MOD_PIN, lderror, "API_MOD_PIN is not the table's"
.assert api_b64_mod_unpin = API_MOD_UNPIN, lderror, "API_MOD_UNPIN is not the table's"
.assert api_b64_hud_text = API_HUD_TEXT, lderror, "API_HUD_TEXT is not the table's"
.assert api_b64_hud_number = API_HUD_NUMBER, lderror, "API_HUD_NUMBER is not the table's"

        .res B64_API_DATA - B64_API - (api_entries_end - api_first)

; the engine variables a module may read (and the cutscene module write)
b64_plat:       .byte 0         ; B64_PLAT_* bits (b64_plat_probe)
b64_reu_mb:     .byte 0         ; REU size in MB: 0, 8 or 16
mux_first:      .byte 1         ; the multiplexer's first hardware sprite: 1, or 0 in a scene
cut_active:     .byte 0         ; set while the cutscene module has the display
mod_err:        .byte 0         ; why the last module load was refused (src/b64_mod.s), for scripts to read
                .res 3          ; spare
; the VM's variables (VM_VARS and the hidden T), lo and hi
vm_lo:          .res 33
vm_hi:          .res 33

.assert b64_plat = B64_API_DATA, lderror, "b64_plat is not at B64_API_DATA"
.assert mod_err = B64_MOD_ERR, lderror, "mod_err is not at B64_MOD_ERR"
.assert vm_lo = B64_VM_LO, lderror, "vm_lo is not at B64_VM_LO"
