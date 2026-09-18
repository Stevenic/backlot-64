# Roadmap

Where the engine is going and in what order. `PLAN.md` is the design and its milestone table is the record of what has shipped; this file is the forward view. Every step ends with a runnable program, a measured number, and a check in `make check` that would fail if it regressed. Ideas taken from other projects are named with their source; `CREDITS.md` has the full list.

## Where it stands (September 2026)

Running in VICE: the core, the data engine with a slot packer, the 8-way scroller over a 2048x2048 metatile world, the 24-sprite multiplexer with frame streaming, the HUD split, cutscenes with pixel-exact sprite-to-bitmap parking and a reflection shimmer, a p-code VM executing scripts from the REU through a page cache, and a boot probe that scales from a stock C64 with an 8 MB REU to the C64 Ultimate. Resident engine 10,182 of 10,227 bytes. Scroller preparation worst frame 10,361 cycles against a 6,000 target. VM 82 to 118 cycles per opcode. Cutscene tick: median 8,414 cycles, 15,356 on a shimmer frame, of a 19,656-cycle frame. Every figure is from `make check` and held by `budgets.txt`.

## Phase 1: Solid

The engine other people can trust. Nothing new is drawn; everything already drawn becomes provable.

1. **`make check`.** Done 2026-09-18 (`docs/CHECK.md`). `tools/b64vice.py` drives VICE through the monitor, waiting on prompts rather than sleeps, frame-exact on the frame counter and program labels; `tools/b64check.py` runs both tiers in parallel: the image and its header, the four boot outcomes, the platform probe, overlays, the cutscene's park and restore, the showcase's lamps, pattern, reach and park, and every line of `budgets.txt`. 50 checks in under a minute. Runs in CI on every push (macOS, for `sips`). It found two bugs on its first run: a new object inherited the previous object's lights, and the probe build no longer linked.
2. **Docs audit.** Done 2026-09-18. Every hardware claim in `PLAN.md`, `ART.md`, `PREPARE.md`, `MEMORY.md`, `PAGING.md`, `ULTIMATE.md` and `INSTRUMENT.md` was checked against Bauer's VIC-II article, Codebase64's REU pages, Pepto's colour analysis, "Mapping the C64" and "Mapping the C128", the Ultimate documentation and VICE's source. Corrected: the luma table (wrong in the docs and in the tools), PAL vertical blending, the multicolour bitmap's resolution, the REU rate and setup cost, the I/O window's reachability by DMA, CIA timers under turbo, a real 1750's size, the VM's opcode cost where it was stale, and the REU layout's overlaps; the last Rockstar place names went with it. Still unsourced and marked so: the C128's REC in fast mode, the digi sample cost, whether the command interface unlocks from a program.
3. **Self-describing REU image.** Done 2026-09-18. `b64pack.py` writes a header at $4FF000 (magic, format, a hash of the slot layout, a descriptor per slot); `b64_boot_check` verifies magic, format and hash with the REU's compare command and halts with a flashing border for no REU, no image and a stale image. `make check` proves all four outcomes. *After DOOM C64U. Changed: a verify against constants instead of a fetched, cross-checked header.*
4. **Instrumentation.** Done 2026-09-17, first cut: the probe (`docs/INSTRUMENT.md`) records events, a timer-driven program-counter sample with the VM thread and script offset, opcode counts and a tick histogram into a block at $F800; `tools/b64probe.py` reads it from VICE or from the C64 Ultimate over REST (hardware path untested) and writes the profile the optimizer will read. The clock under turbo is settled on the evidence (2026-09-18): the CIA timers keep counting the 1 MHz clock at every turbo speed, measured on hardware for DOOM C64U and on an Ultimate 64 Elite, so under turbo the probe's tick and histogram are wall time in microseconds and `b64probe.py` labels them so. Step 5 confirms it on this machine. *After DOOM C64U.*
5. **The first hardware run.** When the C64 Ultimate arrives: `make bench` on it, the tiers 2 to 4 probes confirmed or fixed, the UNTESTED markers removed, footage of the scene from the HDMI output.

## Phase 2: Fast

The three budgets that are over or fragile, each fixed by an idea with a measured payoff.

6. **Fills.** Done 2026-09-18. Colour packed into the screen code by the tileset tool, so colour RAM is written by one DMA from an REU copy of the finished screen, which is also the next shift's source; rows unrolled per metatile; columns gathered from a by-column copy of the library and written by unrolled stores; a column's ids by register-reusing one-byte DMAs. The worst case, a diagonal crossing, is 5,754 cycles against the 6,000 target (from 6,341); the border's work after a crossing 1,119 (from 3,109); the engine 500 bytes smaller. `make check` now proves the scrolled picture equals a full redraw of the world. *After Cadaver's c64gameframework. Changed: colour RAM by DMA instead of per-block colour flags.*
7. **VM dispatch.** Done 2026-09-17. Page-aligned `jmp (table)` dispatch with pre-doubled opcodes and a self-modified page byte in the opcode fetch, per-byte page wrap in place of the boundary buffer, budget charged on taken jumps. Measured: 82 to 116 cycles per opcode (was 116 to 147), the drive loop 6.8 times assembly (was 11). *After the Å-machine.*
8. **Page table with a pin bit.** A 256-entry map replaces the linear tag scan; a running thread's page can never be evicted. *After the Å-machine.*
9. **Multiplexer, the tick, and logic at 25 with motion at 50.** The tick-rate design is `PLAN.md` section 6.2, decided 2026-09-18: the display every frame; the game tick at 50 or 25 per mode (one tick every N frames, N = 1 or 2; 16.7 Hz is not offered, see the plan for why); on a 25 tick, the frame between shows every position at the midpoint of its last two; budgets as raster deadlines instead of opcode counts, so turbo headroom is used without guessing its speed. Built with a 25-tick example and its checks. The cutscene tick was 9,600 cycles, most of it the object's eight sprite submissions with their animation lookups and the list sort; measure each part with `-DFRAME_TRACE` and cut it before adding the ninth sprite. Then: persistent sort order with sorting only when the count changes, grouped IRQs with a count-aware advance and direct fall-through when late, ninth-sprite rejection, thinning as the fallback, and two layer bits for draw order. *After c64gameframework, leissa/c64engine and hhprg/C64Engine.*
10. **Turbo tier shift.** A CPU screen shift selected by the boot probe, because DMA does not speed up. *After DOOM C64U's measurements.*

## Showcase (built alongside)

- **Baked lighting** (2026-09-17, `examples/showcase`, `make run-showcase`): dusk over a sunset still through 32 streamed colour maps, then the night street with the cruiser's own light bar, declared in its object file, lighting only the surfaces near each lamp from 80 position maps the engine picks itself, then a pixel-exact park. Every map lands as 1.6 KB of DMA in the blank; the bitmap never changes. The first of the capability pieces from the precomputation list: video, scaled sprites, flow fields, rewind and voice follow the same pattern.

## Phase 3: A world

The pieces a game loop needs, in the order the paging plan lays them out.

11. **Sector ring.** 256-byte sector records, a 3x3 ring around the camera, prefetch by heading, header-first fetch so empty sectors cost one small DMA. *Header-first after DOOM C64U.*
12. **Split tileset swap.** A region's 12 KB tileset arrives 1 KB a frame into a second library, switched under the core-only band.
13. **Modules as overlays.** The VM becomes the overlay manager (`docs/MODULES.md`): a four-slot code cache with pins in region A, modules with jump tables linked once per slot, SYS and NEED opcodes, a wait-on-module thread state, and the residency plan the script compiler emits. The vehicle module is the first pinned module and the pathfinder the first cached one.
14. **Entities.** The entity table in hot RAM, spawn and write-back through the sector ring, sprite frames pre-streamed when a sector loads. Staggered updates (`PLAN.md` section 6.2): physics, input and the player every tick; AI decisions and path requests for one entity in three per tick, by index modulo 3; module hooks declared per-tick or staggered, and the packer's budget counting a staggered hook at a third. This, not a 16.7 Hz tick, is how a crowd fits a stock machine.
15. **VM events.** Freeze and override for cutscenes, event waits, entity-bound threads spawned from a per-entity event table, bitvars, per-thread locals once contexts page to the REU. *After SCUMM v0.*
16. **Music.** A SID register stream: the tune's player runs at build time, register writes are delta-encoded into the REU, and playback is a small IRQ. Ultimate Audio for samples on tier 3; a stock-hardware sample path later. *After DOOM C64U.*
17. **Screens as packages.** The overlay loader is done (2026-09-17, `examples/overlay`, verified at both tiers); next is one REU slot per screen with its code, screen data and text, and window-and-lookahead lists inside them.
18. **Save and load.** Hot state stashed as a block, sector records written back, the 64 KB region as the save.

## Phase 4: Ship

19. **Release.** A tagged build with the REU image, the examples, the benchmark numbers in the readme, and a page that shows the scene running on hardware.
20. **The game.** Its own repository on this engine, with its own name and hand-drawn art.

## Not planned

EasyFlash, NTSC timing, C128 and split-screen stay in `PLAN.md` as possibilities and are not on this roadmap. VSP scrolling, runtime charset allocation and a stack-machine VM were considered and rejected; `PRIOR-ART.md` says why.
