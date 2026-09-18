; backlot-64: the C64 Ultimate module, loaded into overlay region B at boot.
;
; The sampler (b64_pcm.s) and the command interface (b64_uci.s) only do
; anything on an Ultimate, so they are not resident: they are assembled for
; region B, packed as the ULTIMATE slot, and fetched by b64_plat_probe when
; it finds either feature.  On any other machine the probe writes a stub
; for each entry that returns with the carry clear, so the calls are always
; safe.  The module refers to no engine address, only to zero page and the
; hardware, so one binary serves every program, profile builds included.
; UNTESTED on hardware as of 2026-09-18: VICE emulates neither feature.

.include "b64.inc"

.import pcm_play, pcm_loop, pcm_stop, pcm_volume, uci_load

.segment "ULTJMP"
        jmp pcm_play            ; b64_pcm_play
        jmp pcm_loop            ; b64_pcm_loop
        jmp pcm_stop            ; b64_pcm_stop
        jmp pcm_volume          ; b64_pcm_volume
        jmp uci_load            ; b64_uci_load
        .byte 0                 ; B64_ULT_PLAT: b64_plat, written by the loader
