# backlot-64

A rendering and data engine for the Commodore 64 with an REU. Assembly for everything per-frame; data for everything else.

Read these before working here:

- `docs/JOURNAL.md` — the engineering journal: how the engine is being built with AI, step by step. Add an entry at each milestone: what was asked, what was decided and by whom, what was built, what was measured, and what went wrong. Mistakes stay in the record. It records the work only; it carries no commentary on people or communities.
- `docs/PLAN.md` — what the engine is, its budgets, memory map, API, milestones.
- `docs/MEMORY.md` — the memory strategy: what is resident, what is paged and by whom, DMA times, game state in chunks.
- `docs/PAGING.md` — the catalogue of paging strategies, what each costs, which data gets which, and what cannot or should not be paged.
- `docs/ROADMAP.md` — the phased forward plan; work in its order unless the user says otherwise.
- `CREDITS.md` — every source of an idea, number or tool. When you adopt a technique from anywhere, add a comment naming its origin at the point of use and an entry here in the same change. The comment has a fixed shape: `After <author>, <project> (<file>).` then `Changed: <what differs and why>.` when this engine departs from the source, or `As is.` when it does not. An improvement is stated as a measured difference, never as a claim; unmeasured, write `Changed:` and the reason, not `Improved:`. `docs/PRIOR-ART.md` keeps the same form per entry, and its "Where this engine departs from its sources" section is the public record of every departure.
- `docs/PRIOR-ART.md` — what other C64 engines do that this one should borrow, ranked, with credit; check it before redesigning the fills, the multiplexer or the VM dispatch.
- `docs/MODULES.md` — modules as overlays managed by the VM: pinned versus cached residency, the code cache, SYS and NEED, and the plan the script compiler emits. Supersedes the build-time residency in PLAN.md section 4.
- `docs/CHECK.md` — `make check`: what it proves, how it drives VICE, and `budgets.txt`. A change is done when it passes.
- `docs/INSTRUMENT.md` — the probe: how the engine measures itself on VICE and on the hardware, and how the profile feeds the optimizer.
- `docs/ULTIMATE.md` — the platform tiers from a stock C64 to the C64 Ultimate: what the boot probe finds, the turbo, sampler and command-interface registers, and what has run only on paper.
- `docs/PREPARE.md` — how to prepare every kind of data the engine consumes: sets, objects, portraits, tilesets, worlds, the REU image. Follow it literally; it is the contract.
- `docs/ART.md` — the colour rules and how to draw for the chip.
- `art-style.md` — the prompt contract prepended to every image generation.

Rules of the repository:

- Per-frame code is engine assembly in `src/`. Games supply data and scripts, never per-frame code.
- Scripts are p-code blobs assembled at offset 0 with `script.cfg` and packed as REU slots (see `reu.manifest`); a game's resident code only starts them. Code overlays are assembled for the window with `overlay.cfg`, linked against the resident program's label file by `tools/b64overlay.py` (so they may call any `.global` engine routine), packed as slots, and fetched with `b64_overlay_load`; the render path never depends on one being present. `make bench` measures DMA and VM costs; assemble `src/b64_vm.s` with `-DVM_TRACE` to log every dispatch at $E100 when a script misbehaves; `make probe-<example>` builds the example with `-DB64_PROFILE` into `build/prof/` and prints a profile (events at every `FTRACE` point, a timer-driven program-counter sample with the VM thread and script offset, opcode counts, the tick histogram) read from VICE; `tools/b64probe.py --host` reads the same block from a C64 Ultimate. See `docs/INSTRUMENT.md`. Probe numbers are upper bounds; confirm budgets with the plain build.
- The reference machine is tier 0: a stock C64 with an 8 MB REU, as VICE emulates it (`make bench REUSIZE=8192`, `build/world8.reu`). Everything is proven there first. Extras from the platform probe (`b64_plat`) add headroom and features, never correctness. Code for tiers VICE cannot reach (turbo, Ultimate Audio, UCI) is marked UNTESTED in its header until it has run on the hardware.
- Resident RAM is the scarce resource. Assembly is for per-frame work and byte moving only; everything a game decides is p-code for the VM (`src/b64_vm.s`). A new behaviour is never a new opcode. Opcode bytes are doubled indices into a vector table that `b64_vm_start` copies to the page at $C900; add an opcode by appending to the table and the `VM_OP_*` list together. Watch the sizes in `build/cutscene.map`.
- Never read the VIC control register ($D011) back and rewrite it: bit 7 reads as the raster's high bit. Write it from constants.
- The interrupt saves the shared zero-page scratch; a DMA's register writes run with interrupts masked. Keep both when adding vertical-blank work, and keep the vertical blank short: the sprite list is taken first, and anything costing more than a few hundred cycles (the shimmer) runs from the main loop through `b64_cut_frame`, not the interrupt. A tick is about 9,600 cycles today; measure with `make probe-<example>` before adding to either side.
- The sprite list is handed to the vertical blank only when `b64_spr_end` has finished it; `b64_spr_begin` waits for the handoff. Do not touch the list arrays from interrupt code.
- Nothing in assembly hard-codes an REU address; use the symbols in `build/slots.inc` from `reu.manifest`. The image carries a header that `b64_boot_check` verifies at boot, so a program never runs on an REU packed from another manifest.
- Lighting is colour maps, never bitmap edits: `tools/b64light.py` makes them and the engine applies them in a base-phase blank. A light belongs to the object that carries it: declare it in the object file's lights section (`--lights`), bake with `b64light.py object`, and let LIGHTS drive both the lamp sprites and the maps. Scripts never compute lamp positions (see `docs/PREPARE.md`).
- `make check` must pass before anything is called done or committed. It runs in CI on every push. A new capability gets a check in `tools/b64check.py` in the same change, and a new cost gets a line in `budgets.txt`; raising a limit is a decision stated in the commit. Every converted asset is also looked at in the emulator; `tools/b64vice.py` is the way to drive VICE from a script (it waits on the monitor's prompt, never on sleeps).
- The quantisers report repairs and damage. High numbers mean fix the art, not the tool.
- Branches on the 6502 reach 127 bytes; loops with DMA calls in them need `jmp`. After a subroutine, test the value (`cmp #0`), never the flags it happened to leave.
- `sips -c` and `-z` must be separate calls.
- The OpenAI key for image generation is not in this repo; the gen script reads it from the environment.
