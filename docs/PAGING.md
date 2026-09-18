# Paging Strategies

`MEMORY.md` says what is resident and why the REU is the real memory. This file is the catalogue of ways bytes move into the 64 KB, when each one applies, what it costs, and the rules that decide whether a thing can be paged at all. Every strategy here is an engine mechanism; a game picks one by declaring its data in the manifest, never by writing a DMA.

The one idea underneath all of them: a byte is in RAM because it is needed this frame or the next, and it arrived before it was needed, on a schedule the engine set. Paging is about *when* a byte lands, not what it is.

---

## 1. The numbers every strategy is built on

| Fact | Value |
|---|---|
| Frame | 19,656 cycles, 50 per second |
| Border (VIC not drawing) | 112 lines, 7,056 cycles |
| DMA rate | 1 byte per cycle, about 105 cycles setup (measured) |
| DMA in the displayed area | about 93 percent of full rate (badlines, measured) |
| Largest change to the picture per frame, invisibly | about 6 KB, in the border |
| 256-byte page | 361 cycles (measured) |
| 8 KB overlay | 8,423 cycles in the border, 9,053 in the display (measured) |
| Camera speed | 2 px per frame, so one cell every 4 frames, one sector every 512 frames |

Two consequences. Anything that touches the picture moves in the border, and the border holds about 6 KB, so a bigger change is split across frames or hidden under a blanked frame. Anything that does not touch the picture can move whenever the engine has cycles, and the camera gives seconds of warning for everything the world will need.

---

## 2. The strategies

### 2.1 Window and lookahead

**For:** anything the player scrolls through: the playfield, a list in a dialog, a dialogue history, a mission log, a map legend.

**How:** the visible rows or columns are resident, plus one row or column of lookahead past each edge. A scroll step shifts the window (in the border) and fetches the next row past the edge, which has a whole frame to land before the step that shows it. A jump to an arbitrary position fetches the whole window under one blanked frame.

**Cost:** per step, one fetch the size of a row: 80 bytes and 140 cycles for a 40-column list row, 23 cells for a playfield column. The resident part is the window plus two rows. The list behind it can be as long as the REU.

**Rule:** a step is at most one row per frame, because the lookahead is one row. Faster scrolling means deeper lookahead, which is a manifest number.

The playfield scroller (E1) is this strategy with metatiles: the screen matrix shifts through REU scratch, the new column is filled from the metatile library, and the world is fetched a metatile column at a time.

### 2.2 Ring

**For:** state that is dense around the player and irrelevant far away: sector records, parked vehicles, destroyed props, pickups, unlocked doors.

**How:** the world is 64 x 64 sectors of 32 x 32 metatiles. Each sector has one 256-byte record. The engine keeps a 3 x 3 ring of records around the camera. Crossing a sector edge writes the trailing row or column of three records back and reads the leading three. Records page as whole units, so a record is never half written when it is stored.

**Cost:** 2.3 KB resident. Six DMAs, about 2,000 cycles, once per sector crossing, in the border. Nothing per frame.

**Prefetch:** the leading fetch runs by heading, one row or column ahead of the ring, so the crossing itself never waits. At 2 px per frame the camera gives ten seconds of warning per sector.

### 2.3 Stream

**For:** small pieces requested implicitly by what is on screen: sprite frames, charset animation frames, the metatile column entering the screen.

**How:** the engine notices the need and fetches without a request. The multiplexer fetches a 64-byte frame into a slot when the frame a sprite wants is not the one the slot holds; a sprite that keeps its frame costs nothing. Charset animation (water, neon, traffic lights) is 8-byte characters written into the charset each frame from the REU, with no resident frame tables.

**Cost:** 125 cycles per sprite frame that changes; 70 cycles per animated character. All 24 virtual sprites can change frame every frame inside the border budget.

**Prefetch:** when a sector record loads, the sprite frames its entities will need are streamed into free slots before the entities are visible, so a busy street costs nothing on its first visible frame.

### 2.3b Baked lighting (built)

**For:** anything that changes how a still or a screen is lit: dusk, neon, a lamp moving with a car, a strobe.

**How:** the VIC's bitmap holds colour *codes*; the colours they mean live in screen RAM, colour RAM and the background register. A lighting state is those bytes for the visible rows, 1.6 KB, precomputed on the Mac from the still and a light model (`tools/b64light.py`) and streamed by two DMAs in a base-phase vertical blank. Localised light is a state per light position; the script picks the state from the object's position. The bitmap is never touched.

**Cost:** 1,900 cycles in the blank per applied state; 2 KB of REU per state. A 32-step dusk is 64 KB; a beacon at 20 positions in two colours is 82 KB.

**Rule:** applied only on base-phase frames so the shimmer's swapped cells are never relit out of step; the background colour is global, so colour-00 pixels cannot be relit per cell.

### 2.4 Slot swap, split

**For:** a big fixed-size asset that changes on a known event: the tileset at a region border (12 KB), a sprite bank.

**How:** the event is known well in advance (a region border is sectors away), so the asset arrives in pieces over many frames into an inactive second copy, and the switch is one pointer change in the border. The region's core-only tile band on both sides of the border is what makes the switch invisible.

**Cost:** 1 KB per frame for 12 frames, then nothing. The second library costs 8 KB of RAM, the one place the strategy spends RAM for smoothness. Without the second copy the swap is a 12 ms hit under a blanked frame, which is acceptable for a cut but not for driving.

### 2.5 Page cache

**For:** data read sequentially in small pieces where the reader does not know in advance which bytes: p-code, dialogue text, path tables, stat records, mission flags.

**How (built):** eight 256-byte pages at $C100 with a linear tag lookup, a one-entry fast path for the page answered last, and round-robin replacement (`src/b64_page.s`, 139 bytes). A hit is a compare; a miss is one 361-cycle DMA. The VM reads p-code through it: a script is assembled at offset 0 (`script.cfg`) and packed as a slot; a thread's position is a 16-bit offset from the script base, so operands stay 16-bit and a script can be 64 KB. The running thread holds a pointer to the cached page of its offset, so a fetch is one indirect load; an instruction that starts within nine bytes of a page end is copied into a small buffer that spans the boundary. Jumps within a page skip the lookup. A loop that spans two pages settles into the cache and never misses again. Measured: 116 to 147 cycles per opcode (`MEMORY.md` section 6).

**Cost:** 2 KB resident for the cache, about 300 bytes of code. A miss is 361 cycles; the per-frame script budget (1,500 cycles) absorbs about four misses a frame, and a warm cache misses far less. The page-relative fetch is also what makes the VM fast: see the measurements in `MEMORY.md` section 6.

**Rule:** the cache serves the VM and the screens, never the frame loop. Nothing per entity per frame reads through it.

### 2.6 Package

**For:** a screen the player opens and closes: a detail screen, the phone, a garage, the pause menu, the map, the title.

**How:** the packer builds one REU slot holding the screen's overlay code, its screen data, its text and its font. Opening the screen is one 8 KB DMA into an overlay region under a blanked frame; closing it is forgetting it. Nothing about any screen is resident while it is closed. A scroll region inside the screen uses 2.1; its records use 2.5.

**Cost:** 8.4 ms to open, zero per frame, zero resident when closed.

**Built (loader):** `b64_overlay_load` and `tools/b64overlay.py`; `examples/overlay` is the proof. Measured 9,013 cycles for an 8 KB load into region A. The packaging of screen data and text with the code is the part still open.

### 2.7 Stash and restore

**For:** a mode that borrows RAM the game is using: the cutscene bitmap at $6000.

**How:** the engine stashes the borrowed region to the REU (8 KB, 8 ms), the mode uses it, and the engine restores it on exit. The scene reads its still straight into the VIC bitmap, renders, and throws everything away. This is the same path the save file uses: hot state stashed as a block, not serialised.

**Cost:** two 8 KB DMAs per mode change, hidden under the mode's own fade or cut.

### 2.8 Overlay by mode

**For:** engine code that is dead in one mode: the scroller during a cutscene, the cutscene module during play, the map screen renderer.

**How:** each is an overlay slot assembled for a fixed region, loaded when the mode starts. The rule that the render path never depends on an overlay still holds, read as: the render path *for the current mode* is resident.

**Cost:** frees about 2 KB of core for whichever mode runs. One overlay load per mode change.

### 2.9 Context paging

**For:** VM threads beyond the eight resident ones.

**How:** a thread context is 16 bytes (program counter, wait, stack). Sleeping and waiting threads live in the REU; the scheduler swaps ready ones in. Eight resident threads become sixty-four.

**Cost:** a few hundred cycles of DMA per frame when threads wake, nothing while they sleep.

---

## 3. Choosing a strategy

| The data is | Strategy |
|---|---|
| scrolled through by the player | window and lookahead |
| dense around the player, sparse elsewhere | ring |
| implied by what is on screen | stream |
| large, fixed size, changes on a known event | slot swap, split |
| read in small sequential pieces, order unknown | page cache |
| a whole screen with its own code | package |
| RAM a mode borrows from the game | stash and restore |
| engine code dead in the other mode | overlay by mode |
| a thread that is asleep | context paging |

Every strategy shares three properties: the record is a fixed size at a computed REU address (arithmetic, never a search); the fetch is scheduled a frame or more before the need; and anything that touches the picture lands in the border.

---

## 4. What cannot be paged

- **Anything the interrupt runs.** The dispatcher, the vertical-blank work, the sprite chain, the raster splits, the DMA primitives, the page-cache lookup. A miss inside an interrupt is a missed raster line, a visible tear. The code that pages is never paged.
- **What the VIC is showing this frame.** The active screen, the charset, colour RAM, the sprite slots of sprites on screen, the metatile rows the scroller is filling from. They change only in the border, and the border moves about 6 KB.
- **Code, in place.** The 6502 cannot execute from the REU; every byte of code that runs was copied in first, so an overlay is only ever whole.
- **The 4 KB under the I/O window.** DMA sees the CPU's memory map, and the REU registers live in that window.
- **Zero page, the stack, the vectors.**

## 5. What should not be paged

- **Anything read per entity per frame.** The entity table, the visible collision map, the sprite list. If a miss could happen inside the frame loop's per-entity work, it is resident.
- **Hot state with no warning.** Player, wanted level, timers, input, the frame callback.
- **The music player.** Its per-frame routine is resident; its pattern data pages.
- **State being written.** A record is in one place while it changes, or write-back races the copy. Records page as whole units.
- **Things under about 32 bytes.** The bookkeeping costs more than the data.

**The rule.** The frame loop never touches anything that can miss. Everything it reads is resident or was fetched the frame before. Paging is for what the game decides and what the player is about to see, never for what the frame is drawing now.

---

## 6. Order of work

1. Done: page cache (2.5).
2. Done: p-code from the REU (2.5); the cutscene example's script left the PRG.
3. Ring with heading prefetch (2.2), then the split tileset swap (2.4).
4. Packages and the overlay loader (2.6), including window-and-lookahead lists (2.1) inside them.
5. Overlays by mode (2.8) and context paging (2.9).
6. Save and load as stash and restore (2.7).

Each step is measured in VICE with the benchmark counter before it is called done, the way the park was proven by frame diff.
