# Building backlot-64 with AI

An engineering journal. It records how this engine was built with an AI system, step by step, so anyone can see the process and check the results for themselves.

backlot-64 is written by Steven Ickman working with Claude, Anthropic's model, through Claude Code. Every commit carries a `Co-Authored-By` line naming the model that wrote it. Times below are US Pacific.

---

## What "AI engineering" means here

"Vibe coding", as the term is usually used, means accepting what a model writes because it appears to work. This project runs the other way. The model writes most of the code, but nothing is accepted on appearance:

- A person owns the goals, the constraints and the taste, and makes every decision that shapes the engine.
- The model works against written contracts: a plan, data-preparation rules and repository rules it must follow.
- Every performance claim is a measurement taken in an emulator, and every hardware claim is traced to a published source.
- Every feature is verified in the running machine, frame by frame, and then held by an automated check.
- What is unknown is written down as unknown.

The model is not treated as an authority on the Commodore 64. When its own documentation was audited against primary sources, it was wrong in several places, including the colour luminance table the art tools depended on. The method exists because of that, not in spite of it.

## Who does what

| Steven | Claude |
|---|---|
| Sets goals and constraints: the 38 KB memory budget, "shift as much as we can to p-code", scale from a stock C64 to the C64 Ultimate | Researches the hardware, other engines and the options, and lays out trade-offs |
| Decides between designs: modules as overlays, logic at 25 Hz with motion at 50 | Writes the 6502 assembly, the Python tools, the docs and the tests |
| Reviews what the engine shows and says what is wrong: "it paused unnaturally in spots", "it's lighting the whole scene" | Measures in VICE, traces faults with the monitor and the probe, and fixes them |
| Names things, and owns the licensing and publishing decisions | Credits every source and records every departure from one |

---

## The practices

1. **Contracts before code.** `docs/PLAN.md` is the design with budgets and a memory map. `docs/PREPARE.md` is the recipe for every kind of data the engine consumes, written so a person or an agent can follow it literally. Steven's framing: "the engine can also be considered a set of agent instructions which describe how the data should be prepared." `CLAUDE.md` holds the repository's rules, and a small persistent memory carries decisions from one session to the next.
2. **Measure, don't assert.** DMA costs, VM cycles per opcode, overlay load time and frame cost were each measured in VICE before they were written down. `budgets.txt` now holds 21 of them, and a change that moves one says why in its commit. The rule for borrowed ideas: an improvement is only called an improvement when it has been measured.
3. **Verify in the machine.** The emulator is driven through its monitor. Tests stop on program labels and on stores to the frame counter, take screenshots and compare pixels. A car parking into the picture must change no pixel outside the ones that shimmer, at both REU sizes. `make check` runs 50 such checks on every push.
4. **Look at it.** Results that matter visually are published as frame-by-frame flipbook pages for Steven to review. His eye caught things no check had been written for yet: a pause one frame in four, and lighting that washed the whole scene instead of lighting near its source.
5. **Credit and source everything.** Nine C64 engines were read for ideas. Each borrowed technique carries a comment at its point of use in a fixed shape: `After <author>, <project> (<file>).` followed by `Changed:` and the reason, or `As is.` `CREDITS.md` lists every source, and `docs/PRIOR-ART.md` records every departure. Licenses were checked before anything was adopted.
6. **Say what is unknown.** Code for hardware VICE cannot emulate, the C64 Ultimate's turbo, sampler and command interface, is marked UNTESTED until it has run on the real machine. Claims no source supports are marked as such in the docs.
7. **Parallel research, one build.** Independent questions, such as auditing three sets of docs against primary sources, go to separate research agents at the same time. The engine itself is built in one thread, so there is one author of the code.
8. **Keep secrets out.** The image-generation key lives outside both repositories and reaches the tool only through the environment. When the image budget ran out unexpectedly, the repositories and their history were scanned to confirm the key had never entered them.

---

## Timeline

### 14 to 15 September, overnight: the questions

The first message asked which C64 emulator is best. The answer, VICE's cycle-exact `x64sc`, was installed and has been the reference ever since. The next questions set the project's direction:

- What could a C64 keep from a modern open-world game? A game plan was written listing what is kept and what is dropped.
- Which look? Five small working demos showed different visual directions to choose from.
- Can memory be virtualised? The answer was the RAM Expansion Unit: a 2048 by 2048 tile world lives in 4 MB of REU and streams in by DMA.
- Can behaviour be data? A small script virtual machine was planned for cutscenes and AI loops, with the rule that rendering stays assembly.
- Should the engine be its own thing? The engine was split from the game, with modules in tiers (simple or complex physics, basic or tactical AI) that each game chooses, plus bespoke modules.

### 15 September, afternoon: art and cutscenes

- Vehicles, with emergency vehicles identifiable by their flashing patterns, led to pattern tables for light overlays.
- Hand-coded procedural vehicle art broke on three-quarter views; the wheels came out wrong. The art moved to an image model driven by a written style contract (`art-style.md`), followed by a quantiser that forces the result into the VIC-II's real colour rules and reports how much damage it did.
- The cutscene engine was built on bitmap stills, with a file format for objects that are a sprite grid and a bitmap block at once. A car drives in as sprites and parks into the picture with no seam. Rotating wheels and palette-correct shadows came next.
- `docs/PREPARE.md` began here, from Steven's point that the engine is also a set of instructions for preparing data.

### 15 to 16 September: memory

- A C64 leaves about 38 KB for a program. The engine's share was counted, and a paging strategy was written for everything that can move in and out of the REU, p-code included (`docs/PAGING.md`).
- The costs were measured instead of estimated: 361 cycles to page in 256 bytes, about 9,000 for an 8 KB block, and p-code first running at one nineteenth the speed of assembly.
- A page cache was built so scripts execute straight from the REU without ever being resident.

### 17 September, evening: an engine others can use

- **Platform tiers.** The C64 Ultimate's specifications were researched. The engine probes the machine at boot and scales from a stock C64 with an 8 MB REU, the reference, up to the Ultimate's 16 MB, turbo CPU, sampler and command interface.
- **A name and a repository.** The first working names referenced a commercial game series. The engine was renamed backlot-64 and published under the MIT license, and the game was re-planned as Priors-64, set in a fictional state.
- **Prior art.** Nine engines were surveyed and ranked by what to borrow. The roadmap was written in four phases, with credit for every source and a public record of every departure.
- **The VM.** It was rebuilt after Linus Åkesson's Å-machine dispatch, from 116 to 147 cycles per opcode down to 82 to 116. P-code went from 11 times the cost of assembly to 6.8 times.
- **A pause, found and fixed.** Steven saw the scene pause unnaturally. The probe traced it to a background effect running 8,700 cycles inside the vertical-blank interrupt. It moved to the main loop, and the frame contract in `PLAN.md` now says where per-frame work may run.
- **Code overlays** were verified loading from the REU at run time.
- **Modules as overlays.** The VM becomes the overlay manager, and the script compiler emits the plan for which modules stay resident (`docs/MODULES.md`). An optimizer turns hot script loops into native code, guided by profiles.
- **Instrumentation.** A probe measures the engine the same way in VICE and on hardware, because the model can run the emulator but cannot measure the real machine.
- **A showcase.** Asked what modern features a C64 could light up, the answer was precomputation: the REU holds what a faster machine would compute. The first piece was baked lighting, a street falling from day to night through 32 streamed colour maps without the bitmap ever changing. Steven's review: the police strobe lit the whole scene. It became a map per light position, then light sources declared in the vehicle's own file, so the lights and the light they throw cannot drift apart.

### 18 September: Phase 1, "solid"

- **`make check`.** The ad hoc verification scripts became one harness that proves the engine in VICE at both REU sizes and holds every budget. Its first run found two real bugs: a newly loaded object inherited the previous object's lights, and the profiling build no longer linked.
- **A self-describing REU image.** The image carries a header, and every program verifies it at boot, halting with a distinct border colour for no REU, an empty REU and a stale image. VICE silently gives an empty REU when the image size doesn't match the unit, which had broken the stock tier twice.
- **A docs audit.** Three research agents checked every hardware claim against primary sources: Christian Bauer's VIC-II article, Codebase64's REU pages, Pepto's colour analysis, "Mapping the Commodore 64" and "128", the Ultimate documentation, and VICE's source. They found real errors, now fixed:
  - the luminance table, wrong in the docs and in the art tools
  - the claim that PAL does not blend colours vertically
  - the bitmap's resolution
  - the REU's speed, and whether it can reach the RAM under the I/O area
  - whether CIA timers speed up under turbo
  - a real 1750's size
- **Continuous integration.** Before the first push, the repository was built from a fresh clone. That found two engine tools importing code from the game's private repository, which would have broken every clone. The first CI run passed 48 of 50 checks and timed out on two, because GitHub's runner emulates eight times slower. The second run passed all 50.
- **Frame rates.** Steven asked about locked frame rates. PAL refreshes at 50 Hz, so only 50, 25 and 16.7 lock cleanly. He chose logic at 25 Hz with motion at 50: the game ticks every second frame and the frame between shows every position at its midpoint. 16.7 Hz was ruled out for a driving game, and staggered AI updates were planned instead.
- **An honest benchmark.** Asked whether the new multiplexer would be the state of the art, the answer was no, not by borrowing alone. It would match the best open game multiplexers. It can lead only where this engine is different, and whether it does will be measured against Cadaver's framework in the same harness rather than claimed.

### 18 September, morning: Phase 2 begins with the fills

The scroller missed its budget: 6,000 cycles for a cell crossing was the target and 10,361 the measurement. Before changing anything, the cost was measured with the emulator's own cycle counter, and that turned up something no check had looked for: the scroller example dropped a frame at every cell crossing, 100 frames in 800. The old budget measured only the scroller's preparation, not whether the frame held.

- **Colour in the screen code.** The tileset tool now assigns character codes so each code's low four bits are the colour its cells show, twelve codes per colour. Every metatile of the example tileset was checked to render exactly as before. The metatile colour table disappeared, and 4 KB of RAM with it.
- **One REU copy of the shown screen** serves as both the next shift's source and colour RAM's, so the vertical border does one DMA where it did two plus a loop.
- **Faster fills.** Rows are unrolled per metatile. Columns read from a second copy of the library stored by column and write with unrolled stores. A column's metatile ids come from one-byte DMAs that reuse the REU's registers.

| Cell crossing, interrupts off | Before | After |
|---|---|---|
| Right | 4,609 | 4,218 |
| Down | 4,281 | 4,124 |
| Diagonal, the worst case | 6,341 | 5,754 |
| Vertical border's work | 3,109 | 1,119 |

The new scroller was compared with the old one at every settled frame where both showed the same camera: 31 states, identical to the pixel. `make check` now also proves the scrolled screen and colour RAM equal a full redraw computed from the world map, on every push. The engine is about 500 bytes smaller than when Phase 2 began, partly from removing an old text routine nothing called.

Dropped frames fell only from 100 to 89. The rest is the example's own per-frame work, its traffic, the sprite sort and its debug numbers, which is the next step's problem, and it is now a budgeted number rather than an unnoticed one.

### 18 September, midday: room, and the multiplexer

**Room first.** Every new feature was pressing against the 10 KB the resident engine is allowed. Three things moved out rather than letting the engine grow: the sampler and command-interface code, which only an Ultimate can use, became a module fetched into region B at boot when the hardware is there, with stubs elsewhere; an old text routine nothing called was removed; the scroller example's debug readout moved into the example. The engine went from 31 bytes free to about 280.

**A harness before a claim.** Asked whether the new multiplexer would be the state of the art, the answer was that it could only be measured. So a harness came first: 24 sprites on paths the checker computes, first at normal density, then bunched so a line carries up to twelve. It showed at once what the traffic in the scroller example had hidden: the old multiplexer sorted from scratch every frame, 15,800 cycles for 24 sprites arriving out of order.

**Three designs, measured.** The first new design did every decision and every register value in the main loop; the interrupts were cheap, but the main loop cost more than it saved. The second kept the decisions in the main loop but let the interrupts read through one index byte per sprite, with a routine per hardware sprite generated into spare RAM at start. That is the one kept.

| 24 sprites | Previous | New |
|---|---|---|
| Main-loop cycles (`b64_spr_end`, interrupts off) | 8,172 | 5,864 |
| Interrupt cycles per frame | 8,891 | 6,428 |
| Overloaded, 60 frames: sprites drawn damaged | 30 | 0 |

For the cutscene's nine sprites the saving is a transfer, not a gain: the main-loop tick rose by about 1,000 cycles and the interrupts fell by as much. The budget moved with the reason written down.

**How it was proven.** Screenshots turned out to be the wrong instrument: in a few frames VICE's monitor screenshot held rows that differed from what the frame had drawn, while the registers and the earlier canvas showed every sprite in place. The check was rebuilt on the invariant itself: the timing check breaks at every generated routine and requires each hardware sprite to be moved only after its previous occupant's last line and before its new occupant's first. 40 frames at normal density, 40 overloaded: no violation.

**What went wrong on the way,** all caught by measurement: the routine table lost a carry for sprites 4 to 7, so their entries ran sprite 0's routine and cut others short; the harness's own soak loop made the engine skip every other frame; the benchmark reset forced the routines to be regenerated on every script tick; an empty list stored the accumulator's leftover as its length. The profiler had been lying too: its sampler wrote two zero-page bytes from its interrupt without saving them, which is why the scroller's profile build ran one frame in four.

**A step not taken.** The roadmap's page table for the script cache was measured before it was built: about two lookups a frame, nearly all answered by the fast path. It would have saved about 40 cycles a frame for 256 bytes. It stays on the roadmap as deferred, with the number.

### 18 September, morning: more sprites than the hardware has, and an instrument for a machine not yet here

**The ask.** Steven asked whether software sprites were possible, then: "I'd really like to see if we can up the overall count of sprite support versus other engines."

**32, then a limit on 32.** The multiplexer went from 24 virtual sprites to 32, the densest layout seven hardware sprites can reuse: one every 4 lines. Two things made it hold. The chain got its own interrupt handler, so a group costs no dispatch. And a hardware sprite was being treated as free a line too early: a sprite with Y = y is shown on lines y+1 to y+21, so it is free from y+22, not y+21 (Bauer 3.8). The timing check proved 32 at 1 MHz with no violation, but building the list took the whole frame. Steven: "one thing I want to be certain of is that you only can do 32 sprites when you're running on a turbo mode." So the limit follows the CPU: 24 on a stock machine, 32 with the turbo.

**Why not 64?** Steven asked why not 48 or 64 on faster machines. The VIC-II still shows at most eight sprites on a line at any CPU speed, but a crowd spread down the screen can be 64 if the main loop can sort and place them and the interrupts can move each one in time. Steven: "let's implement the 64 sprite turbo tier, but I can't actually test it until I get my machine. We also need instrumentation to make that test work." So both were built: the tier (lists of 64, the tables moved to $9800 to make room, overlay region A down from 8 KB to 6 KB, 48 sprite slots) and a test that runs the same way on VICE and on the Ultimate, reading the machine over its REST interface.

**What the instrument found first.** The first VICE run of the 64-sprite layout at 1 MHz reported groups finishing after their sprite's line: about 40 late writes a frame. They were real. The allocation knew when each hardware sprite came free, but not that the chain cannot start a group until it has finished the one before; with a group every 3 lines and each taking 3 to 4 lines at 1 MHz, the chain fell further behind with every group. The allocation now models the chain too: a group starts at its line or when the previous one is done, whichever is later, and at 1 MHz each further entry in a group costs two lines, not one. The same layout at 1 MHz now shows 51 of 64 and writes none late, checked cycle by cycle. The price is about 45 cycles a sprite in the main loop; the two budgets were raised with that reason.

**Making the instrument trustworthy.** A raster line is too coarse to judge a deadline at cycle 55, so the test build stamps every entry with a clock: a CIA timer counting four lines over and over, which gives the line and the cycle from one read and counts the same 1 MHz clock under turbo. Then the instrument was itself checked: on VICE every rebuilt stamp is compared with the emulator's own clock, and all land 0 to 2 cycles after it, never before, so its errors can only lean towards reporting a write late. Its first version disturbed what it measured: two reads per entry and a log at each group's end slowed the chain enough to make late writes the real build does not make. It was cut to one read per entry. The test build's chain is still the slower of the two, so a pass there is a pass in the real build.

**Two more things the checks caught.** The cutscene's worst frame jumped from 16,832 to 21,087 cycles, more than a frame. Tracing it: the new list cost moved the scene one frame against the reflection shimmer's four-frame rhythm, and drawing the officer's text and a shimmer step landed on the same frame. Neither was new; they had missed each other by luck. The shimmer now waits a frame when text was drawn. And a check run passed on objects built from the previous commit, because a size comparison had stashed the working tree and rebuilt it; a clean build found the difference. Comparisons against an earlier version are now built in a separate worktree.

**Waiting for the hardware.** The procedure is in `docs/ULTIMATE.md`: run `tools/b64muxhw.py --host` against the test build, and set the turbo tiers' timing figures from what it measures. Until then the 32- and 64-sprite tiers are UNTESTED.

### 18 September, morning: traffic

**The ask.** Asked what dense sprites are for besides crowds, the answer was traffic, and a rule: the VIC-II shows eight sprites on a line, so with the player's own car on the pinned sprite, an east-west street can carry seven moving cars besides it, and a north-south street is limited by its length. Steven: "create a demo that shows traffic in priors. keep in mind that the player will have their own vehicle as well."

**What was built.** `examples/traffic`: the player's car and up to 24 others on Bellamar's grid. Cars read the road bits of the map a byte at a time, keep to their lane, turn at the new lane's line, stop at lights, queue, and stay out of a jammed crossing. A band governor counts every car in the lines its sprite covers, so no line is ever given more than seven.

**What the measurements changed.**

- The per-line count alone was not enough: 54 sprites were dropped in 3,000 frames. The drops were a car starting 4 lines below a full row of seven, inside the 5 lines the multiplexer needs to move a hardware sprite. Each car now also holds the 17 lines below its sprite, the multiplexer's lead plus 2 lines a sprite for a row of seven. Drops went to none.
- The first look-ahead treated a car as a point within 12 pixels of a lane. It could not see a 24-pixel car crossing one's path, so cars met inside crossings. It now uses the cars' real sizes.
- A turning car checked only ahead of its centre. Its turned body reaches back 12 pixels and landed on a car waiting beside it, so turns now check the whole new body.
- A left turn waiting in a crossing sits across the lane that cars turning right from the other side want. Each waited for the other for ever, found by a trace of the player's car standing still for 1,500 frames. Cars driving themselves now turn only right or go straight. By hand the player still turns either way and can let go.
- A spawn landed 12 pixels in front of a car still at the region's edge. The spawner now always checks both ways.
- The all-red gap was 32 frames, and a car entering on the last green frame needs 56 to clear the crossing. It is now 64.
- The frame budget took the most work. At first a quarter of frames were lost. Staggering the checks, a fast path for cars with nothing near, and spreading the spawner and the status row over separate frames brought it to 1 to 5 percent, depending on the route.

**What it found in the engine.** The status row goes blank in some frames, in this demo and in the scroller example alike. The split interrupt fires on the last line of playfield row 22 and rewrites the vertical fine scroll so that the status row is fetched at line 239. The handler takes 60 to 70 cycles, and when its write lands in the next line at cycle 4 or later, the VIC-II has already started that line as the playfield's next row. In the log, writes at 234:62 or 235:0-1 show the row and writes at 235:4-7 lose it, every time. The fix needs care: with a fine scroll of 0 or 1 the safe window is a few cycles wide. It is the next thing to do.

**How it was checked.** `make check` runs the demo driving itself for 3,000 frames. It checks that no two cars overlap, that the band table matches the cars and holds no more than seven, that nothing is dropped, that traffic flows and that the player's car gets somewhere. It then drives the car by hand through a test byte. A six-minute run found no car standing still for longer than two light cycles.

---

## What went wrong, and what caught it

| What went wrong | What caught it | What changed |
|---|---|---|
| The scene paused one frame in four | Steven, watching it run; then the probe | The effect moved out of the interrupt; the frame contract was written down |
| Lighting washed the whole scene | Steven, reviewing the flipbook | A map per light position; then lights declared in the object file |
| The lamp sprite could not be seen | Frame-stepped crops and register dumps | The sprite was a tiny bar; tests now use VICE's own palette values |
| Screenshots taken a fixed time apart always saw the same strobe phase | The colours never alternated in the test | Tests step the emulator's frame counter instead of sleeping |
| The showcase page stopped playing | Steven | Apostrophes in captions broke the page script; captions are written as JSON and the script is syntax-checked |
| A new object kept the previous object's lights on | `make check`, first run | Loading an object clears the light state |
| The profiling build no longer linked | `make check`, first run | Profile builds link with a larger engine area |
| Engine tools imported code from the private game repository | A fresh-clone build before the first push | The code moved into the engine |
| The luminance table was wrong in the docs and the tools | The docs audit | Corrected; the art re-converted; one budget moved, with the reason in the commit |
| VICE gave an empty REU when the image size didn't match | Wrong output, twice | An 8 MB image derived from the 16 MB one; the boot check halts with a colour |
| The first daytime art converted badly | The quantiser's damage report | The prompt was constrained to flat palette fills; damage fell from 5,606 to 2,055 |
| CI timed out | The first CI run | Monitor timeouts scale on slower machines |
| 6502 branches written past their 127-byte reach | The assembler | A rule in `CLAUDE.md` |
| The scroller example dropped a frame at every cell crossing | Counting callbacks per frame at the start of Phase 2 | Now a budget in `make check`; roadmap step 9 |
| Timings from the monitor's run-until-return were wrong | They contradicted the profiler | That command stops at the first return from any subroutine; timings now break at the caller's next instruction |
| The scroller's profiling build ran one frame in four or five | Counting callbacks per frame | The probe's sampler wrote two bytes of shared zero page from its interrupt without saving them, corrupting whatever it interrupted. It now writes through patched addresses; a check requires a clean profile of the scroller |
| The first fix of the sampler wrote half its samples over the opcode counters | The next profile: script opcodes counted in a program with no scripts | A carry handled wrongly in the address arithmetic; fixed, and the same check catches it |
| The new multiplexer cut sprites short | A per-sprite judge on the harness's screenshots | The table of routine addresses lost a carry for sprites 4 to 7; fixed |
| The harness itself made the engine skip every other frame | Counting lists per frame | Its measuring loop now stops before the vertical blank |
| Screenshots disagreed with the registers in some frames | Stepping one frame and screenshotting at several raster lines | The multiplexer check now tests the timing invariant from the registers; screenshots only look for damage |
| The first new multiplexer design cost more than it saved | The benchmark, interrupts off | Redesigned: decisions in the main loop, copies in the interrupt |
| A hardware sprite was reused one line early | The timing check modelled on the VIC-II's own rules | Free from y+22, not y+21 |
| The chain wrote sprites late when groups came faster than it could run them | The new hardware test, on VICE, then cycle by cycle | The allocation models when the chain is free |
| The test build's own logging made the chain late | The plain build passed the cycle-exact check where the test build failed | One timer read per entry; the test build is the slower of the two, so its passes carry over |
| Text and the shimmer landed on one frame and overran it | The cutscene's worst-tick budget | The shimmer waits a frame after text |
| A check passed on objects built from the previous commit | A clean build disagreed | Comparisons with earlier versions are built in a separate worktree |
| Seven sprites to a line still let the multiplexer drop cars | The traffic demo's drop count | Each car also holds the lines the multiplexer needs to reuse its sprite |
| Cars met inside crossings | Box-overlap samples, then a frame-by-frame trace | The look-ahead uses the cars' real sizes; turns check the whole new body |
| Two turning cars waited for each other for ever | A trace of the player's car standing still | Cars driving themselves turn only right |
| The status row goes blank in some frames | Screenshots of the traffic demo, then a log of the split's writes | Recorded with the evidence; the split's timing is the next fix |

---

## Where it stands, 18 September 2026, after the sprite tiers

| | |
|---|---|
| Elapsed | 14 September, 11:55 PM, to 18 September, 7:15 AM; about 115 requests from Steven |
| Engine | 5,600 lines of 6502 assembly; 10,164 of its 10,227 resident bytes used |
| Tools | 4,400 lines of Python: packers, quantisers, the VICE harness, the probe reader, the multiplexer's hardware test |
| Docs | 2,050 lines, audited against primary sources |
| Checks | 65, passing locally in about half a minute and on every push |
| Scroller | worst cell crossing 5,754 cycles against a 6,000 target; the example still drops 52 frames in 800 |
| Cutscene frame | 9,999 cycles typical, 17,057 at worst, of 19,656 |
| Script VM | 82 to 118 cycles per opcode |
| Multiplexer | 24 on a stock C64, 32 or 64 with the turbo; 32 sprites cost 8,586 main-loop and 8,389 interrupt cycles; too dense a layout drops sprites whole, never late |
| Not yet run on hardware | the C64 Ultimate tiers, including the 32- and 64-sprite lists, which wait for the machine |

---

## Keeping this journal

Each milestone adds an entry: what was asked, what was decided and by whom, what was built, what was measured, and what went wrong. Mistakes stay in the record.
