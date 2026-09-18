# Memory Strategy: 38 KB that behaves like 8 MB

The C64 has 64 KB. After the VIC's bank, the I/O window, the zero page and the tables the engine needs every frame, about 38 KB is left for everything that is not the picture. That 38 KB is not where the game lives. It is a cache. The game lives in the REU, addressed by 24 bits, and the engine moves bytes into the 64 KB only for the frame that needs them.

This file is the strategy: what is resident, what is paged, who pages it, how long paging takes, and how game state is cut into chunks so that no piece has to fit at once.

---

## 1. How long a read takes

REU DMA moves one byte per cycle and halts the CPU while it runs. Setting up a transfer is nine register writes, about 105 cycles with the call. The VIC steals the bus on badlines and for sprites (the REU pauses whenever the VIC holds BA low), so inside the displayed area a DMA ran at about 93 percent in the benchmark; in the border, where no sprite is displayed, it runs at full speed. The 105 cycles are the engine's call, not the REU's: the hardware has no setup cost of its own.

| Transfer | Cycles, border | Cycles, in the display | Time (PAL) | Share of a 19,656-cycle frame |
|---|---|---|---|---|
| 64 B sprite frame | 169 | 169 | 0.17 ms | 0.9 % |
| 256 B page | 361 | 361 | 0.37 ms | 1.8 % |
| 1 KB screen matrix | 1,129 | 1,213 | 1.1 ms | 5.7 % |
| 4 KB | 4,201 | 4,579 | 4.3 ms | 21 % |
| 8 KB overlay or bitmap | 8,423 | 9,053 | 8.5 ms | 43 % |
| 10 KB still | about 10,500 | 11,300 | 10.7 ms | 53 % |
| 12 KB tileset slot | about 12,600 | 13,500 | 12.8 ms | 64 % |
| 38 KB, the whole game area | about 39,000 | 42,000 | 40 ms | 2 frames |
| 64 KB | about 65,600 | 70,500 | 67 ms | 3.3 frames |

Measured in VICE with `make bench` (`examples/bench/main.s`, `tools/b64bench.py`); `make check` holds the measured rows to `budgets.txt`. A transfer costs about 105 cycles of setup plus one cycle per byte in the border; inside the display the badlines slow it to about 93 percent. The border is only 7,056 cycles, so nothing over about 6.9 KB is border-only: the 8 KB "border" figure already includes some badlines, and the rows above it are extrapolations, not measurements.

For comparison a stock 1541 delivers about 300 bytes a second, so an 8 KB overlay is 27 seconds from disk and 8 milliseconds from the REU. A good fastloader is 5 to 10 KB a second. The REU is about three thousand times the disk, which is why the design treats it as memory, not storage.

The one budget that matters is the border: 112 lines, 7,056 cycles, when the VIC is not drawing. Anything that changes what is on screen (a screen shift, a block park, a palette change) goes there so the change is never seen half done. Anything that does not touch the picture (a page fetch for a script, a sector record, a sprite frame) can go anywhere in the frame, provided no raster interrupt falls due during it: the CPU is halted for the whole transfer, so a DMA delays every interrupt by its own length, and an 8 KB transfer is about 134 raster lines.

On real hardware the REU is filled once at boot from whatever mass storage the machine has: seconds from an SD2IEC or 1541 Ultimate, a quarter of an hour of reading from a real 1541 with a fastloader, and 48 disk sides to swap for 8 MB. After that nothing touches the disk except the save.

---

## 2. What is resident

The map in `PLAN.md` section 5, with the current measured sizes.

| Region | Size | Holds | Paged? |
|---|---|---|---|
| $0002-$0051 | 80 B | Engine zero page: camera, DMA parameters, sprite list, VM program counter | no |
| $0200-$07FF | 1.5 KB | Engine tables: sprite lists and sort, VM variables and threads, cutscene state, interrupt scratch copy | no |
| $0800-$2FFF | 10 KB | Engine resident core. Today 7.7 KB code + 0.8 KB tables, including the platform layer. | no |
| $3000-$3FFF | 4 KB | Game resident code: init, the frame callback, module glue | no |
| $4000-$5FFF | 8 KB | VIC: screen A, screen B, charset, 64 sprite slots | the sprite slots stream |
| $6000-$7FFF | 8 KB | Game RAM in play; the bitmap during a cutscene | stashed to the REU for a cutscene |
| $8000-$9FFF | 8 KB | Overlay region A | yes, whole |
| $A000-$C0FF | 8.25 KB | Active metatile library by row and by column, and properties | swapped per region |
| $C100-$C8FF | 2 KB | Page cache: eight 256-byte copies of REU pages | yes, per page |
| $C900-$C9FF | 256 B | The VM's vector table | no |
| $CA00-$CBFF | 512 B | Scroller tables, generated | no |
| $CC00-$CFFF | 1 KB | Overlay region B | yes, whole |
| $D000-$DFFF | 4 KB | I/O | |
| $E000-$FFF9 | 8 KB | Game hot state: entity table, player, mission registers | parts stream (section 5) |

BASIC and the KERNAL are banked out at init and never return. The engine core's 8 KB is a ceiling, not a target: the resident code is 6.6 KB with the VM and the page cache, and the rule in section 6 is what keeps it there.

---

## 3. Who pages what

Five mechanisms, each owned by the engine. A game never writes a DMA.

**Streams (automatic, per frame).** The scroller fetches the metatile column or row that enters the screen; the multiplexer fetches a 64-byte sprite frame into a slot when the frame a sprite wants is not the one the slot holds. Neither needs a request. A sprite that keeps its frame costs nothing; the 24 virtual sprites can each change frame every frame and stay inside the border budget.

**Slots (on an event).** A tileset slot (12 KB) is swapped when the camera crosses a region border, under the region's core-only tile band so the swap is invisible. A still (10 KB) is loaded straight into the VIC bitmap when a script says STILL. An object's header comes in when a script says OBJECT. All of these are one DMA to a fixed address and nothing is kept afterwards but the header.

**The page cache (on a miss).** For data read in small sequential pieces the engine keeps eight 256-byte pages at $C100 with a linear tag lookup and round-robin replacement. A hit is a compare; a miss is one 361-cycle DMA. This is how the VM will run p-code from the REU, how dialogue text is read, and how path tables are walked. Scripts stop being limited by RAM: a mission script can be 60 KB and the game pays for the pages it touches.

**Overlays (on a screen change).** Code that is not per-frame lives in 8 KB slots in the REU assembled for region A or B. The map screen, the pause menu, the save system, an interior editor, the radio tuner: each is an overlay that loads in 8 ms when its screen opens and is forgotten when it closes. The render path never calls into an overlay, so a missing overlay cannot break a frame.

**Stash and restore (around a mode).** A cutscene borrows the 8 KB at $6000 for its bitmap. `b64_cut_begin` stashes those 8 KB to the REU (8 ms) and `b64_cut_end` restores them. The scene reads its still, renders, and throws everything away; the game's RAM comes back untouched. Information screens, the map, and the title do the same through overlays.

---

## 4. The video buffer

The VIC reads one 16 KB bank; the engine uses $4000-$7FFF.

- **In play:** two 1 KB screens (A and B) double-buffered, a 2 KB charset, and 4 KB of sprite slots. The playfield is character mode, 40 x 23 cells over the HUD. Colour RAM at $D800 is a separate 1,024 four-bit cells (1,000 used) that the VIC reads directly; the upper four bits read back as bus noise, so colour data is never checked with the REU's verify.
- **In a cutscene:** an 8 KB bitmap at $6000, its 1 KB colour cells at $5C00 (inside the sprite slot area, which the cutscene does not use for its top band), the text band on screen A, the font in the charset, and actor sprites in the remaining slots.

Scrolling is two things. The VIC scrolls 0 to 7 pixels in hardware through two registers; that is free. Every eighth pixel the screen matrix (1,000 bytes) must move one cell, and the new column or row must be filled. The engine already does this (milestone E1): the shift is two DMAs through REU scratch, the fill comes from the metatile library, and the whole update runs in the border. Its worst case measured in VICE is about 9,200 cycles against a 6,000-cycle target; the fill is the next optimisation. So the answer to "does it scroll" is: the hardware does the fine part, the engine does the coarse part, and games see a camera position.

Bitmaps do not scroll. A cutscene set is a fixed 320 x 200 picture; a pan would move 9 KB per cell step and is out of scope. A scene that needs a wider world is two sets and a cut.

---

## 5. Game state in chunks

State is split by how often it changes and how much of it is near the player.

**Hot state (resident, $E000, at most 8 KB).** The player, the vehicle the player is in, the active entity table (32 entities x 32 bytes = 1 KB), wanted level, timers, mission registers the current script is using, the camera. Everything the frame loop reads. Never paged.

**Sector state (paged, 256 bytes per sector).** The world is 64 x 64 sectors of 32 x 32 metatiles. Each sector has one 256-byte record in the REU: parked vehicles with their damage, destroyed props, pickups taken, doors unlocked. The engine keeps a 3 x 3 ring of sector records around the camera (2.3 KB in the tables area). When the camera crosses a sector edge, one row or column of three records is written back and three new ones are read: six DMAs, 2,000 cycles, once per sector crossing. Entities spawn from the sector record when it becomes active and are written back to it when it drops out. All 4,096 sectors together are 1 MB of REU; nothing about a sector the player is not near is ever in RAM.

**Global tables (paged by key).** Owned property, garage contents, the phone book, mission completion flags, radio state, statistics. Fixed-size records in the REU, read through the page cache when a screen or a script asks for one. A property record is one page fetch; a script checks a mission flag with one opcode that the VM serves from the cache.

**The save file ($7E0000, 64 KB).** Saving is not a serialisation pass. Hot state is stashed (8 ms), the active sector records are written back, and the 64 KB region is then the save. In VICE the REU image is written back to disk on exit with `-reuimagerw`; on real hardware the 64 KB goes to disk with a fastloader in about ten seconds. Loading is the reverse. The whole game's persistent state fits in the 64 KB because sector records only exist for sectors the player has changed; the packer writes the unchanged ones as a shared default.

**What this costs the frame.** Per frame: nothing, unless a sector edge is crossed, and then 2,000 cycles in the border. The design goal is that the frame loop never waits for a read it did not schedule the frame before.

---

## 6. The rule that keeps the core small

Assembly is for work that runs every frame or moves bytes: the scroller, the multiplexer, the raster splits, the DMAs, the VM's dispatch loop, and the syscalls that wrap the primitives. Everything else is p-code in the REU: cutscene direction, mission logic, pedestrian and driver behaviour, menus, dialogue flow.

The measure is the resident code size in `build/cutscene.map`. Today:

| Module | Code | Tables | Purpose |
|---|---|---|---|
| core | 395 | | init, frame loop, interrupt dispatcher |
| reu | 202 | | DMA primitives, tileset and sprite bank loaders |
| scroll | 1,171 | 562 | screen shifts, metatile fills, edge streaming |
| sprites | 549 | 33 | 24-sprite multiplexer with slot streaming |
| hud, text, bench | 519 | 31 | HUD band, text, cycle counter |
| cut | 2,010 | 50 | stills, blocks, objects, text band, shimmer, park |
| vm | 1,713 | 90 | 45 opcodes, 8 threads, 32 variables, p-code from the REU |
| page | 139 | | eight-page cache |
| **total** | **6,722** | **766** | of the 8 KB reserved |

The VM cost 916 bytes and removed 724 bytes of scene-specific assembly (the drive ramp, the beacon, the actor mover). Every future scene, mission, and behaviour costs zero bytes of resident code. A new opcode is added only when it wraps a primitive that must be assembly; a new behaviour is never an opcode.

### P-code versus assembly, measured

`make bench` times one VM tick against the same work in assembly. Three builds of the VM so far: the first fetched every operand byte through a subroutine; the second ran p-code from the REU through the page cache with a page-relative fetch; the third (current, 2026-09-17) dispatches the Å-machine way: the opcode byte is a doubled index stored straight into the low byte of a `jmp (vector)` through a page-aligned table, 17 cycles from one opcode to the next, with the budget charged on taken jumps only.

| Work | First VM | Second VM | Current VM | Assembly |
|---|---|---|---|---|
| 64 x LOOP (16-bit decrement, taken jump) | 247 per opcode | 142 | 116 | |
| 63 x ADD v, w then YIELD | 194 per opcode | 116 | 92 | |
| the cutscene drive body, 16 opcodes a step | 4,000 per step | 2,350 | 1,464 (82 per opcode) | 214 per step |

So a VM opcode now costs 82 to 116 cycles, and the drive loop runs 6.8 times slower as p-code than as assembly, down from 19 at the start. What remains is mostly operand fetching (9 cycles a byte, two to four bytes an opcode) and the register save around each operand pair; the arithmetic itself is 30. The next lever is fatter opcodes for common pairs, not a faster dispatcher. The honest ratio to design around is seven times assembly.

What it means for budgets: the cutscene's two threads run about 26 opcodes a frame, about 2,300 cycles. The plan's 1,500-cycle script budget is about 16 opcodes a frame. Neither number is enough for anything per entity per frame, which is the point of the rule: p-code decides, and the assembly hooks run what it decided for as many frames as it takes.

The VM is 2,208 bytes of code plus a 256-byte vector table: 430 bytes more than the second build, all of it the operand fetch inlined at every use (7 bytes instead of 3). That is the trade the dispatcher makes, and the roadmap's page table with a pin bit will not change it.

Three rules learned while moving the scene into the VM, all now in the engine:

1. The interrupt saves and restores the zero-page scratch it shares with the main loop, so a DMA set up in the main loop cannot be hijacked by a DMA in the vertical blank.
2. A DMA's register writes run with interrupts masked, so no interrupt can start its own DMA between the setup and the go.
3. The VIC control register is never read back and rewritten. Bit 7 reads as the raster's high bit, and writing it back in the lower border sets the raster compare to a line that never comes.

---

## 7. Order of work

1. **Page cache** in the data engine (E0.5): eight pages, linear lookup, round-robin. About 300 bytes.
2. **VM threads run from the REU:** the thread program counter becomes 24 bits and `vm_fetch` reads through the cache. Scripts leave the PRG.
3. **Sector records** with the 3 x 3 ring, spawn and write-back hooks.
4. **Overlay loader** with the two regions and the resident-check.
5. **Save and load** as the 64 KB stash.

Each step is measured in VICE with the benchmark counter before it is called done.

---

## 8. Aggressive paging

The strategies themselves, with costs and the rules for what cannot be paged, are catalogued in `docs/PAGING.md`.

The policy on top of section 3: nothing is resident because it might be needed; it is resident because it is needed this frame or the next, and it was fetched before that. Every paged thing is a fixed-size record at a computed REU address, so paging is arithmetic and never a search.

**P-code is paged.** A thread's program counter is a 24-bit REU address, split as a script base and a 16-bit offset, so opcode operands and the `V_*` macros keep their 16-bit addresses and a script can be 64 KB. The VM reads through an eight-page cache of 256-byte pages at $C100-$C8FF. Each thread keeps a pointer to the page it is on, so the hot fetch is `lda (page),y` plus an increment: the same cost as reading from RAM. Only when the offset's low byte wraps does the VM look the next page up in the cache, and only a miss costs a 361-cycle DMA. A loop that spans two pages settles into the cache and never misses again. Strings and tables are read through the same fetch, so TEXT copies its line into a 40-byte buffer and LDT is one cached read. Scripts leave the PRG entirely; the cutscene example's 339 bytes of script become 0 resident bytes, and a mission script can be as long as it needs to be. Thread contexts are 16 bytes, so sleeping and waiting threads can live in the REU too, and eight resident threads become sixty-four for a few hundred cycles of DMA a frame.

**Map traversal prefetches by heading.** The sector ring is 3 x 3 for state, but the fetch runs one row or column ahead in the direction of travel, so a crossing never waits; at 2 px a frame the camera gives seconds of warning. A region border is known sectors in advance, so the 12 KB tileset arrives in 1 KB pieces over twelve frames into a second, inactive library instead of one 12 ms hit. That second library costs 8 KB, the one place this strategy spends RAM to buy smoothness. When a sector record loads, the sprite frames its entities need are streamed into free slots before they are visible.

**Screens are packages.** A detail screen, phone, garage, or pause menu is one REU slot holding its overlay code, its screen data, its text and its font, built by the packer. Opening it is one 8 KB DMA under a blanked frame; closing it is forgetting it. Nothing about any dialog is ever resident. Portraits, vehicle stats and mission text are fixed-size records fetched by arithmetic through the page cache.

**Engine code pages by mode.** The scroller is dead during a cutscene and the cutscene module is dead during play. Each becomes a mode overlay, freeing about 2 KB of core for whichever mode is running. The rule that the render path never depends on an overlay still holds: the render path for the current mode is resident.

**Assets that need not be resident.** Music patterns stream page by page; charset animation frames (water, neon, traffic lights) are 8-byte characters DMA'd into the charset each frame with no resident tables; HUD furniture is pre-rendered screen chunks, so the HUD code is only the numbers.

**Revised order of work.**

1. Done: page cache at $C100, `src/b64_page.s`.
2. Done: p-code from the REU; the example script left the PRG.
3. Heading prefetch for sector records, then the split tileset swap.
4. Screen packages and the overlay loader.
5. Mode overlays for the scroller and cutscene modules.
6. Save and load as the 64 KB stash.
