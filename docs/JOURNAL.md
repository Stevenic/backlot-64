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

### 18 September, evening: a page of demos, and physics

**The asks.** Steven: "create a demo page with videos posted to the repo. use gh-pages to display everything." Then: "next I want to start working on things like physics. let's work on a rich physics module next." Asked to identify the physics each kind of play needs (driving, flying, walking), the answer was a shared core with a mover per way of moving: foot, wheels, hull, air, thrown. Steven: "I was thinking the shared core as well, so let's start building all of this." Then, on whether collision belongs in physics: "if we have to duplicate some logic to optimize module size that's fine."

**The demo site.** `tools/b64video.py` records a program in VICE through the monitor, a frame at a time with the emulator stopped, and encodes it with ffmpeg at twice the size with square pixels. `tools/b64site.py` records six demos and writes the page. Each demo names the `make check` lines that hold its numbers. `make publish-pages` puts it on the gh-pages branch, which GitHub Pages serves at stevenic.github.io/backlot-64. The videos never enter main.

**Physics, first stage.** A pinned module at $6000 (`modules/physics`), loaded from the REU when play starts and linked against the engine's labels. It holds the core and two movers: foot, and wheels with grip, skids, the handbrake, and surfaces from the map's tile bits. The core covers fixed-point numbers, a quarter-square multiply, a map cache of 3 x 3 metatiles per body, walls, and collisions exchanged by mass. `examples/physics` puts a walker beside four parked vehicles and four pedestrians. The design is `docs/PHYSICS.md`.

**What went wrong on the way.**
- The body allocator hands out slots from the top, and the demo assumed the player was body 0. The camera followed an empty slot across the city.
- The first physics step cost 13,000 cycles for nine bodies. Testing every pair in full was most of it (see PHYSICS.md section 6).
- The first version of the check reset its results for each of its two runs. The second run does not look, so the wall check passed without having looked. Caught when the ram test reported no ram in a run where the trace showed one. Fixed, and the wall check has now really passed.

### 18 September, night: grenades, and a first cost pass

**What was built.** Thrown things in the collision module, beside the shots: `throw_fire` tosses a grenade with an altitude of its own. It arcs under gravity, bounces off the ground at half speed, turns back off walls, passes over people, and goes off after 70 frames. The blast pushes every body within 40 pixels away from it, damages it, and knocks people down. The demo throws when fire is pressed with no direction held, and draws each grenade twice, its shadow on the ground and itself raised by its height. The design is in `docs/PHYSICS.md`.

**How it is checked.** The tape now throws grenades after the shots. `collision.thrown` requires that no grenade is ever inside a wall and that every body within reach of a blast shows it: pushed, marked with the blast's impact, and down if on foot.

**What the measurements changed.** The step's cost used to be measured over 24 quiet frames after the tape. It is now measured over every step of the tape, in a third run, and that showed a worst step of 19,004 cycles. Breaking on each routine's entry inside that one step found two causes. It was a three-car pile-up, with two pairs resolved in one frame. And each car's wheels mover cost about 1,000 cycles a frame, mostly signed multiplies turning the car's own velocity into the world's. Three exact savings followed: a multiply by zero costs a test, a speed under a pixel a frame skips the high product, and a car whose heading and speeds have not changed keeps last frame's world velocity. Frames lost over the tape fell from 81 to 37 of 800. The worst step fell to 15,436 cycles and the median to 6,413. Every body's path stayed the same to the bit: the momentum figures and the repeat check did not change. The step budgets were re-set against the new measure, and the reason is in the commit.

**What went wrong on the way.**
- The blast check added up Python booleans with `and`, which returns its last operand rather than a truth value. It counted 3 responses from 2 bodies.
- Timing the step in the same run as the frame-driven checks made that run stop at a different point from the other one. The repeat check then failed on two runs that were never alike. The timing now has a run of its own.
- The first blast went off out of view. Tracing it found two faults. Ground friction worked on the velocity's high byte only, so under 4 pixels a frame it took nothing away, and a grenade rolled at full speed until its fuse ran out. It now halves the whole 16-bit speed at each bounce. And the tape's drift began with a fire press while the car was nearly stopped, which the demo reads as getting out. The player had been leaving the car at frame 266, in what the docs called a drift, and the later "get out" press threw a grenade. The drift now starts at speed, and the tape was traced entry by entry until it does what its comment says.
- The first measurement after the multiply changes matched the one before to the cycle. The module had been rebuilt, but the REU image that the demo loads it from had not. A result identical to the cycle is now read as a sign that the old build is still in use.

### 18 September, late: boats, and the first module swap

**What was built.** The water module: the same core and the same on-foot mover as the ground module, with a hull mover in place of the wheels. The car's own frame of speeds (`to_body`, `world`, and the unchanged-frame shortcut) moved out of the wheels mover into `frame.s`, which both movers share. A boat has no grip. Its sideways speed loses a share of itself each frame instead of a fixed amount, so it slides out wide through a turn. Pulling back is reverse thrust, and the rudder only bites while water flows past it. The example builds a second time at the coast, where the road at row 1000 meets the sea. Getting into the speedboat fetches the water module over the ground module, and getting out onto the sand fetches the ground module back. Getting out now looks for land around the vehicle instead of assuming the pavement south of it.

**How it is checked.** Seven checks on the coast tape. The one that matters most is `boats.swap`. A run stops at each swap and requires that the body tables are the same byte for byte before and after the 6 KB fetch, and that the module in place matches its binary. That is the claim the module split rests on, and it had not been tested until now.

**What the measurements and the checks changed.**
- The first tape rammed the launch and then stayed stuck against it. Pushing a heavier boat kept the speedboat below the speed at which its rudder bites, so it could not turn away. Real boats steer at low speed on the propeller's wash. The hull now turns at half rate when slow with thrust held, and not at all when drifting still.
- The walls check failed every frame on its first run. One of the beach's walkers had been placed inside a palm tree. The check judged it from the map file, not from the module, and was right. The walker moved ten pixels.
- `hold`, which a module runs for a mover it does not carry, zeroed the world velocity but left the car's own frame of speeds as it was. A car moving when the water module came in would have stopped, then set off again at its old speed when the ground module returned. `hold` now marks the body so that its own mover takes up from rest.
- The city tape's frames lost rose from 34 to 40 of 800. The step's median rose by 12 cycles, from the shared entry call, and the rest came from the example's own per-body work. The limit was raised to 44, and the commit says so.

### 18 September, night: helicopters, and building heights

**What was built.** The air module: the core assembled with `AIR`, the on-foot mover, and a helicopter. Altitude, reserved in the body tables since the split, is now in use. Fire held climbs to a ceiling; let go, the craft settles onto whatever is under its box. Flying, the stick thrusts it in the world's directions and it turns to face its way. Buildings needed heights, which the map never had. The tileset now carries a second table of 256 bytes beside the properties, one height per metatile in storeys of 8 pixels, and the tool refuses a solid metatile without one. The air module folds each building's height into the low bits of its cached properties, which are the road bits, and a building never has those. Its wall test then reads a building as a wall only below its height. A new entry, `phys_resume`, reloads every body's map cache after a swap, so the air module never reads entries the ground module wrote in its own form. The example builds a third time, with a helicopter on the road, and flies over a block, lands on its roof, and lands back on the road.

**How it is checked.** Five checks. `sky.walls` judges the helicopter's box against the map and the tileset's heights, not against the module's cache. `sky.flight` requires the craft to be over the building in the air, to rest on its roof at the roof's height, and to stay under the ceiling. The swaps are checked as for the boats.

**What went wrong on the way.**
- Fire is the climb, so taking off was also a fresh press of fire, which the example reads as getting out. The player got in and straight back out. In an aircraft, getting out is now fire with the stick pulled down, on the ground.
- Letting go took a sixth of the climb rate off a frame, so the craft kept rising for 43 frames and the tape's settle ended 10 pixels above the roof. Settling is now as quick as climbing.
- The first frames on the roof drew the helicopter 24 pixels above its own shadow. The example raised it by its altitude, but roofs are drawn at ground level. The mover now leaves the height above whatever is under the craft in `pb_agl`, and the example draws from that.
- The city scene's frames lost reached its limit again as the shared example grew. Instead of raising the limit a second time, the status row is now made on one frame and shown on another, as the traffic demo does. That took it from 44 to 39.

### 18 September, late night: shots and height; an encounter zoom planned

**The asks.** Asked where physics had landed, the list of what was not done came back: shots that ignore altitude, planes, debris, airboats, the status-row fault and a cost pass. Steven: "do the other tasks", then "add demos for each". Midway: "we should be able to zoom from an overhead view down to a 3/4 view for things like encounters." The zoom was designed and put on the roadmap (step 14b). Steven chose to build it after the physics list, with 3/4 sets both chosen by the kind of place and authored for particular encounters.

**What was built.** Every question the collision module answers is now asked at a height, `col_z`, and sees only bodies within 8 pixels of it. A shot flies at its firer's height, and a blast reaches 16 pixels up. `col_near` compares the asker's own height, so a walker under a hovering helicopter cannot climb into it. Its demo is a fourth build of the example: a helicopter lifts off across the road and holds 32 pixels up, flown by a small pilot in the example. Shots pass beneath it and a grenade goes off under it; once it settles, the same shots hit it. The example's scenes are now built from one Makefile template, since there will be more.

**How it is checked.** `hover.beneath`: never hit while 8 pixels or more up, though shots cross its footprint (9 frames). `hover.blast`: a blast in reach at 16 pixels up does not mark it. `hover.down`: hit three times on the ground.

### 18 September, late night: planes

**What was built.** A second air mover, the plane, in the air module. It goes where it points, in the vehicle's own frame with no sideways speed. Up is the throttle; at flying speed fire climbs and letting go holds its height; slower than that it sinks, which is how it lands. The helicopter's handling of height (the ceiling, the floor under the box, landing, the height above ground) became one routine, `rise`, which both aircraft use. The fifth build of the example puts a plane on the road. It takes off, circles over the blocks and lands back on the road.

**What went wrong on the way.**
- The first flight climbed for 50 frames, turned over a six-storey block at 37 pixels, and flew into it: 120 damage, and speed from 896 to 40. The walls worked. The tape now climbs longer.
- The air module's code outgrew the 4 KB before the shared tables. The limit set in `pinned.cfg` for this reason caught it at link time. Every module's tables moved up 512 bytes: code to $71FF, tables at $7200, the body tables at $7A00. They now end 9 bytes short of $7C00.
- The get-out tap came while the plane was still rolling, so it was refused, and the walk that followed on the tape steered the plane. The tape brakes longer.
- The city scene's frames lost rose to 44 again from the example's new drawing cases. Testing a body's height above the ground before its mover, and walkers first, brought it back to 39.

### 18 September, night: debris

**What was built.** Debris in the collision module, beside the grenades: up to 12 pieces with a height. They are thrown out in a spread, bounce at half their speed, and settle when a bounce is too weak to matter. Then they lie 6 frames and go. Nothing but the ground touches them. A game throws a burst with `debris_burst`; a blast throws as many as the game sets, none by default. The sixth build of the example drives into parked cars and throws a grenade at the wrecks.

**What the measurements changed.**
- The first crash threshold, an impact of 24, was a guess. The tape's rams measure 16 to 22, so there was no debris at all. It is now 16.
- The city scene went from 39 frames lost to 142. Most of it came before any piece existed: empty loops over twelve pieces and twelve bodies, about 500 cycles a frame, in a frame with nothing to spare. The collision module now counts live pieces and skips everything at none. Debris is something a game asks for: only the debris scene does, and the city is back to 40.
- A car pushing a wreck crossed the threshold frame after frame and threw a new burst each time. A crash now throws once, on the frame its impact first crosses the line.
- Pieces never settled. After storing the halved bounce speed, the code branched on the Z flag, but a store sets no flags, so the branch tested the byte shifted just before. Every piece lived its full 48 ticks, about 100 frames at the rate the scene was running. The value is tested now (the rule in `CLAUDE.md` about testing values, not left-over flags, applies to stores too). Frames lost in the debris scene went from 100 to 73 of 560.
- What remains is the real price. Six pieces in the air in a full city frame cost about half the frames while they fly. It is budgeted and stated, not hidden.

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
| The demo followed an empty body across the city | A contact sheet of the first frames | Bodies are allocated from the top; the demo keeps the index it is given |
| A check passed without looking | The ram test found no ram where a trace showed one | The check kept its results across its two runs; results are now taken from the run that looks |
| The blast check counted 3 responses from 2 bodies | The count itself | Python's `and` returns an operand, not a truth value; the terms are now converted to booleans |
| Two runs of the tape stopped comparing alike | The repeat check | Timing moved to a third run, so the two compared runs are driven the same way |
| A cost change measured identical to the cycle | The identical number | The demo loads the module from the REU image, which had not been repacked |
| Grenades rolled at full speed until they went off | A blast out of view, then a trace | Ground friction had worked on the high byte only; it now halves the 16-bit speed |
| The tape's drift got the player out of the car | The same trace, entry by entry | The drift starts at speed; a tap when all but stopped means get out |
| A rammed boat stayed stuck against the one it hit | A trace of the coast tape | Slow boats steer on the propeller's wash |
| A walker started inside a palm tree | The coast's walls check, every frame | Moved; the check judges from the map, not the module |
| Taking off in the helicopter got the player out | A trace of the sky tape | In an aircraft, getting out is fire with the stick down |
| A landed helicopter was drawn above its own shadow | A screenshot on the roof | The mover publishes the height above what is under the craft |
| The plane flew into a six-storey block | Its damage and speed in a trace | The tape climbs longer before turning |
| Debris never settled | A piece watched tick by tick | A branch tested flags a store never set; the value is tested |
| Empty debris loops cost the city 100 frames | Frames lost counted every 10 frames | Live pieces are counted; debris is asked for, not always on |

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
