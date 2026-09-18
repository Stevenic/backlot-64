# backlot-64

A rendering and data engine for the Commodore 64 with an REU, built first for Priors-64, an open-world driving game set in a fictional Florida, and meant to outlive it.

Two halves. The rendering half draws a multicolour character-mode world of up to 2048x2048 metatiles, scrolls it in 8 directions with DMA-assisted screen shifts, multiplexes 24 sprites, and handles raster splits, charset animation, text, and transitions. The data half treats the REU as the program's real memory and the 64 KB as a cache: it streams world data and assets, runs code overlays, and keeps a page cache so scripts and text execute from expansion memory. On top of both sits a module system: physics, AI, pathfinding, collision, scripting, and sound come in tiers, all in assembly, and a game picks the tiers it wants in a manifest that the build checks against the machine's RAM and frame budget. Everything per-frame is hand-written 6502. One build scales from a stock C64 with an 8 MB REU to the C64 Ultimate (16 MB, turbo CPU, PCM sampler, files into the REU), probing the machine at boot; see `docs/ULTIMATE.md`.

See [docs/PLAN.md](docs/PLAN.md) for principles, budgets, memory map, API, data formats, and milestones, and [docs/PREPARE.md](docs/PREPARE.md) for how to prepare every kind of data the engine consumes. [docs/ROADMAP.md](docs/ROADMAP.md) is where it is going, [docs/PRIOR-ART.md](docs/PRIOR-ART.md) is what it learned from other C64 engines, and [CREDITS.md](CREDITS.md) names everyone whose work it stands on.

## Requirements

```
brew install cc65 vice
```

## Layout

```
docs/       engine plan and, later, API reference
include/    .inc files games assemble against: ZP map, constants, macros
src/        engine source, one file per subsystem, prefixed b64_
tools/      Python packers: tileset, world, sprites, font, REU image, palette report, portrait quantiser, benchmark runner
images/     generated art (art-style.md is the prompt contract; candidates archive under images/archive/)
```

## Build and run

```
make                # engine + example + build/world.reu (8 MB REU image)
make run-scroll     # x64sc with the REU attached; joystick 2 drives the camera
make shot-scroll    # headless autodrive screenshots in build/
```

## Status

E0 core, E0.5 data engine (first cut), E1 scroller, E3 sprite multiplexer, the E4 HUD split, and E12 cutscenes are running. `make run-cutscene` plays a scene written as p-code for the engine's VM (`src/b64_vm.s`), read from the REU through the page cache so none of it is resident: a bitmap set from generated art, a sprite-grid actor, a blitted prop, and a text band. The scroller streams a 2048x2048 metatile world from the REU with DMA screen shifts and measures its own frame cost on screen. Worst case is about 9,200 cycles against a 6,000 target; the fills are the next optimisation. See the milestone table in the plan, and [docs/ART.md](docs/ART.md) for how to draw tiles.

## License

MIT. See [LICENSE](LICENSE).
