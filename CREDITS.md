# Credits

Backlot-64 stands on other people's work. This file names every source an idea, a technique, a number or a tool came from. If something here is borrowed from you and credited wrongly or not at all, open an issue and it will be fixed.

## Engine techniques borrowed or planned

Details and rankings are in `docs/PRIOR-ART.md`. Each adopted technique also carries a comment naming its origin at the point of use in `src/`.

- **Lasse Öörni (Cadaver)**, c64gameframework (MIT) and the rants at cadaver.github.io: colour packed into the screen code for one-lookup redraws, persistent sprite order sorted only when the count changes, grouped sprite IRQs with a count-aware advance and direct fall-through when late, ninth-sprite rejection, the two-frame sprite-cache guard, two-frame logic with interpolation, the re-entrant frame-update IRQ.
- **Linus Åkesson**, the Å-machine 6502 engine: the zero-page fetch through a self-modified page byte, page-aligned `jmp (table)` dispatch with pre-doubled opcodes, per-byte page wrap, the page table with second-chance eviction and a pinned current page, operand-type bits in the operand, short relative branches.
- **Honza Slesinger**, DOOM for the C64 Ultimate (CC BY-NC-SA 4.0): the measurement that REU DMA costs one microsecond per byte at every CPU speed and the CPU-copy consequence on turbo, the SID register stream, header-first two-stage fetches in power-of-two slots, the self-describing REU image header with boot cross-checks, the millisecond clock and frame histogram, the turbo and Ultimate Audio recipes, and the finding that VICE boots an empty REU when the image size does not match the unit.
- **Michael Steil** (pagetable.com) and the **ScummVM** project, for SCUMM v0 as used in Maniac Mansion: freeze and override for cutscenes, the deferred sentence queue as the model for event-driven entity threads, the script slot fields, bitvars, per-script locals.
- **hhprg**, C64Engine (MIT): layer-aware hardware sprite allocation, difference-list colour shifts, the priority task ring, flip-bit virtual characters (considered, not taken).
- **Markus Leissa**, c64engine (GPL-3.0, ideas only): Y-order sprite thinning, fill budgets across frames, the AGSP/VSP analysis (considered, not taken).
- **Scott Robison and David Murray**, Attack of the PETSCII Robots C64 REU edition (study licence, ideas only): editing the master copy of an asset in the REU so every instance updates, the dirty-cell compare before a bitmap DMA, per-index address tables for streamed tiles, self-stashing asset programs.
- **Stefano Coppi**, Chrome Horizon: the parallax split with a mid-screen scroll register write.
- **Bobbi Webber-Manners**, EightBall: the frame-pointer-relative locals scheme; the stack-machine comparison that confirmed the register model.
- **Steve Wozniak**, SWEET16: the single-page dispatch table and push-and-return jump that the VM's first dispatcher used.

## Ultimate 64 and C64 Ultimate

- **Gideon Zweijtzer**, Gideon's Logic Architectures: the Ultimate 64, the C64 Ultimate firmware, the Ultimate Audio Register API (v0.2, 2012), the Command Interface register documentation, and the turbo control documentation. Every register address in `src/b64_plat.s`, `src/b64_pcm.s` and `src/b64_uci.s` comes from these.
- **xahmol**, UltimateDemo2026 (GPL-3.0): the reference implementation read for the turbo library (CIA time-of-day detection), the Ultimate Audio channel layout and the 6-bit volume finding, the UCI transport and the DOS load-to-REU command format. Read for understanding; no code copied.
- **6510nl**, ModPlayer_16k: the Ultimate Audio detection routine (idle status, silent looped sample, end flag) that the boot probe's audio test follows.
- **Barry Walker**, ultimate-uci-sdk: the "probe, do not assume a model" principle for capability detection.
- **Bumbershoot Software**: the write-up confirming REU behaviour matches between VICE and the C64 Ultimate and that turbo is where they diverge.

## Hardware and platform references

- **Christian Bauer**, "The MOS 6567/6569 video controller (VIC-II) and its application in the Commodore 64": badlines, sprite DMA, the timing of every VIC register. The docs audit in the roadmap is against this text.
- **Codebase64** (codebase64.org): the community wiki of C64 programming idioms.
- **Commodore 64 Programmer's Reference Guide** and **Sheldon Leemon, "Mapping the Commodore 64"**: the memory map and the register descriptions.
- **Philip "Pepto" Timmermann**: the VIC-II colour measurements used for the palette and the luminance ladder in `docs/ART.md`.
- **The VICE team**: the emulator every number in this repository was measured on, its remote monitor, and its cycle-exact `x64sc`.
- **The cc65 project**: `ca65` and `ld65`.
- **Commodore Business Machines**: the machine, and the 1750 REU whose DMA controller this engine treats as its memory bus.

## How this project was built

The engine was designed and directed by Steven Ickman and written with AI assistance (Anthropic's Claude), which is disclosed in every commit's trailer. Every performance claim was measured in VICE; every visual claim was checked by frame diff; the platform code for tiers VICE cannot reach is marked untested until it has run on hardware. Using or contributing to the engine needs no AI: it is plain `ca65` assembly and Python. Generated concept art in `images/` is placeholder and will be replaced by hand-drawn work before any release.
