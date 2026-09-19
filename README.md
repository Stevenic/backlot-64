# backlot-64

[![check](https://github.com/Stevenic/backlot-64/actions/workflows/check.yml/badge.svg)](https://github.com/Stevenic/backlot-64/actions/workflows/check.yml)

A rendering and data engine for the Commodore 64 with an REU, built first for Priors-64, an open-world driving game set in a fictional Florida, and meant to outlive it.

Two halves. The rendering half draws a multicolour character-mode world of up to 2048x2048 metatiles, scrolls it in 8 directions with DMA-assisted screen shifts, multiplexes 24 sprites, and handles raster splits, charset animation, text, and transitions. The data half treats the REU as the program's real memory and the 64 KB as a cache: it streams world data and assets, runs code overlays, and keeps a page cache so scripts and text execute from expansion memory. On top of both sits a module system: physics, AI, pathfinding, collision, scripting, and sound come in tiers, all in assembly, and a game picks the tiers it wants in a manifest that the build checks against the machine's RAM and frame budget. Everything per-frame is hand-written 6502. One build scales from a stock C64 with an 8 MB REU to the C64 Ultimate (16 MB, turbo CPU, PCM sampler, files into the REU), probing the machine at boot; see `docs/ULTIMATE.md`.

See [docs/PLAN.md](docs/PLAN.md) for principles, budgets, memory map, API, data formats, and milestones, and [docs/PREPARE.md](docs/PREPARE.md) for how to prepare every kind of data the engine consumes. [docs/ROADMAP.md](docs/ROADMAP.md) is where it is going, [docs/PRIOR-ART.md](docs/PRIOR-ART.md) is what it learned from other C64 engines, and [CREDITS.md](CREDITS.md) names everyone whose work it stands on.

**Watch it:** every example, recorded in VICE on a stock C64 with an 8 MB REU, is on the demo site at https://stevenic.github.io/backlot-64/ (`make pages` records them; `make publish-pages` updates the site).

## Requirements

```
brew install cc65 vice
```

macOS, for now: the art quantiser resamples with `sips`.

## Layout

```
docs/       engine plan and, later, API reference
include/    .inc files games assemble against: ZP map, constants, macros
src/        engine source, one file per subsystem, prefixed b64_
tools/      Python packers: tileset, world, sprites, font, REU image, palette report, portrait quantiser; the VICE harness, make check, benchmark and probe readers
images/     generated art (art-style.md is the prompt contract; candidates archive under images/archive/)
```

## Build and run

```
make                # engine, examples, build/world.reu (16 MB REU image) and build/world8.reu (8 MB)
make check          # everything proven in VICE at both REU tiers, held to budgets.txt (docs/CHECK.md)
make run-showcase   # baked lighting: day to night, then a cruiser whose own lights light the street
make run-scroll     # x64sc with the REU attached; joystick 2 drives the camera
make bench          # DMA and VM costs; REUSIZE=8192 for the stock tier
```

## Status

E0 core, E0.5 data engine (first cut), E1 scroller, E3 sprite multiplexer, the E4 HUD split, and E12 cutscenes are running. `make run-showcase` shows baked lighting: a street at noon falls to night through 32 streamed colour maps, then a police cruiser whose light bar is declared in its own object file lights only the surfaces near each lamp, without the bitmap ever changing. `make run-physics` puts you on foot beside four parked vehicles: walk, get in, drive into the others and they are shoved by their mass (docs/PHYSICS.md). `make run-traffic` drives a car through Bellamar's grid among up to 24 others that keep their lanes, stop at the lights, queue and turn, with no line ever carrying more sprites than the hardware can show (docs/PLAN.md 3.4). `make run-overlay` loads two 6 KB code overlays from the REU into the same window and runs each, the proof of the data engine's code paging. `make run-cutscene` plays a scene written as p-code for the engine's VM (`src/b64_vm.s`), read from the REU through the page cache so none of it is resident: a bitmap set from generated art, a sprite-grid actor, a blitted prop, and a text band. The scroller streams a 2048x2048 metatile world from the REU with DMA screen shifts and measures its own frame cost on screen. Its preparation's worst cell crossing is 5,754 cycles against a 6,000 target. The multiplexer takes 24 sprites on a stock C64 and 32 or 64 with the C64 Ultimate's turbo (not yet run on the hardware; `docs/ULTIMATE.md` has the test). `make check` proves all of it on every push, and a program refuses to run on an REU image it was not built for. See the milestone table in the plan, and [docs/ART.md](docs/ART.md) for how to draw tiles.

## License

MIT. See [LICENSE](LICENSE).
