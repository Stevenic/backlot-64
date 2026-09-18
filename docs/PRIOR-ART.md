# Prior Art: What Backlot-64 Borrows

Nine C64 projects were read for techniques worth taking. Each entry names the source file, explains the mechanism, says which module it improves and what it costs, and is ranked by value to this engine. Where a source is not open for reuse, the idea is described and the code is not copied. Credit to the authors is owed and given here; anything adopted gets a comment naming its origin in the source.

## Ranked

### 1. Colour packed into the screen code (c64gameframework)

`macros.s` `drawfullblock` and `drawedge`, from Cadaver's framework and QUOD INIT EXIT 2. Every character's colour equals the low four bits of its screen code, so the redraw is one load and two stores with no colour lookup. Each block also carries flags: one colour for all four cells, or skip the colour write (sky). **Module:** scroller fills, the stated bottleneck at about 45 cycles per cell. **Cost:** a constraint in `b64tileset.py` (characters bucketed by colour), zero runtime; the fills lose the metatile colour lookup entirely.

### 2. Zero-page fetch and page-aligned dispatch (Å-machine)

`src/6502/engine.s` `fetchnext`, Linus Åkesson's Å-machine. The fetch lives in zero page: increment Y, branch on wrap, load absolute-indexed through a self-modified page byte (4 cycles, not 5), then `jmp (optable)` through a page-aligned table whose low byte is patched with the pre-doubled opcode. 23 cycles against this VM's 56 for the same work. **Module:** VM dispatch, 40 to 50 percent of the measured 116 to 147 cycles per opcode. **Cost:** a 256-byte aligned table padded with END so the bounds check goes away, a dozen bytes of zero page, opcodes doubled by the assembler macros. Also from the same source: per-byte wrap on operand fetches instead of the boundary buffer, which is a wash in cycles and a large simplification in code.

### 3. SID register stream (DOOM C64U)

`tools/sidstream.py`, `src/music.asm`. The tune's own player runs at build time in a Python 6502; the 25 SID registers are snapshotted per tick and delta-encoded (about 9 bytes a tick, 20 bytes per second of music). Playback is an IRQ that DMAs a fixed window per tick and writes the named registers. **Module:** sound; zero resident player code, music as a packer slot. It also carries a rule this engine adopted independently: an interrupt that issues a DMA must save and restore the REU registers it interrupts. **Cost:** about 150 bytes of handler, 40 bytes of DMA per tick.

### 4. Freeze and override for cutscenes (SCUMM v0)

`script.cpp` `freezeScripts`, `beginOverride`. A cutscene freezes every script except itself and the freeze-resistant ones with a count, not a flag, so nested freezes unwind correctly; an override stores a resume offset so the player can skip the scene. **Module:** VM scheduler. **Cost:** a frozen count and a resume offset per thread, no dispatch cost.

### 5. Persistent sprite order, count-aware IRQ advance, ninth-sprite rejection (c64gameframework)

`screen.s` `UF_SortLoop`, `UF_CopyLoop2`, `aligneddata.s` `sprIrqAdvanceTbl`, `raster.s`. The order array is never reset; unused sprites carry a maximum Y and sink, and the full sort runs only when the count changes. Sprites within five lines share one IRQ whose line is the first Y minus an advance by group size, and if the raster is already within three lines the next handler is jumped to directly. A sprite fewer than 21 lines below the one eight places back is rejected rather than shown late. **Module:** multiplexer, which today rebuilds identity order and insertion-sorts every frame with a fixed 22-line advance. **Cost:** a few dozen bytes; most of the sort disappears on coherent motion.

### 6. CPU screen shift on the turbo tier (DOOM C64U)

`src/reubench.asm`, `docs/georam-vs-reu.md`. Measured on hardware: REU DMA costs one microsecond per byte at every CPU speed, so at 64 MHz a CPU copy beats DMA for RAM-to-RAM work by about eight times. **Module:** scroller and platform layer; the 999-byte shift through REU scratch becomes the slowest thing in a turbo frame. **Cost:** a second shift routine selected by the boot probe.

### 7. Page table with a pin bit (Å-machine)

`engine.s` `swapin`. Virtual page to physical page through a 256-entry map, second-chance eviction with a referenced bit, and the current program counter's page protected. **Module:** page cache, which scans eight tags linearly and can evict the page a thread is executing. **Cost:** 256 bytes of map for the script region, a pin bit.

### 8. Y-order thinning (leissa/c64engine)

`raster.acme`. When sprites will not fit, show every second one in Y order on alternate frames, then every fourth; nothing vanishes, density degrades evenly. **Module:** multiplexer, as the fallback after the ninth-sprite rejection. **Cost:** a counter and a phase.

### 9. Header-first fetch (DOOM C64U)

`src/render/bsp.asm`. Fixed power-of-two slots; fetch the small header, test it, fetch the payload only for the records that pass. Mean traffic 39 bytes instead of 128. **Module:** sector records and object headers. **Cost:** one extra DMA setup per fetch; wins when payloads are usually skipped.

### 10. Layer-aware hardware sprite allocation (hhprg/C64Engine)

`Multiplexer.asm` `AllocHardwareSprites`. Two layer bits per virtual sprite; hardware sprites are split between layers and reused once the previous occupant's Y has passed, so lower hardware numbers give correct draw order. **Module:** multiplexer, for beacons over cars and pedestrians under vehicles. **Cost:** a fast path when one layer is in use, otherwise about 200 compares worst case.

### 11. Deferred event queue for entity threads (SCUMM v0)

`o2_doSentence`, `_walkToObjectState`. The wait lives in engine state advanced per frame, and the script starts only when the state completes. **Module:** VM events and entity-bound threads, planned. **Cost:** a per-entity (event, offset) table; a wait word with the high bit set meaning "wait on event" rather than frames.

### 12. Fill budget across frames, two-frame logic with interpolation (leissa, c64gameframework)

`tiles.acme` `COPY_TILES`; `actor.s` `InterpolateActors`. Fill the column on one frame and the row on the next under a 4 px per frame cap; run entity logic every second frame and interpolate positions between. **Module:** scroller; game side. **Cost:** a resume point; a previous position per entity.

### 13. Self-describing REU image header (DOOM C64U)

`docs/reu-format.md`, `src/mapload.asm`. Magic, version and block descriptors at the start of the image; the loader cross-checks load addresses against the compiled constants and sums each block, halting with the error in the border. **Module:** packer and boot. **Cost:** 128 bytes of header, 200 bytes of loader. Would have caught the empty-REU trap that broke the 8 MB tier twice.

### 14. Millisecond clock and frame histogram (DOOM C64U)

`src/clock.asm`, `src/instrument.asm`. CIA2 timers cascaded into a millisecond counter valid at any CPU speed, with per-frame min, max and a histogram read by a monitor script. **Module:** benchmark harness, whose cycle counts do not travel to 64 MHz. **Cost:** 60 cycles a frame.

### 15. Smaller pieces

Bitvars (256 flags in 32 bytes) and per-thread locals when contexts move to the REU (SCUMM); short one-byte relative branches (Å-machine); edit the master copy of an asset in the REU so every on-screen instance changes on its next plot (PETSCII Robots REU); a dirty-cell compare before every bitmap DMA (PETSCII Robots); an x-scroll field in the split table for a parallax sky band (Chrome Horizon); a warm-up that prefills half the page cache on scene entry (Å-machine).

## Where this engine is already ahead

The page cache and VM have no counterpart in any of the nine. DOOM re-fetches per subsector every frame and has no multiplexer. PETSCII Robots redraws its window tile by tile; the shifted screen plus column fill is far cheaper. Cadaver's compacting allocator with relocation is unnecessary with an REU behind a page cache. The hidden immediate variable that lets the immediate and register forms of every opcode share one handler is cheaper than SCUMM's parameter bits. Manifest-generated slot symbols beat hand-typed constants everywhere. Border-scheduled DMA appears in none of them.

## Not taken

AGSP and VSP bitmap scrolling (leissa): a fixed 25-line cost, hand-timed, and VSP corrupts RAM on some machines. Flip-bit virtual characters with runtime charset allocation (hhprg): the fixed core-plus-regional charset is cheaper per frame. A stack machine (EightBall): more opcodes per statement than the register form. Compacting relocation (c64gameframework): solved by paging.

## Sources

- c64gameframework, Lasse Öörni: https://github.com/cadaver/c64gameframework (MIT) and the rants at https://cadaver.github.io/rants/
- DOOM for the C64 Ultimate, Honza Slesinger: https://github.com/slesinger/doom (CC BY-NC-SA 4.0), https://hondani.com/doom
- Å-machine, Linus Åkesson: https://github.com/Dialog-IF/aamachine, https://www.linusakesson.net/dialog/aamachine/6502/index.php
- SCUMM v0 as described by Michael Steil: https://www.pagetable.com/?p=603, and ScummVM's `engines/scumm`
- hhprg/C64Engine: https://github.com/hhprg/C64Engine (MIT)
- leissa/c64engine: https://github.com/leissa/c64engine (GPL-3.0; ideas only)
- PETSCII Robots C64 REU edition, Scott Robison and David Murray: https://github.com/zeropolis79/PETSCIIRobots-C64REU (study only; ideas only)
- Chrome Horizon, Stefano Coppi: https://github.com/stefanocoppi/chrome-horizon-C64
- EightBall, Bobbi Webber-Manners: https://github.com/bobbimanners/EightBall
- SWEET16, Steve Wozniak: https://en.wikipedia.org/wiki/SWEET16
