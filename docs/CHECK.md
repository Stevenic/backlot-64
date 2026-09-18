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

**The multiplexer.** The harness (`examples/mux`) runs 24 sprites on paths the checker can reproduce, first at most four to a line, then bunched so a line carries up to twelve. `tools/b64muxtiming.py` breaks at every generated sprite routine and checks that each hardware sprite is moved only after its previous occupant's last line and before its new occupant's first. At normal density nothing may be dropped; overloaded, something must be; and no sprite may be drawn damaged in 60 captured frames. `tools/b64irqcost.py` measures the interrupt cycles per frame.

**Budgets.** Every line of `budgets.txt` is measured and held to its limit, the larger value of the two tiers counting. A measurement without a line fails too, so nothing is measured and ignored.

| Measured | How |
|---|---|
| `engine.bytes`, `lowram.bytes` | segment sizes from the link maps |
| `bench.*` | `examples/bench`, read at `test_done` |
| `overlay.load_8k` | `examples/overlay`, the first 8 KB load |
| `cutscene.tick_*` | the emulator's own cycle counter in the plain build, from the callback to the end of the engine's frame work, interrupts included, over 160 frames of the drive |
| `bench.scroll_*` | the benchmark program: one prepare for a crossing right, down and diagonally, interrupts off |
| `scroll.worst_frame` | the autodrive scroller's own maximum, reset after the first full draw, over twice round its square |
| `scroll.frames_dropped` | frames without a callback in the same 800 |
| `bench.mux_*` | the benchmark program: `b64_spr_end` for the harness's 24 sprites, interrupts off |
| `mux.irq_frame` | the emulator's cycle counter from the interrupt handler's entry to its RTI, summed per frame, median of 20 |

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
