# backlot-64 Engine Plan

backlot-64 is the engine under Priors-64. It has two halves. The rendering half owns everything the VIC-II draws: the scrolling character-mode playfield, tilesets and palettes, hardware sprites and their multiplexing, raster splits, text, and screen transitions. The data half owns expansion memory: it treats the REU as the program's real memory and the 64 KB as a cache, streaming world data, assets, and code overlays in and out by DMA. Together they are what lets a C64 in VICE run a program whose memory requirements are measured in megabytes.

The engine core does not own game logic. Physics, AI, pathfinding, collision, scripting, and sound are optional modules, all in assembly, that a game selects in a manifest and pays for in resident RAM and frame cycles. Missions, world design, and the game's own rules belong to the game built on it.

The name is a joke with a serious constraint behind it: the engine is meant to be reused by more than one game, so its boundaries, data formats, and calling conventions are specified up front rather than grown inside Priors-64.

---

## 1. Principles

1. **Rendering is assembly, always.** Every routine that runs per frame is hand-written 6502. No interpreter, no generated code, no overlay swapping inside the render path. The engine core is resident for the whole session.
2. **The VIC-II does the work whenever it can.** Hardware fine scroll, hardware sprites, hardware sprite expansion, shared colour registers, raster interrupts. CPU pixel-pushing is the last resort.
3. **Expansion memory is the real memory.** The REU holds the world, tilesets, sprites, fonts, scripts, and every non-resident piece of code. The 64 KB is a cache the engine manages. The engine fetches exactly the bytes a frame needs by DMA. Nothing is cached "just in case."
4. **DMA is the blitter and the loader.** The REU copies a kilobyte in a kilocycle with the CPU halted. Screen shifts, colour RAM shifts, charset swaps, palette swaps, and code overlays are DMA jobs, not CPU loops.
5. **Data-driven.** Tilesets, worlds, sprite banks, fonts, and raster split tables are packed by tools and loaded by slot number. The engine has no art in it.
6. **Budgets are contracts.** Every subsystem has a worst-case cycle budget per frame, and a benchmark harness that measures it in VICE. A change that breaks a budget is a regression.

---

## 2. Target hardware

The engine has two platforms. A game targets one or both from the same source and the same assets; only the manifest and the platform layer differ.

| | C64 platform | C128 platform |
|---|---|---|
| Machine | C64, PAL first, NTSC pass at the end | C128 in native mode, PAL first |
| CPU | 6510 at 1 MHz | 8502 at 1 MHz during display, 2 MHz in the border |
| RAM | 64 KB | 128 KB in two banks through the MMU |
| Video | VIC-II | VIC-IIe, same capabilities, plus a VDC 80-column chip on its own RAM |
| Storage | REU of at least 8 MB (VICE, Ultimate 64, 1541 Ultimate II+, real 1750 upgraded) | Same REU; the C128 supports it natively |
| Input | Joystick port 2, keyboard | Same |
| Emulator | `x64sc` | `x128` |

**C64 frame budget** on PAL: 312 lines, 63 cycles per line, 19,656 cycles per frame, less badline stalls of roughly 40 cycles on 25 lines of the visible area, giving about 18,600 usable cycles.

**C128 frame budget:** the same during the 200 displayed lines, because the VIC-IIe cannot display in 2 MHz mode. The engine switches to 2 MHz for the 112 border lines and back before the display starts. That is 7,056 border cycles at 1 MHz becoming 14,112, so about 25,600 usable cycles per frame, 38 percent more than the C64. The gain is CPU only. REU DMA runs at 1 MHz on both machines, so the scroller's DMA blits cost the same and the extra time goes to modules, scripts, and audio.

### 2.1 The C128 platform layer

The C128 is treated as a C64 with three additions, and the engine uses each for one thing.

**Bank 1 as resident RAM.** The VIC sees one 64 KB bank, and the engine keeps it, the screens, the charset, the sprite bank, the metatile library, and every module that hooks the per-entity path in bank 0, exactly as on the C64. Bank 1 holds everything that was fighting for the game's 20 KB: the VM and its page cache, all overlay modules made permanently resident, extended entity data, audio, and the persistent state. Code in bank 1 is reached through a far-call trampoline in the MMU's common area, about 35 cycles per call, so the rule is the same as for overlays: nothing per entity per frame lives there. On the C128 the overlay loader still exists but is never invoked, because every overlay slot is resident from init.

**2 MHz in the border.** The raster interrupt at the bottom of the display sets fast mode; the one before the top clears it. The frame contract's border window becomes the place for CPU-heavy, VIC-independent work: the VM's script budget, path/graph expansion, and audio mixing. The manifest's script budget default rises from 1,500 to 4,000 cycles because the border can absorb it.

**The VDC as a development console.** The 80-column chip is too slow to write for gameplay and needs a second monitor on real hardware, so the engine does not use it for the player. Debug builds put a live console on it: the frame's cycle count per hook, the entity table, the running script threads, the last twenty events, and the benchmark harness output. `x128` shows the VDC in its own window, which makes it the best debugger the project will have. Release builds leave the VDC blank.

**Trading memory for cycles.** Bank 1 is also how the C128 runs faster per-entity modules, not only more of them. On a 6502, memory buys speed through lookup tables: a 512-byte squares table turns an 8-bit multiply from 150 cycles into 30, a sine table replaces rotation math, a per-sector distance field turns pathfinding into a table read, a line-of-sight table replaces a tile ray. The C64 has no room for these. The C128 has 60 KB of bank 1 for them.

The mechanism: the MMU's common area is set to the low 16 KB, so the engine core and the per-entity modules at $0800 to $3FFF are visible in both banks. Hot code selects bank 1 with one store to $FF00, reads its table, and selects bank 0 with another. That is 8 cycles of overhead per lookup against savings of 50 to 120. The VIC keeps reading bank 0 throughout, because its bank select is a separate MMU register.

A module that has a table-accelerated variant declares it as a fourth tier, `premium+tables`, that only the C128 manifest can select. It has the premium tier's behaviour, a larger footprint in bank 1, and a lower per-entity cost:

| Module | premium | premium+tables (C128 only) |
|---|---|---|
| physics/sim | 2.5 KB, 180/ent | 2.5 KB + 3 KB tables, 110/ent. Squares and sine tables. |
| ai/tactical | 4.0 KB, 300/ent | 4.0 KB + 12 KB tables, 190/ent. Line-of-sight table, per-sector distance fields. |
| path/graph | 3.0 KB, 200 budgeted | 3.0 KB + 8 KB tables, 80 budgeted. Cached routes and a heuristic table. |
| collision/swept | 1.5 KB, 90/ent | 1.5 KB + 1 KB tables, 60/ent. |

In the points rule a `premium+tables` tier counts 2 points rather than 3, which is what makes two premium per-entity modules affordable on the C128 where they are not on the C64.

Everything else is identical. Tilesets, world, sprites, fonts, scripts, and music are byte-for-byte the same files on both platforms. The REU image is the same image.

---

## 3. What the engine draws

### 3.1 Playfield

Multicolour character mode, 40x25 cells, hardware fine scrolled in 8 directions, 38-column and 24-row mode so the fill edges stay hidden. Two screen buffers in the VIC bank. Colour RAM is single-buffered and updated in the vertical border.

A frame with a one-cell scroll in both axes costs:

| Step | Cycles | How |
|---|---|---|
| Screen shift, front to back buffer with offset | ~2,000 | DMA stash 999 bytes to REU scratch, DMA fetch 999 bytes back at the new offset |
| Colour RAM shift | ~2,000 | Same, in the border window so it never tears |
| Fill new column (25 cells) and new row (40 cells) | ~1,500 | Metatile lookup and expand |
| Metatile fetch for the new column and row | ~400 | 8 one-byte DMAs for the column, 1 eleven-byte DMA for the row |
| Register writes and buffer flip | ~50 | |
| **Worst case** | **~6,000** | About a third of the frame |

A frame with no cell crossing costs under 100 cycles for the scroll register update.

**Measured (E1, 2026-09-15):** no-crossing frame 173 cycles. Crossing frame 6,601 cycles for the preparation (shift DMA plus both fills) and about 2,600 for the vertical-border colour shift and staged writes, roughly 9,200 in total, or half the frame. Above target. The fills are the remaining cost, about 45 cycles per cell over 65 cells, and are the next optimisation: unrolled expansion and a single DMA for the column's metatiles once the world is stored in 8-row bands.

### 3.2 World

The world is a flat 2048x2048 array of metatile indices in the REU, 4 MB. Address is `(y << 11) | x`, so a metatile lookup is three register writes and one DMA. A metatile is 4x4 cells, 32x32 pixels. At Priors-64's scale of roughly 2.5 metres per cell, a metatile is 10 metres and the world is 20.5 km on a side, about 420 square kilometres. Any estimate of GTA VI's map fits inside that with room to spare.

There is no map window in main RAM. The scroller fetches the metatiles under the new screen column or row directly from the REU when it needs them. The whole world is always "loaded."

### 3.3 Tilesets

A tileset is one charset (2 KB), one metatile library (256 metatiles, 16 cell indices and 16 cell colours each, 8 KB), and one properties table (256 bytes: solid, road direction bits, water, door, ramp). A tileset also carries its day and night variants: two charsets and two colour tables, with one metatile library shared. Regions of the world are assigned tileset slots by a 64x64 region table, one byte per 32x32-metatile sector.

**Core and regional halves.** For a world with several outdoor regions, the charset is split: cells 0 to 95 are the *core*, identical in every outdoor tileset and never using shared colour 2; cells 96 to 191 are *regional*; 192 to 255 are the font. Metatiles built only from core cells are core metatiles. The world tool guarantees a band of core metatiles at least one screen wide on both sides of every region boundary. A region change is then a swap of the regional 768 bytes of charset, the regional metatile entries, and one shared colour register, done when the camera's sector changes while only core metatiles are on screen. It costs about 1,500 cycles and is invisible. Two of the three shared colours are fixed for all outdoor tilesets in a world; the tileset tool enforces that core cells dedupe to the same indices in every regional tileset.

A full tileset switch, for interiors or a different world, is a DMA of 10 KB, about 10,000 cycles, spread over two frames behind a raster-timed colour ramp so it never shows. Switching day and night within a tileset is a 4 KB DMA plus register writes.

### 3.4 Sprites

Eight hardware sprites multiplexed to 24 virtual sprites, sorted by Y each frame with an insertion sort, repositioned from a chain of raster interrupts. Hardware sprite 0 is pinned for the object that must never flicker, the player; two more pinned slots are planned.

**Frames are streamed per slot, not loaded in banks.** Each of the 25 sprite slots owns 64 bytes of VIC RAM. A game submits a sprite with its slot number and the 24-bit REU address of the frame it wants; the engine compares that address with what the slot holds and DMAs the 64 bytes only when it differs. An entity keeps the same slot from frame to frame, so a car driving straight costs nothing and a car turning costs one 100-cycle DMA. The resident sprite memory is 1.6 KB, and the number of distinct sprite designs that can be on screen at once is simply the number of slots. This is what lets a game have 150 vehicle types in traffic with no bank juggling. A worst case where every visible sprite changes frame in the same frame is 24 DMAs, about 2,400 cycles, and does not happen in practice.

**Beacon overlays.** A sprite can carry a second, single-colour sprite attached at an offset: a light bar, a rotor, a wake. The overlay takes one slot and one virtual sprite, follows its parent's position, and can step through a pattern table of (left, centre, right, frames) entries, each light one of the 16 colours or off. Patterns are data. Emergency services get distinct rhythms so a player can tell a police cruiser from an ambulance from a fire engine at the edge of the screen without reading the sprite. A hires overlay can use any of the 16 colours, which is how a red and blue light bar sits on a white multicolour car. Cost: one slot per beacon, and about 30 cycles per frame per beacon for the pattern step. The lighting module treats an active beacon as a light source, so at night the walls flash with it.

Budget: 24 sprites, about 3,000 cycles including the sort and the interrupt chain. Measured E3: a static frame with 20 multiplexed cars costs about 1,700 cycles.

### 3.5 Raster effects

A split table of up to 8 entries, each a raster line and new values for the three shared colours and optionally the charset pointer. Used for horizon bands, beach strips, HUD rows, and interior lighting. Each split costs about 60 cycles of interrupt overhead.

Charset animation: up to 8 cells redefined per frame from an animation table in the REU. Water, neon, traffic lights, fire. Every instance on screen animates for the price of 64 bytes of DMA.

Colour RAM cycling: a list of up to 16 cell addresses whose colour rotates through a table. Sign flicker and emergency lights.

### 3.6 Text and HUD

A 4x8 cell font packed into the charset's upper 64 characters in every tileset, so text draws without a charset swap. Routines for a status row, a dialogue box with a portrait, a scrolling text crawl, and a numeric formatter. The HUD lives on rows the playfield does not scroll, separated by a raster split.

### 3.7 Transitions

Fade to black and back by walking the shared colours and the border through a luminance-ordered ramp table, and a cut that swaps both screen buffers under a single blanked frame. Used for interiors, deaths, region loads, and cutscenes.

### 3.8 Cutscenes

A cutscene is layers inside raster bands, because the VIC-II shows bitmap or character mode per line, never both.

| Layer | What | Mechanism | Cost |
|---|---|---|---|
| 0 | The set | A 320x200 multicolour bitmap still streamed from the REU; the original stays in the REU | 10 KB DMA behind a blank |
| 1 | Props | Character blocks converted to bitmap layout and DMA'd into the still at cell positions; restored from the REU original when they move | ~2,000 cycles per placement |
| 2 | Actors | Sprites and sprite grids (4x2 = 96x42, 4x4 = 96x84 through the multiplexer), moving per pixel, with beacon overlays | Free per frame |
| 3 | Text | The bottom rows in character mode through a raster split: dialogue from the font, speaker name, portrait block, letterbox | One split |

Bitmap mode borrows the VIC bank differently from the playfield: bitmap at $6000-$7FFF, its colour cells at $5C00, the text screen at $4000, the font at $4800, actor sprite slots at $5000-$5BFF. The 8 KB at $6000 is game RAM, so the data engine stashes it to the REU when a cutscene starts and restores it at the end, which is two DMAs and the first use of the quicksave path.

Per-cell colours in a still live in screen and colour RAM, so colour cycling works on a set: neon flickers. Charset animation does not apply to bitmaps. The first use is the **shimmer**: the still packer lists the cells below a horizon row that mix two non-background colours, and every fourth frame the engine swaps those two colours' codes by exchanging the nibbles of each cell's screen byte, so the reflection pattern inverts and the wet road moves. About 20 cycles per cell in the border; 80 cells on the Club Bellamar set. The shimmer skips cells under a parked object, and a park or unpark waits for a vertical blank in the shimmer's base phase, at most seven frames, so the block, which was composited against the unswapped still, lands in step with its neighbours. Sets are prompted for clean vertical streak reflections because streaks quantise to bands the shimmer can move, while speckle quantises to noise.

**The engine is also its data contract.** `docs/PREPARE.md` states, for every asset type, how to make it, which tool converts it, and what to check, written so an agent can follow it literally; `CLAUDE.md` at the repository root points there. A game prepared that way runs on the chip.

The script is a VM thread calling the cutscene module: show still, place block, restore, spawn actor, move actor over N frames, say line, flash beacon, wait, cut. All by slot from the REU.

**Objects: one master, two forms.** An object file (`.b64o`, from `tools/b64object.py`) holds a sprite grid and a bitmap block cut from a single master that was quantised once under the sprite rule, three colours plus transparent. Because three global colours never exceed a bitmap cell's three, the block is pixel-identical to the sprites, and an actor can stop and become a prop with no visible change. Transparent pixels in the block are composited at pack time, either over a flat floor colour or over the actual still at the cell where the object will park; in the still case the packer also emits a patched still whose cells under the object use the same reduced colour sets, so parking changes no pixel outside the object. The park itself is deferred to the vertical blank and runs in the same interrupt that swaps the sprite list, so the sprites vanish as the block appears. Measured on the cruiser: 12 pixels differ between the frame before and after the park, all of them the beacon lamp. The file has fixed offsets (header, per-row visible cell spans, sprite frames, bitmap rows, screen, colour) so the engine needs no parsing; the spans let a blit skip fully transparent cell rows.

Objects also carry a checkerboard shadow (a half-brightness shade identical in both forms; exact darkening through the luminance ladder is reserved for bitmap-only art) and procedural wheel frames: the packer finds the wheel discs, redraws their spokes at four angles, and stores the affected sprites per frame in an animation section; the engine's per-frame animation override selects the frame, and the drive primitive advances it every 2.5 pixels travelled so wheel speed follows road speed.

**Assembly versus p-code.** The line is per-frame work and byte moving. Engine assembly: the still, block and object DMAs, the sprite grid submission, the multiplexer, the raster splits, the shimmer, and the VM's dispatch loop. Everything the scene decides is p-code: the drive with its speed ramp and ease-out, the wheel frame advance, the beacon's lamp pattern, the timing, the text. The scene is a byte script (`VM_OP_*` and the `V_*` macros in `include/b64.inc`) that a game supplies; the engine runs it from `b64_vm_start` and `b64_vm_tick`. The VM (`src/b64_vm.s`, 916 bytes) has 45 opcodes: control (WAIT, YIELD, JMP, SPAWN, CALL, RET, LOOP), 16-bit variables with arithmetic, compares and table lookups, and a syscall bridge to the cutscene primitives. Eight threads run round-robin once per frame; a scene is a main thread that directs and a draw thread that submits sprites every frame. Moving the scene into the VM removed 724 bytes of scene-specific assembly. A new behaviour is never a new opcode; an opcode is added only to wrap a primitive that has to be assembly. The memory strategy, and why the resident core must stay small, is `docs/MEMORY.md`; the paging strategies are `docs/PAGING.md`.

Planned on top of objects: further parts (doors, light bar) with generated sequences, hooks for attaching overlays and spawning other objects (a pedestrian at the door), and per-part layers respected by the multiplexer's sort.

### 3.8 Data engine

The data engine is the layer that makes the REU behave like the program's memory. Everything else in the engine, and everything in the game, goes through it.

**Fetch and stash.** `b64_fetch` and `b64_stash` move up to 64 KB between a 24-bit REU address and a 16-bit C64 address in one DMA. Cost is about one cycle per byte plus 40 cycles of setup. The REU registers are written directly. There is no queue, no interrupt, no asynchrony: DMA halts the CPU, so when the call returns the bytes are there.

**Slots and the manifest.** Nothing in the engine or the game hard-codes an REU address. The packer lays out the image from a manifest and emits an include file of slot symbols. A tileset is slot 3, a sprite bank is slot 41, a code module is overlay 7. Renumbering the image is a rebuild, not a code change.

**Page cache.** For data that is read sequentially in small pieces, such as bytecode for the game's VM, dialogue text, or path tables, the engine keeps a small cache of 256-byte pages in main RAM with a 4-entry associative lookup. A page hit costs a compare. A miss costs one 256-byte DMA. This is what lets the game's scripts run from the REU without either loading whole scripts or paying DMA setup per byte.

**Code overlays.** Code cannot execute from the REU, so non-resident code is stored there in 8 KB overlay slots assembled to run at overlay region A ($8000) or region B ($C100). `b64_overlay_load` DMAs a slot in, about 8,000 cycles for a full one, less than half a frame. The engine tracks which overlay is loaded in each region, so a call to an already-resident overlay costs nothing. Overlays are for non-rendering work only: the interior editor, the map screen, the radio tuner, the save system, the cutscene player, the mission compiler's runtime tables. The render path never depends on an overlay being present. The rule is written down so it stays true: a routine in the frame contract's engine rows must live in the resident core.

**Persistence.** The game stashes its state to the REU's persistent region as it changes, one DMA per record. A save to disk or cartridge is a stash of that region. A load is a fetch. Saved games are the same size as the region, 64 KB, and take under a second either way.

**Two lessons from E12.** The VIC-II reads sprite pointers from the end of whichever screen memory is active, so the multiplexer writes them to the bitmap band's colour-cell screen as well as both playfield screens. And the bitmap at $6000 overlaps game RAM, so anything a game keeps alive through a cutscene must live in the $E000 region or in the REU.

**Verification.** At init the engine checks the REU is present and at least the size the manifest needs, and refuses to start with a clear message on screen if not. The image carries a checksum per slot, verified on load in debug builds.

---

## 4. Modules and the feature picker

The engine core is fixed. Everything a game needs beyond drawing is a module: a self-contained unit of assembly with a header that declares what it costs. A game picks the modules it wants in a manifest, and the build refuses any combination that does not fit the machine. That is the feature picker: not a menu of free options, but a budget you spend.

### 4.1 Why modules

The 64 KB and the 18,600 cycles per frame are the whole machine. A game that wants simulation-grade vehicle physics is choosing to have less room and less time for AI, and vice versa. Making that trade explicit at build time, with numbers, is better than discovering it at 40 fps six months in. It also means two games on the engine can make opposite choices without forking it.

### 4.2 What a module is

A module is one or more `.s` files assembled into a segment with a 16-byte header:

| Field | Meaning |
|---|---|
| name, version | For the manifest and the error messages |
| kind | resident or overlay |
| resident size | Bytes of code and tables that must stay in main RAM |
| zero page | Bytes of zero page it needs, allocated by the packer |
| cycles per frame | Fixed cost, measured by the benchmark harness |
| cycles per entity | Marginal cost per active entity it processes, measured |
| hooks | Which frame contract points it attaches to: frame, entity, border, init |
| entry table | Exported routines, by index, so callers do not need its addresses |
| syscall table | The subset of entries exposed to scripts as VM opcodes, with argument signatures |

Resident modules are linked into the game's resident regions at build time and run every frame. Overlay modules live in REU overlay slots and are loaded by the data engine when called. A module declares which it is, and the rule from the data engine section holds: anything hooked into the per-frame contract is resident.

### 4.3 The catalogue

Every category has three tiers. Base is what a game gets for picking the category at all. Plus is a meaningful upgrade at modest cost. Premium is the expensive version that changes what kind of game you can make. Costs are targets to be measured by the benchmark harness and recorded in each module's header. Cycles per entity are per entity updated that frame.

| Category | Base | Plus | Premium |
|---|---|---|---|
| **physics** | **arcade** 1.0 KB, 50 + 60/ent. 8.8 fixed-point velocity, per-vehicle turn rate, tile collision with stop. GTA1 feel. | **grip** 1.6 KB, 80 + 110/ent. Adds drag, skid above a grip threshold, surface friction from tile properties, handbrake turns. | **sim** 2.5 KB, 100 + 180/ent. Mass, momentum transfer between vehicles, damage from impulse, trailers and towing. |
| **ai** | **basic** 1.5 KB, 100 + 80/ent. State machines: idle, walk, drive, flee, attack. Police respond by spawn rate. | **aware** 2.5 KB, 150 + 150/ent. Tile-ray line of sight, flee and attack decisions from what is seen, police intercept rather than chase, groups follow a leader. | **tactical** 4.0 KB, 300 + 300/ent. Cover and flank, roadblocks and pincers, hierarchical pathing on the sector road graph. Requires path/graph. |
| **path** | **road** 0.5 KB, 0 + 20/ent. Follow tile direction bits. Enough for traffic. | **lanes** 1.0 KB, 50 + 35/ent. Lane keeping, intersections with right of way, turn choice toward a target sector. | **graph** 3.0 KB, 200 budgeted. A* over the region road graph in the REU, fixed nodes per frame, results cached per entity. |
| **collision** | **sprite** 0.3 KB, 30. VIC-II hardware sprite collision registers. Cheap and coarse. | **box** 0.8 KB, 50 + 40/ent. Axis-aligned boxes per entity, bucketed by screen column. | **swept** 1.5 KB, 80 + 90/ent. Swept boxes so fast vehicles cannot tunnel, contact normals handed to physics. |
| **entities** | **32** 0.5 KB. 32 slots, 16 bytes each. | **48** 0.75 KB. Adds the round-robin scheduler. | **64** 1.0 KB. Needs the scheduler and a distance-based update rate. |
| **vm** | **core** 2.0 KB, 150. 8 cooperative bytecode threads with event waits and the syscall bridge. Missions and cutscenes. | **ai** 3.0 KB, 250. 16 threads, entity-bound threads that wake on entity events, so pedestrian and driver types are scripts. | **full** 4.0 KB, 400. 32 threads, string and table opcodes, camera opcodes, a debugger hook. |
| **audio** | **sfx** 1.0 KB, 100. One SID voice for effects with a priority table. | **music** 2.5 KB, 400. Three-voice player, effects interleave on voice 3. | **digi** 3.5 KB, 900. Music plus sample playback in the border for voice clips and engine noise. |
| **input** | **joystick** 0.2 KB, 20. | **joystick+keys** 0.5 KB, 40. | **joystick+keys+mouse** 0.7 KB, 60. 1351 mouse for the map screen and interiors. |

Overlay modules (save, mapscreen, cutscene, and any the game writes) have no tier. They cost nothing resident and nothing per frame.

### 4.4 The budget

The packer sums what the manifest selects and checks it against two limits.

**Resident RAM.** The game's resident regions in the memory map total 20 KB. The engine's own core, the module headers, and the game's own code all come out of that. A manifest that picks physics/sim, ai/tactical, path/graph, collision/box, entities/64, vm/ai and audio/music asks for about 17 KB before the game has written a line, and the build says so.

**Frame cycles.** The rendering worst case is about 9,000 cycles. The remaining 9,600 are for modules and the game. The packer computes `fixed + per_entity x active_entities` for the selected modules and reports the total as a percentage of the frame at the entity count the manifest declares. Over 100 percent is an error. Over 80 percent is a warning, because worst cases stack.

The manifest is a small text file:

```
[game]
entities = 32
budget_warn = 80

[modules]
physics   = arcade
ai        = basic
path      = road
collision = box
vm        = core
audio     = music
input     = joystick+keys
overlays  = save, mapscreen, cutscene
```

The packer emits `modules.inc` with the selected modules' entry tables, the zero page allocation, and a linker config with the resident regions laid out, and prints the budget report. Changing a tier is a one-line edit and a rebuild.

### 4.5 Two surfaces: hooks and syscalls

Every module has two faces, and the distinction is the most important rule in the module system.

| Surface | Who calls it | How often | What it is for |
|---|---|---|---|
| **Hooks** | The engine's native frame loop, from the hook table | Every frame, every scheduled entity | Executing. Physics integrates velocity, AI runs the current behaviour, collision tests boxes, audio ticks the player. |
| **Syscalls** | Scripts, through the VM, as opcodes | When a script decides something | Deciding. Spawn a car here, set this pedestrian's behaviour to flee, route this police car to the player, play a siren, give money. |

Scripts decide, hooks execute. Nothing that runs per entity per frame is ever bytecode, because a VM opcode costs about 40 cycles of dispatch on a 6502 before it does any work, and a scripted loop over 32 entities calling three modules each would spend 8,000 cycles on dispatch alone. Equally, nothing that is a game rule is hard-wired into a hook. A hook runs the behaviour a script chose, with the parameters a script set, for as many frames as it takes.

The packer builds both tables. Hooks go into the frame-loop table in manifest order. Syscalls get opcode numbers in a generated `syscalls.inc` that the game's script compiler reads, so `physics.spawn`, `ai.set_behaviour`, `path.route_to`, and `audio.play` are ordinary opcodes, and a bespoke module's syscalls appear next to the catalogue's with no special handling. A syscall is a `b64_mod_call` with arguments marshalled from VM registers, about 60 cycles on top of the routine itself.

**Events, not polling.** A script thread that runs every frame to check whether something happened is a per-frame cost with none of the benefits. Modules raise events instead: `entity.saw_player`, `entity.damaged`, `entity.reached_marker`, `vehicle.entered`, `zone.entered`, `timer.expired`. A thread waits on an event or a timer and costs about ten cycles per frame while it waits. This is what lets a pedestrian type be a script without the VM scaling with the entity count.

**Budget.** The VM gets a script budget per frame in the manifest, 1,500 cycles by default, about 30 opcodes. The scheduler runs ready threads round-robin until the budget is spent and resumes where it left off next frame. At 50 frames per second that is 1,500 opcodes per second, enough for mission logic and a few dozen entity decisions per second, and by design not enough for anything per frame.

Modules attach to the frame contract by declaring hooks, and the engine calls them in a fixed order from a table the packer builds:

| Hook | When | Typical users |
|---|---|---|
| init | Once, after `b64_init` | Everything |
| input | Start of the game callback | input |
| entity | Once per active entity per update, with X = entity | physics, ai, collision, vm/ai |
| frame | After all entity updates | path/graph budget, vm/core, collision/sprite |
| border | Raster 251 to 311 | audio |

Two modules can hook the same point. Order within a hook is manifest order, so a game that wants AI to set velocity before physics integrates lists ai first.

### 4.6 Tiers are not a ladder

The tiers exist so a game can spend where it matters. A racing game on the engine wants physics/sim and ai/basic. Priors-64 probably wants physics/arcade and ai/tactical, because the feel of GTA is in how the city reacts to you more than in how the car slides. A game can also write its own module against the same header format and hook table, and the picker treats it like any other.

### 4.7 Upgrade points

The packer computes the exact budget, but a rule of thumb helps when choosing. Count a plus tier as 1 point and a premium tier as 3. At 32 entities with the round-robin scheduler updating 16 per frame, a game can spend about **6 points on the C64** and stay under 90 percent of the frame with room for its own code. On the **C128 the budget is about 10 points**, because bank 1 removes the RAM constraint entirely and the 2 MHz border adds roughly 7,000 cycles for modules that can run there. Modules hooked per entity still run at 1 MHz during display, so the C128's extra points go two ways: to the VM, audio, path/graph, and entity count, which run in the border, and to `premium+tables` tiers at 2 points each, which are how the C128 affords two premium per-entity modules at once.

| Spend | Example | Modules RAM | Left for game | Frame |
|---|---|---|---|---|
| 1 premium + 2 plus (5) | ai/tactical, path/lanes, collision/box, rest base | 12.3 KB | 7.7 KB | ~83% |
| 1 premium + 3 plus (6) | ai/tactical, physics/grip, path/lanes, collision/box | 11.4 KB | 8.6 KB | ~89% |
| 2 premium (6) | ai/tactical, physics/sim, everything else base, no music | 11.0 KB | 9.0 KB | ~91% |
| 6 plus (6) | grip, aware, lanes, box, 48 entities, music | 11.7 KB | 8.3 KB | ~65% |
| 3 premium (9) | tactical, sim, digi | 13.5 KB | 6.5 KB | over 100% |

Two things the table shows. Plus tiers are cheap in cycles and the budget mostly bites on premiums, so six plus tiers cost less frame time than two premiums. And the RAM side is nearly flat across sensible configurations at 11 to 12 KB, so the game keeps 8 to 9 KB resident either way. The frame is the constraint, not the memory.

The scheduler matters. Without round-robin, updating all 32 entities every frame, the same manifests cost roughly double and only the all-base configuration fits. Any manifest above base should pick entities/48 or better to get the scheduler.

### 4.8 Bespoke modules

A game is not limited to the catalogue. Any category can be filled by a module the game writes itself, and the picker treats it exactly like a catalogue module: same header, same hooks, same budget check, same points. Bespoke modules live in the game's repository, not the engine's, and the manifest points at them by path.

```
[modules]
physics   = @modules/vehicle       ; bespoke, in Priors-64/modules/vehicle/
ai        = tactical
path      = lanes
collision = box
```

**Writing one.** The engine ships a module SDK in `include/b64_module.inc`: a header macro, an entry macro, and a hook macro.

```
        B64_MODULE "vehicle", 1, RESIDENT
        B64_HOOKS  ENTITY | FRAME
        B64_ZP     6                     ; zero page bytes the packer allocates
        B64_COST   120, 140              ; declared cycles: fixed, per entity

        B64_ENTRY  vehicle_spawn         ; index 0
        B64_ENTRY  vehicle_damage        ; index 1
        B64_ENTRY  vehicle_enter         ; index 2

        B64_SYSCALL vehicle_spawn, "vehicle.spawn", ARGS_XY_CLASS   ; visible to scripts
        B64_SYSCALL vehicle_enter, "vehicle.enter", ARGS_ENT_ENT
        B64_EVENT   "vehicle.entered"                              ; raised to waiting threads
```

Entries are the native interface for other modules and the game's resident code. Syscalls are the script interface. A routine can be both. Events are raised with `b64_event` and wake any thread waiting on them.

A bespoke module may call catalogue modules through `b64_mod_call`, so it can be built on top of one rather than from scratch. The common pattern is to select a catalogue tier as a dependency in the header and add to it.

**Declared versus measured.** The header declares a cost. The benchmark harness measures it, in a build with the module's entity hook run over a synthetic entity table, and the build fails if the measured cost exceeds the declared one by more than 10 percent. This is what keeps the points rule honest for modules the engine authors never saw: the packer derives a bespoke module's points from its measured per-entity cost, 0 points at 80 cycles or less, 1 point up to 160, 3 points above that.

**What is not allowed.** A bespoke module cannot hook the render path. It cannot run bytecode from a hook. It cannot own an overlay region. It cannot allocate zero page outside what the packer gives it. It cannot take more than 4 KB resident without a manifest override that says so in writing. The restrictions exist so that a bespoke module is a module, not a fork of the engine.

**Worked example: Priors-64's vehicle physics.** Priors-64 does not want sim physics. It wants arcade handling with the things that make Leonida Leonida. Its bespoke `vehicle` module depends on physics/arcade and adds:

| Addition | What it does | Why bespoke |
|---|---|---|
| Vehicle classes | A table of car, truck, bike, boat, airboat, seaplane, helicopter with turn rate, accel, top speed, mass, and the medium they run on | The catalogue has no notion of medium |
| Media from tile properties | Land vehicles stop at water, boats stop at land, airboats cross both, aircraft ignore tiles and use an altitude byte with a shadow sprite | Grassrivers and the Keys depend on it |
| Hydroplaning | Wet tiles after rain lower grip for land vehicles | Ties into the game's weather flag |
| Ramming | Mass ratio decides who stops on impact, without full momentum transfer | The GTA feel at a fraction of sim's cost |
| Damage staging | Damage byte thresholds swap the sprite frame to dented, then add a smoke sprite, then fire, then explode | Sprite work the physics module should own, not the AI |
| Enter and exit | Vehicle ownership by an entity, door position offsets, the busted-while-in-car case | Game rules, not physics |

Declared cost: 1.8 KB resident, 120 cycles fixed, 140 per entity. That measures as a plus tier, 1 point. So Priors-64's manifest of bespoke vehicle physics, tactical AI, lane pathing, and box collision comes to 5 points and stays inside the budget with the same headroom as the catalogue version.

### 4.9 Engine modules

The catalogue above is game-side: physics, AI, and so on. The engine also has optional modules of its own, rendering and data features that cost frame time or RAM and so live in the manifest rather than the core. The test for inclusion is whether the feature uses the VIC-II, the REU, or the raster in a way people assume the C64 cannot.

Always present in the core: world streaming, the sprite multiplexer with REU sprite banks and sprite stacking, the raster split table, charset animation and colour cycling, palette ramps, text and HUD, the data engine, and the benchmark harness.

| Module | What it does | Why it reads as impossible | Cost |
|---|---|---|---|
| **splitscreen** | Two cameras, two scrollers, one raster split | Two-player co-op on one C64, both halves scrolling freely | ~2 half-height scrollers, about one full |
| **lighting** | Rewrites the character and colour of cells in a cone or radius each frame to lit variants | Headlights sweep the road, streetlights pool, neon glows onto the sidewalk | ~60 cells, ~2,000 cycles |
| **cloudshadows** | Drifting dark multicolour sprites behind the playfield | The world is lit from above and weather has a look | 2 to 4 sprites |
| **weather** | Sprite rain layers, raster lightning flash, wet-road charset swap | A storm rolls in | 4 sprites plus one swap |
| **minimap** | Packs the surrounding world map into a sprite each frame from one DMA | A live radar drawn from the real 4 MB map | ~300 cycles |
| **stills** | Full-screen multicolour bitmaps streamed from the REU behind a fade | Hundreds of painted cutscene frames and the map screen; 10 KB each, 800 per 8 MB | One DMA per still |
| **video** | Streams charset and screen deltas at 12 to 25 fps | Full-motion video from the REU, about 100 seconds per 8 MB | 3 KB DMA per frame |
| **samples** | 4-bit samples through the SID volume register, streamed from the REU | Minutes of digitised speech | ~25 percent of the CPU while playing |
| **replay** | Records entity state per frame to the REU and plays it back | The crash replay; ten seconds of 48 entities is 384 KB | One stash per frame |
| **quicksave** | Snapshots the 64 KB to the REU and restores it | Save anywhere in three frames | 64 KB DMA |
| **proptext** | Renders variable-width text into spare charset cells at runtime | Typeset dialogue on a character grid | ~100 cycles per glyph |
| **camerafx** | Shake, look-ahead, cut, pan | Explosions feel like explosions | Trivial |

First wave, in order: lighting, splitscreen, stills, samples. Video and replay wait for the systems they depend on.

---

## 5. Memory map

The strategy for treating this map as a cache over the REU, with measured DMA times and how game state is chunked, is `docs/MEMORY.md`.

The engine reserves fixed regions. The game gets everything else.

| Range | Size | Owner | Use |
|---|---|---|---|
| $0002-$004F | 78 B | engine | Zero page: camera, scroll state, DMA scratch, sprite list pointers |
| $0050-$00FF | 176 B | game | |
| $0200-$07FF | 1.5 KB | engine | Sprite sort tables, split table, colour cycle list, staged column and row colours |
| $0800-$2FFF | 10 KB | engine | Resident core (7.7 KB used with the VM, page cache and platform layer) |
| $3000-$3FFF | 4 KB | game | Game resident core |
| $4000-$43FF | 1 KB | engine | Screen A |
| $4400-$47FF | 1 KB | engine | Screen B |
| $4800-$4FFF | 2 KB | engine | Active charset |
| $5000-$5FFF | 4 KB | engine | Active sprite bank, 64 frames |
| $6000-$7FFF | 8 KB | game | Except $7FFF, the VIC idle byte, which the engine keeps at 0 |
| $8000-$9FFF | 8 KB | engine | Overlay region A, managed by the overlay loader |
| $A000-$BFFF | 8 KB | engine | Active metatile library: cells at $A000, colours at $B000 |
| $C000-$C0FF | 256 B | engine | Metatile properties |
| $C100-$C8FF | 2 KB | engine | Page cache: eight 256-byte copies of REU pages |
| $C900-$CFFF | 1.75 KB | engine | Overlay region B, for small modules that must coexist with a region A module |
| $D000-$DFFF | 4 KB | I/O | VIC, SID, CIA, REU registers at $DF00 |
| $E000-$FFF9 | 8 KB | game | Entity tables and game state |

BASIC and KERNAL ROMs are banked out at init and never return. The engine provides its own IRQ chain and expects the game to hook a per-frame callback rather than install its own interrupts.

### REU layout

| Offset | Size | Contents |
|---|---|---|
| $000000 | 4 MB | World, 2048x2048 metatiles |
| $400000 | 4 KB | Region table, 64x64 sector to tileset slot |
| $401000 | 16 x 12 KB | Tileset slots 0-15: charset day, charset night, metatile cells, colours day, colours night, properties |
| $431000 | 64 x 4 KB | Sprite banks 0-63 |
| $471000 | 8 KB | Fonts and portraits |
| $473000 | 4 KB | Charset animation tables |
| $474000 | 256 x 8 KB | Code overlay slots 0-255 |
| $600000 | to $7EFFFF | Game heap on an 8 MB REU (`b64_heap_alloc`); the packer never places assets here |
| $7E0000 | 64 KB | Game persistent state: parked vehicles, mission flags, owned property, stashed by the game and restored at load |
| $7F0000 | 64 KB | Engine scratch: shift buffers, page cache backing |

The engine ships a Python packer that lays out this image from a manifest, and VICE loads it with `-reuimage`. On real hardware a boot loader fills the REU from cartridge or disk once per session.

---

## 6. Frame contract

The engine owns the raster interrupt chain. One frame, in order:

| Raster | Who | What |
|---|---|---|
| 0 | engine | Apply scroll registers and buffer flip prepared last frame. Start the sprite chain. |
| 0 to 249 | engine | Sprite multiplexer interrupts at each reuse point. Raster splits at their lines. |
| 0 to 249 | game | Main loop: the game's per-frame callback runs here in the gaps. It reads input, updates entities, and calls engine functions to set the camera and submit sprites. |
| 250 | engine | Vertical border work: colour RAM shift by DMA, staged colour fills, charset animation, colour cycling, then latch the next frame's scroll and flip. |
| 251 to 311 | engine | Remaining border time is spare. Music drivers conventionally hook here. |

The game callback must return before raster 250 to have its changes shown this frame. If it overruns, the engine shows the previous state for one more frame and nothing tears.

---

### 6.1 Where per-frame work runs

Measured with `-DFRAME_TRACE` on the cutscene example, 2026-09-17, after a stall was traced to the shimmer running inside the vertical-blank interrupt:

| Where | What | Cost today | Rule |
|---|---|---|---|
| Vertical-blank interrupt | Take the finished sprite list and write the first hardware sprites, then the mode's blank work (bitmap registers, a deferred park or unpark) | about 2,200 cycles | Short, and the sprite registers first so they are always written in the border. Nothing here may cost more than a few hundred cycles. |
| Main loop, the game callback | The VM tick: every ready thread, the sprite grid submission, the frame streaming, the list sort | about 9,600 cycles on the cutscene | The game's budget. The engine measures it and the VM budget scales with the tier. |
| Main loop, engine effects | `b64_cut_frame`: the reflection shimmer every fourth frame; later colour cycling and charset animation | about 3,000 cycles on a shimmer frame | Background effects live here, after the callback and before the rows they touch are drawn, so they cost frame time and never interrupt latency. Each effect declares its cost. |

The frame holds when the three together stay under the 19,656 cycles a PAL frame has. A background effect that cannot fit is spread over frames, not moved into the interrupt: the shimmer running in the blank cost 8,700 cycles there and made the car hold still one frame in four.

---

## 7. API

Calling convention: `jsr` with arguments in zero page variables owned by the engine, A/X/Y for short arguments. All routines preserve nothing unless stated. Symbols are prefixed `b64_`.

### Lifecycle

```
b64_init            Bank out ROMs, set VIC bank, clear screens, install IRQ chain, verify REU.
b64_set_callback    A/X = address of the game's per-frame routine.
b64_run             Never returns. Runs the frame loop.
```

### World and camera

```
b64_load_tileset    A = tileset slot. Streams the tileset over two frames.
b64_set_time        A = 0 for day, 1 for night. Swaps charset and colour tables.
b64_set_camera      b64_cam_x, b64_cam_y (16-bit world pixels). Takes effect next frame.
b64_move_camera     A = dx, X = dy, signed, up to +/-8. Common case, cheaper than set.
b64_redraw          Full screen rebuild from the current camera. Used after cuts.
b64_peek_tile       b64_cam-relative cell coordinates in X/Y. Returns metatile properties in A.
b64_tile_at         b64_wx, b64_wy world cell coordinates. Returns properties in A. One DMA.
```

### Sprites

```
b64_spr_begin       Clear this frame's virtual sprite list.
b64_spr_add         b64_spr_x (16-bit), b64_spr_y, b64_spr_slot (1-24), b64_spr_colour,
                    b64_spr_flags (multicolour, behind-playfield), b64_reu = REU address of
                    the frame. The frame is fetched only if the slot does not already hold it.
b64_spr_pinned      b64_reu = frame for hardware sprite 0, slot 0. Same caching.
b64_spr_overlay     Attach a beacon overlay to the last added sprite: b64_reu = overlay frame,
                    A = pattern id, X/Y = offset. Uses the next slot. Patterns are packed data.
b64_spr_end         Sort and build next frame's multiplexer chain.
```

### Raster and effects

```
b64_split_set       A = entry 0-7, X = raster line, b64_split_bg1/bg2/bg0, b64_split_charset.
b64_split_clear     A = entry.
b64_anim_set        A = animation table id. Enables charset animation.
b64_cycle_add       b64_wx/b64_wy cell, X = table id. Adds a colour-cycled cell.
b64_fade_out        A = frames. Non-blocking, completes over A frames.
b64_fade_in         A = frames.
b64_cut             Blank one frame and redraw. For scene changes.
```

### Text

```
b64_text            A = row, X = column, b64_ptr = string. Draws to the HUD rows.
b64_number          A = row, X = column, b64_val (24-bit). Right-aligned decimal.
b64_dialog          b64_ptr = text, A = portrait id. Opens the dialogue box.
b64_dialog_close
```

### Data engine

```
b64_fetch           b64_reu (24-bit), b64_ptr (C64 address), b64_len (16-bit). REU to RAM.
b64_stash           Same arguments. RAM to REU.
b64_slot_addr       A = slot id. Returns its REU address in b64_reu and size in b64_len.
b64_page            b64_reu = any REU address. Returns a pointer to the cached page
                    containing it in b64_ptr, fetching on a miss.
b64_overlay_load    A = overlay id. Loads it into its region if not already resident.
b64_overlay_call    A = overlay id, X = entry index. Loads if needed, then calls.
b64_state_stash     A = record id. Writes one game state record to the persistent region.
b64_state_fetch     A = record id.
```

### Modules

```
b64_mod_call        A = module id, X = entry index. Calls an exported routine of a resident
                    module, or loads and calls an overlay module.
b64_mod_hooks       Runs one hook point. Called by the engine, not the game.
b64_syscall         A = syscall number. Marshals VM registers and calls the module entry.
                    Called by the VM, not the game.
b64_event           A = event id, X = entity. Wakes threads waiting on it. Called by modules.
```

### Debug

```
b64_bench_begin     Start the CIA cycle counter.
b64_bench_end       Stop and return elapsed cycles in b64_val.
b64_bench_show      Print the last measurement to the HUD.
```

---

## 8. Data formats and tools

All packing is Python 3 in `tools/`, invoked by `make`. Source art is PNG or the canvas-drawing DSL already used for the Priors-64 zone demos.

| Format | Tool | Notes |
|---|---|---|
| Tileset `.b64t` | `b64tileset.py` | Renders metatiles on a canvas, enforces VIC-II per-cell colour rules, dedupes cells into a charset of at most 192 (64 reserved for the font), emits day and night variants |
| World `.b64w` | `b64world.py` | 2048x2048 metatile bytes plus the region table. Generated procedurally from a region layout and hand-authored overrides in Tiled |
| Sprite bank `.b64s` | `b64sprites.py` | 64 frames of 64 bytes from PNG sheets or the ASCII sprite DSL, with rotation and flip derivation |
| Font `.b64f` | `b64font.py` | 64 cells |
| Object | `b64object.py` | One PNG to a sprite grid and a bitmap block that match pixel for pixel; composites over a floor colour or over a still at a parking cell and emits the patched still |
| Overlay module | `b64overlay.py` | Assembles a module against region A or B, checks it fits 8 KB, records its entry table |
| Module SDK | `include/b64_module.inc` | Header, entry, hook, and cost macros a catalogue or bespoke module is written against |
| Portrait and still quantiser | `b64quant.py` | Takes any PNG, crops and resamples with sips, maps to the 16 colours (low-saturation pixels only to greys; for stills, a colour no solid matches well becomes a luminance-safe checkerboard of two), then enforces the mode's per-cell rule: for a block, a shared trio chosen by least visual damage plus one cell colour from the first eight; for a still, one background plus three per cell. Blocks take any cell shape: 16 × 12 for a three-quarter portrait, 20 × 8 for a profile. Reports cells fixed and a damage score. |
| Generated art | `art-style.md` + the gen-image skill | The style contract every generation is prompted with. Winners land in `images/`, candidate sets in `images/archive/`, and go through `b64quant.py`. |
| Module manifest | `b64modules.py` | Reads the manifest, sums resident RAM and frame cycles against the budgets, emits `modules.inc`, the hook table, the zero page allocation, and the linker config |
| REU image `.reu` | `b64pack.py` | Lays out the image from a manifest, verifies slot sizes, emits `slots.inc` with symbols for every slot and overlay, writes the file VICE loads |
| Benchmark report | `b64bench.py` | Runs the benchmark program in VICE headless, reads the numbers from a screenshot or the monitor, and compares against budgets |

---

## 9. Backends

The engine reads the world through one interface, `b64_fetch(reu_addr, c64_addr, len)`. Three implementations:

| Backend | World size | Fetch cost | Status |
|---|---|---|---|
| REU DMA | 4 MB world, unbounded assets | ~1 cycle per byte | Primary |
| EasyFlash | 1 MB total, so a reduced world | Bank switch plus CPU copy, ~10 cycles per byte | Later, for cartridge release |
| 1541 disk | 170 KB per side | Seconds per sector | Development only, never for play |

The scroller's DMA blits degrade to CPU copies on non-REU backends. The frame budget in section 3.1 roughly doubles, which is why the REU is the primary target rather than a nice-to-have.

---

## 10. Milestones

Each milestone ships a runnable program under `build/` and a measured benchmark.

| # | Milestone | Exit criteria |
|---|---|---|
| E0 | **Core** | Done. Init, bank, IRQ chain, benchmark harness on CIA2 timers. |
| E0.5 | **Data engine** | Done, first cut. Fetch, stash, REU verification, slot manifest and packer, tileset and world packers. No page cache or overlays yet. |
| E1 | **Scroller** | Done, over budget. 8-way scroll over the 4 MB REU world with DMA shifts and double buffering, 50 fps, measured worst frame ~9,200 cycles against a 6,000 target. `make run-scroll` drives it with the joystick. |
| E2 | **Tilesets** | Region table, tileset streaming, day and night swap behind a ramp. |
| E3 | **Sprites** | Done. Sprite 0 pinned, sprites 1-7 multiplexed over 24 virtual sprites with a y-sorted raster chain, double-buffered lists, and per-slot frame streaming from the REU (a frame is fetched only when a slot's entity changes heading or state). Measured: a static frame with 20 multiplexed cars costs ~1,700 cycles including the chain interrupts. |
| E4 | **Raster** | HUD split done: the playfield is rows 0-22 and row 23 is a fixed HUD row. The split interrupt fires on the last line of row 22 (231 + YSCROLL) and sets YSCROLL to 7 so the HUD's badline always lands on line 239; the 0-7 idle lines between show background 0 through the idle byte at $7FFF. Forcing a badline mid-row makes the VIC repeat the row, which is why the split has to track the scroll. The multiplexer chain is clamped around the split. Still to do: the general split table, charset animation, colour cycling. |
| E5 | **Text** | Font, status row, dialogue box, numbers, fades and cuts. |
| E5.5 | **Modules** | Module SDK, hook table, manifest packer with budget checking, declared-versus-measured enforcement, and the base and plus tiers of physics and ai measured. A bespoke module from Priors-64 built against the SDK as the acceptance test. |
| E6 | **Overlays** | Page cache, overlay loader with region tracking, persistence records, and the overlay assembler. Full tool chain and the benchmark runner in CI. |
| E7 | **EasyFlash** | Cartridge backend with a reduced world. |
| E8 | **NTSC** | Timing pass. |
| E10 | **Lighting** | Cell lighting module: cone and radius, lit-variant tables from the tileset tool, restore list through the vblank. |
| E11 | **Splitscreen** | Two cameras and scrollers with a raster split; the example drives two cars. |
| E12 | **Cutscenes** | Done. `b64_cut_begin/end` stash and restore the 8 KB of game RAM the bitmap borrows; `b64_cut_still` loads a 10 KB still from the REU with its shimmer cell list; blocks and objects blit into and out of the set in the vertical blank; the text band is character mode below a raster split at line 209. Objects are a sprite grid and a bitmap block from one master, and the park is pixel-exact against the shimmering still (verified by frame diff: zero pixels differ outside the reflection cells). `examples/cutscene` is p-code on the VM: a cruiser drives in with easing and turning wheels, stops with its beacon flashing, an officer speaks, the car parks as a block, then drives off. Still to do: fades, a portrait block in the text band, door and pedestrian parts. |
| E13 | **VM** | Done, core tier, running from the REU. `src/b64_vm.s`: 45 opcodes, 8 threads, 32 shared 16-bit variables, a two-level call stack per thread, a per-frame instruction budget, syscalls to the cutscene primitives. Scripts are assembled at offset 0 with `script.cfg`, packed as REU slots, and read through the page cache (`src/b64_page.s`); nothing of a script is resident. Measured with `make bench`: 82 to 116 cycles per opcode after the Å-machine dispatch (2026-09-17), the cutscene drive loop 6.8 times slower than the same step in assembly (19 at the start, 11 after the page-relative fetch). Debugging: assemble with `-DVM_TRACE` to record every dispatch (thread, offset) in a ring at $E100. Next: event waits and entity-bound threads (the ai tier), thread contexts in the REU. |
| E14 | **Platform tiers** | Done, first cut. `src/b64_plat.s` probes the machine at boot: REU size (8 or 16 MB), the Ultimate turbo register, Ultimate Audio, the command interface; sizes the VM budget and the game heap. `src/b64_pcm.s` plays 8-bit PCM from the REU on Ultimate Audio (PCM opcode); `src/b64_uci.s` loads a file into the REU through the command interface. Tiers 0 and 1 verified in VICE; 2 to 4 await hardware. See `docs/ULTIMATE.md`. |
| E15 | **Samples on stock hardware** | REU-streamed 4-bit sample playback on a CIA timer NMI with a mixing budget, for machines without Ultimate Audio. |
| E9 | **C128** | Platform layer: MMU setup, far-call trampoline, 2 MHz border switch, resident overlays in bank 1, VDC console. GTA-128 boots in `x128` from the same REU image as Priors-64. |

The forward sequence, phased and with the ideas' sources, is `docs/ROADMAP.md`; this table records what has shipped. Priors-64's Milestone 1 through 5 map onto E1 through E5. Priors-64 begins using the engine at E1. GTA-128 is the same game built for the C128 platform at E9, with its own manifest and no other differences.

---

## 11. Relationship to Priors-64

backlot-64 lives in its own repository next to Priors-64. Priors-64's Makefile points at it with a variable, and the engine is assembled into the game as source, not linked as a binary. The engine's segments and symbol prefix keep the two from colliding.

```
U64 ?= ../backlot-64
ca65 -I $(U64)/include ...
```

What moves from Priors-64 into the engine: the VIC bank setup and IRQ skeleton from `src/main.s`, the canvas renderer and sprite DSL from `tools/mkdemo.py`, and the sprite path runtime from `src/demo/runtime.inc` reworked into the multiplexer. What stays in Priors-64: the zone art, the world layout, and everything in the game's own plan.

---

## 12. Explicitly out of scope

- Any interpreter in the render path. The game's bytecode VM calls the engine and streams its code through the page cache; the engine never calls the VM.
- Overlays in the render path. The overlay loader is engine code, but nothing the frame contract runs may live in an overlay.
- Sound in the core. The audio modules hook the border time the engine leaves free, and that is the whole interface.
- Physics, collision response, AI, and pathfinding in the core. They exist only as modules, and a game that selects none of them gets an engine that answers "what tile is here" and nothing more.
- Bitmap modes, except a possible map screen in E6 if the game needs it.
- Isometric, VSP/FLD scrolling tricks, or anything that depends on VIC-II revision quirks.
