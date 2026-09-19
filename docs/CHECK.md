# Checks

`make check` is the engine's claim that it works. It builds everything from source and art, runs the programs in VICE at both REU tiers, and fails on any pixel, count or cycle that is not what the engine promises. It runs on every push (`.github/workflows/check.yml`) and takes under a minute on a Mac.

A change is not done until `make check` passes. A change that moves a number in `budgets.txt` says so in its commit.

## How it runs

`tools/b64vice.py` drives x64sc through its remote monitor. Every command waits for the monitor's prompt instead of sleeping, the emulator runs in warp, and the tests stop the machine on labels from the program's label file (`-Ln`) or on stores to the frame counter, so a run is frame-exact and the same every time. Screenshots are read by `tools/b64png.py`, which has no dependencies.

`tools/b64check.py` runs the two tiers and the single-tier tests in parallel, on separate monitor ports. A shared CI runner emulates several times slower than a desk machine, so every monitor timeout is multiplied by `B64_VICE_TIMEOUT_SCALE` (the workflow sets 6). A timeout is a failure, never a hang.

| Tier | REU | Image |
|---|---|---|
| 8 MB, the reference (tier 0) | `-reusize 8192` | `build/world8.reu`, the first 8 MB of the build |
| 16 MB | `-reusize 16384` | `build/world.reu` |

## What it checks

**The build.** The image at each tier has the right size, carries its header, and its slot table agrees with `reu.manifest`, the files packed and `build/slots.inc`. The baked lighting file agrees with the object whose lights it bakes.

**The boot check.** Every program calls `b64_boot_check` from `b64_init`, which compares the image header with the REU's verify command. Four runs prove it:

| Case | How it is made | Border |
|---|---|---|
| No REU | VICE started with `+reu` | red, flashing |
| No image | an REU with nothing loaded (in VICE, also what an image of the wrong size gives) | yellow, flashing |
| Stale image | the 8 MB image with its layout hash altered | orange, flashing |
| The right image | the build | the scene runs |

**The platform probe.** The benchmark program reports what `b64_plat` found: an REU, 8 or 16 MB as the tier says, and no turbo, sampler or command interface in VICE.

**Overlays.** `examples/overlay` loads two overlays in turn, reloads each, and asks for a resident one again. Five calls, four DMAs, the last byte of the window as written.

**The cutscene.** The park changes no pixel outside the ones that shimmer or flash; after the unpark and the drive off, the street is pixel for pixel the empty street it was. At both tiers.

**The showcase.** With the cruiser stopped and its lights on: each frame shows exactly one lamp, each lamp in its own colour at the offset the object file declares; the pattern changes every 8 frames; every frame relights at least 200 pixels, and none beyond the light's declared radius; the park is exact after the lights go off. At both tiers.

**The scroller.** The autodrive example runs twice round its square. About every 12 frames, on a settled frame, its screen buffer and colour RAM are read and compared with a full redraw of the world at the camera, computed in Python from the world map and the tileset. The count of frames that go without a callback is budgeted too.

**The multiplexer.** The harness (`examples/mux`) runs 32 sprites on paths the checker can reproduce, first at most four to a line, then bunched so a line carries up to twelve. `tools/b64muxtiming.py` breaks at every generated sprite routine and checks that each hardware sprite is moved only after its previous occupant's last line and before its new occupant's first. At normal density nothing may be dropped; overloaded, something must be; and no sprite may be drawn damaged in 60 captured frames. `tools/b64irqcost.py` measures the interrupt cycles per frame.

**The multiplexer's hardware test, on VICE.** `tools/b64muxhw.py` runs both test builds (`build/mlog/`, `docs/INSTRUMENT.md`): the 32-sprite harness and the 64-sprite layout, the second at 1 MHz, beyond the tier that allows 64, where the allocation must drop what the chain cannot write in time. From three frozen snapshots each: no sprite cut short, none written late by its stamp, none cut short by the blank, and the groups cover the list (`muxhw.mux`, `muxhw.mux64`). And the instrument itself: every stamp rebuilt from the log clock lands on the emulator's line, 0 to 3 cycles after the emulator's own cycle and never before (`muxhw.clock`). The same tool runs on a C64 Ultimate; that run is not part of the check.

**Traffic.** `examples/traffic` driving itself for 3,000 frames, sampled every 10: no two cars' bodies overlap, the band table matches the cars' positions and no band holds more than seven, the multiplexer drops nothing, there is traffic (at least eight cars live on average), and the player's car gets somewhere (a thousand pixels). Then driven by hand through its test byte (`joy_test`): holding up turns the car north at the next crossing, it runs at two pixels a frame, and pulling back holds it (`traffic.auto`, `traffic.by_hand`).

**Physics.** `examples/physics` plays its input tape (walk, get into a sedan, ram the sports car and the truck, brake, reverse, turn, drift, stop, get out, walk). No body's box ever has a corner in a wall, judged from the world map file and the tileset's properties; the first ram conserves momentum along its axis, allowing for the engine's push; the abandoned car comes to rest and sleeps; two runs of the tape end in the same state (`physics.walls`, `physics.momentum`, `physics.rest`, `physics.repeat`). The tape ends by firing: shots are fired and stop, no shot is ever inside a wall, and every stopping point is clear of one (`collision.shots`). It throws grenades too: no thrown thing is ever inside a wall, and every body within a blast's reach when it goes off is pushed and marked with the blast's impact, and knocked down if on foot (`collision.thrown`). The abandoned car must be asleep at frame 530, before the grenades reach it.

**Boats.** The same example built at the coast (`build/boats-auto.prg`) plays its own tape: walk to a speedboat and get in, which swaps the water module in; ram the launch, slide through a turn, run into the beach, get out on the sand, which swaps the ground module back, and walk. No body's box ever has a corner in what its mover counts as a wall (land for a boat; walls and water for feet and wheels), judged from the world map and the tileset (`boats.walls`). A run stopped at each swap compares the body tables before and after the fetch and the module in place with its binary (`boats.swap`). The boat slides and throws spray (`boats.slide`), meets the shore (`boats.shore`), rams the launch (`boats.ram`); the player ends on foot, on land, with the ground module in (`boats.landed`); two runs end alike (`boats.repeat`).

**Sky.** Built with a helicopter (`build/sky-auto.prg`), the tape gets in, which swaps the air module in; flies over a six-storey block and settles onto its roof; flies back and settles onto the road; gets out, which swaps the ground module back. No body's box ever has a corner in what its mover counts as a wall, the helicopter's walls being buildings standing higher than it, from the tileset's heights (`sky.walls`); the swaps as for the boats (`sky.swap`); the helicopter is over the building in the air, rests on its roof at the roof's height, and never passes the ceiling (`sky.flight`); the player ends on foot, on land, with the ground module in (`sky.landed`); two runs end alike (`sky.repeat`).

**Budgets.** Every line of `budgets.txt` is measured and held to its limit, the larger value of the two tiers counting. A measurement without a line fails too, so nothing is measured and ignored.

| Measured | How |
|---|---|
| `engine.bytes`, `lowram.bytes` | segment sizes from the link maps |
| `bench.*` | `examples/bench`, read at `test_done` |
| `overlay.load_6k` | `examples/overlay`, the first 6 KB load (region A) |
| `cutscene.tick_*` | the emulator's own cycle counter in the plain build, from the callback to the end of the engine's frame work, interrupts included, over 160 frames of the drive |
| `bench.scroll_*` | the benchmark program: one prepare for a crossing right, down and diagonally, interrupts off |
| `scroll.worst_frame` | the autodrive scroller's own maximum, reset after the first full draw, over twice round its square |
| `scroll.frames_dropped` | frames without a callback in the same 800 |
| `bench.mux_*` | the benchmark program: `b64_spr_end` for the harness's 32 sprites, interrupts off |
| `mux.irq_frame` | the emulator's cycle counter from the interrupt handler's entry to its RTI, summed per frame, median of 20 |
| `traffic.frames_lost` | frames without a callback in 3,000 of the traffic demo driving itself |
| `boats.step_*`, `boats.frames_lost`, `sky.*` | the same as the physics lines, over the coast's and the sky's 700 steps, through the jump table at $6009 so either module is timed |
| `physics.step_*`, `physics.frames_lost` | `phys_step` from entry to the callback's next routine (`shot_step`), interrupts included, every step of the tape in a third run (the first two are the frame-driven runs `physics.repeat` compares); frames without a callback in 800 |

The profile build (`build/prof/cutscene.prg`) is checked only for linking and filling its block. Its numbers are upper bounds and are not budgeted.

## Running it

```
make check                   # everything, both tiers
make check CHECKFLAGS=--keep # keep the frames in build/check even when it passes
python3 tools/b64check.py --tier 8 --only showcase,static
```

The names for `--only` are `static`, `bench`, `overlay`, `cutscene`, `showcase`, `boot`, `scroller`, `ticks`, `probe` and `mux`. On a failure the frames it looked at stay in `build/check`, and the CI run uploads them.

## What it does not check

- Anything VICE cannot emulate: the turbo, Ultimate Audio and the command interface. Those stay marked UNTESTED until they have run on a C64 Ultimate (`docs/ULTIMATE.md`).
- The joystick-driven examples beyond the autodrive build.
- Sound.
- Pixel-exact screenshots at every instant. A monitor screenshot taken in the lower border can, in some frames, hold rows that differ from what the frame drew; the multiplexer's correctness is therefore checked on its timing, from the registers, and its pictures are checked only for damaged sprites, never for absent ones.
- Real hardware timing. VICE's x64sc is cycle-exact for the stock machine, which is why tier 0 is proven there, but the first hardware run (roadmap step 5) is its own check.
