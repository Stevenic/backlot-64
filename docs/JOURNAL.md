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

---

## Where it stands, 18 September 2026, after the fills

| | |
|---|---|
| Elapsed | 14 September, 11:55 PM, to 18 September, 4:30 AM; about 105 requests from Steven |
| Engine | 5,600 lines of 6502 assembly; 9,676 of its 10,227 resident bytes used |
| Tools | 3,600 lines of Python: packers, quantisers, the VICE harness, the probe reader |
| Docs | 1,850 lines, audited against primary sources |
| Checks | 55, passing locally in under 30 seconds and on every push |
| Scroller | worst cell crossing 5,754 cycles against a 6,000 target; the example still drops 89 frames in 800 |
| Cutscene frame | 8,889 cycles typical, 15,692 on effect frames, of 19,656 |
| Script VM | 82 to 118 cycles per opcode |
| Not yet run on hardware | the C64 Ultimate tiers, which wait for the machine |

---

## Keeping this journal

Each milestone adds an entry: what was asked, what was decided and by whom, what was built, what was measured, and what went wrong. Mistakes stay in the record.
