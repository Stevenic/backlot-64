# Roadmap

Where the engine is going and in what order. `PLAN.md` is the design and its milestone table is the record of what has shipped; this file is the forward view. Every step ends with a runnable program, a measured number, and a check in `make check` that would fail if it regressed. Ideas taken from other projects are named with their source; `CREDITS.md` has the full list.

## Where it stands (September 2026)

Running in VICE: the core, the data engine with a slot packer, the 8-way scroller over a 2048x2048 metatile world, the 24-sprite multiplexer with frame streaming, the HUD split, cutscenes with pixel-exact sprite-to-bitmap parking and a reflection shimmer, a p-code VM executing scripts from the REU through a page cache, and a boot probe that scales from a stock C64 with an 8 MB REU to the C64 Ultimate. Resident code 8.5 KB. Scroller worst case 9,200 cycles against a 6,000 target. VM 82 to 116 cycles per opcode. Cutscene frame: 2,200 cycles in the blank, 9,600 in the tick, 3,000 for the shimmer every fourth frame.

## Phase 1: Solid

The engine other people can trust. Nothing new is drawn; everything already drawn becomes provable.

1. **`make check`.** The two-tier scene diff (8 MB and 16 MB), the benchmark, and the budget table move from scratch scripts into `tools/` and the Makefile. The target fails on any pixel outside the shimmer, any probe result other than expected, and any cycle count over budget. Runs in CI on every push.
2. **Docs audit.** Every claim about the VIC-II, the CIAs and the REU in `PLAN.md`, `ART.md` and `MEMORY.md` is checked against Christian Bauer's VIC-II article, Codebase64, the Programmer's Reference Guide and "Mapping the C64", and corrected or cited. Claims that cannot be sourced are marked as measured-in-VICE or removed.
3. **Self-describing REU image.** A header with magic, version and block descriptors, checked at boot against the compiled slot table; a mismatch halts with the error in the border. Ends the silent empty-REU failure for good. *After DOOM C64U.*
4. **Millisecond clock.** CIA timers cascaded into a counter that is valid at any CPU speed, so the benchmark travels to the Ultimate's turbo. *After DOOM C64U.*
5. **The first hardware run.** When the C64 Ultimate arrives: `make bench` on it, the tiers 2 to 4 probes confirmed or fixed, the UNTESTED markers removed, footage of the scene from the HDMI output.

## Phase 2: Fast

The three budgets that are over or fragile, each fixed by an idea with a measured payoff.

6. **Fills.** Character colour packed into the screen code so the redraw is one load and two stores, plus per-metatile flags for uniform colour and no colour write. Target: scroller worst case under 6,000 cycles. *After Cadaver's c64gameframework.*
7. **VM dispatch.** Done 2026-09-17. Page-aligned `jmp (table)` dispatch with pre-doubled opcodes and a self-modified page byte in the opcode fetch, per-byte page wrap in place of the boundary buffer, budget charged on taken jumps. Measured: 82 to 116 cycles per opcode (was 116 to 147), the drive loop 6.8 times assembly (was 11). *After the Å-machine.*
8. **Page table with a pin bit.** A 256-entry map replaces the linear tag scan; a running thread's page can never be evicted. *After the Å-machine.*
9. **Multiplexer and the tick.** The cutscene tick is 9,600 cycles, most of it the object's eight sprite submissions with their animation lookups and the list sort; measure each part with `-DFRAME_TRACE` and cut it before adding the ninth sprite. Then: persistent sort order with sorting only when the count changes, grouped IRQs with a count-aware advance and direct fall-through when late, ninth-sprite rejection, thinning as the fallback, and two layer bits for draw order. *After c64gameframework, leissa/c64engine and hhprg/C64Engine.*
10. **Turbo tier shift.** A CPU screen shift selected by the boot probe, because DMA does not speed up. *After DOOM C64U's measurements.*

## Phase 3: A world

The pieces a game loop needs, in the order the paging plan lays them out.

11. **Sector ring.** 256-byte sector records, a 3x3 ring around the camera, prefetch by heading, header-first fetch so empty sectors cost one small DMA. *Header-first after DOOM C64U.*
12. **Split tileset swap.** A region's 12 KB tileset arrives 1 KB a frame into a second library, switched under the core-only band.
13. **Modules as overlays.** The VM becomes the overlay manager (`docs/MODULES.md`): a four-slot code cache with pins in region A, modules with jump tables linked once per slot, SYS and NEED opcodes, a wait-on-module thread state, and the residency plan the script compiler emits. The vehicle module is the first pinned module and the pathfinder the first cached one.
14. **Entities.** The entity table in hot RAM, spawn and write-back through the sector ring, sprite frames pre-streamed when a sector loads.
15. **VM events.** Freeze and override for cutscenes, event waits, entity-bound threads spawned from a per-entity event table, bitvars, per-thread locals once contexts page to the REU. *After SCUMM v0.*
16. **Music.** A SID register stream: the tune's player runs at build time, register writes are delta-encoded into the REU, and playback is a small IRQ. Ultimate Audio for samples on tier 3; a stock-hardware sample path later. *After DOOM C64U.*
17. **Screens as packages.** The overlay loader is done (2026-09-17, `examples/overlay`, verified at both tiers); next is one REU slot per screen with its code, screen data and text, and window-and-lookahead lists inside them.
18. **Save and load.** Hot state stashed as a block, sector records written back, the 64 KB region as the save.

## Phase 4: Ship

19. **Release.** A tagged build with the REU image, the examples, the benchmark numbers in the readme, and a page that shows the scene running on hardware.
20. **The game.** Its own repository on this engine, with its own name and hand-drawn art.

## Not planned

EasyFlash, NTSC timing, C128 and split-screen stay in `PLAN.md` as possibilities and are not on this roadmap. VSP scrolling, runtime charset allocation and a stack-machine VM were considered and rejected; `PRIOR-ART.md` says why.
