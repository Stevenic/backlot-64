# Instrumentation: the Probe

The engine measures itself the same way on the emulator and on the hardware, and the measurements feed the optimizer. This is the path.

## What a probe build records

`make build/prof/<example>.prg` assembles every engine source with `-DB64_PROFILE` into `build/prof/`. The probe module (`src/b64_probe.s`) then owns 2 KB at $F800, the top of the game's hot-state region, and records four things without stopping the program:

| Record | How | Cost in a probe build |
|---|---|---|
| **Events** | Every `FTRACE` point in the engine writes (tag, frame, raster line) into a 160-entry ring: the order of work within a frame | about 120 cycles per event, about 14 events a frame on the cutscene |
| **Samples** | CIA1 timer B fires every 4,093 cycles, a prime, so the samples sweep every phase of the frame; the handler records the interrupted program counter and, when the VM was running, the thread and its script offset, into a 128-entry ring | about 100 cycles per sample, 5 samples a frame at 1 MHz; under turbo the timer still counts the 1 MHz clock, so samples stay 4,093 microseconds apart and the tick and histogram are wall time |
| **Opcodes** | The VM dispatch counts each opcode into 128 16-bit counters | 14 cycles per opcode |
| **Tick** | The game callback plus the engine's frame effects, timed with the CIA2 timers: last, worst, and a histogram in 1,024-cycle buckets | about 100 cycles a frame |

A probe build is a debug build: the overhead is real (the events alone are close to a tenth of a frame on the cutscene) and a game that uses $F800 to $FFF9 cannot be probed. Without the define, every hook assembles to nothing and the module is not resident.

## Reading it back

`tools/b64probe.py` pulls the block and decodes it identically from three sources:

- `--vice <prg>` runs the program in `x64sc` with the remote monitor, waits `--seconds`, and saves the block through the monitor. `make probe-<example>` does this for any example.
- `--host <ip>` reads the block from a C64 Ultimate over its REST interface, `GET /v1/machine:readmem?address=F800&length=1440`, with `--password` for the network password and `--run <prg>` to upload and start the program first through `POST /v1/runners:run_prg`. Written from the REST documentation; UNTESTED until the hardware arrives.
- `--file <bin>` decodes a saved block.

Symbols come from the label files ld65 writes with `-Ln`: `--labels` for the program (probe builds assemble with `-g` so every routine is named, not only exports) and `--script-labels` for the script. `--json` writes the decoded profile for tools.

The report shows the platform the probe found, the tick's last and worst cycles with the histogram, the time share per engine routine, the script offsets the VM was found at (by thread, mapped to labels), the opcode mix, and the last events in order.

## What it found on its first run (cutscene, VICE, 2026-09-17)

- The main loop was idle at the vertical blank in every sample, so sampling at the blank alone measures nothing; hence the timer.
- The tick timer included the wait for the sprite hand-off, which happened inside the callback; the main loop now waits for the hand-off before calling the callback, so the timer measures work.
- Of the busy time: about a quarter in the VM's dispatch and thread loop, an eighth each in the object's animation lookup and the shimmer, a tenth in the sprite list sort. Those are the next targets, in that order.

## Feeding the optimizer

The JSON profile carries, per script offset, how often the VM was found there; per opcode, how often it ran; and per frame, how long the tick took. The compiler's optimizer (`MODULES.md`) will read it to rank loop bodies by cycles spent, decide which become native spans within the pinned budget, and report what it chose and why. The same file from a hardware run is the same format, so a profile taken on the C64 Ultimate under turbo ranks the same way; only the absolute cycle counts differ, and the tick histogram is what says whether the frame holds there.

## The multiplexer's test build

The probe measures cost. Whether the multiplexer writes every sprite in time is a different question, and it has its own test build: `make build/mlog/mux.prg build/mlog/mux64.prg` assembles the engine with `-DB64_MUXLOG` into `build/mlog/` and links the multiplexer harness (`examples/mux`; `mux64` is the 64-sprite layout). `tools/b64muxhw.py` runs it on VICE (`--vice build/mlog/mux64.prg`) or on a C64 Ultimate (`--host <ip> --prg build/mlog/mux64.prg`, procedure in `docs/ULTIMATE.md`) and judges what it logged.

**What it logs** (at `B64_MUXLOG_AT`, $E800, 512 bytes): per group, the raster line as its interrupt begins; per list position, a stamp taken just after the entry's Y and pointer are written; and 128 calibration samples.

**The log clock.** A stamp is one read of CIA1 timer A, which counts four raster lines (4 x 63 cycles) over and over, started on a line that is a multiple of 4. A PAL frame is 312 lines, also a multiple of 4, so the count keeps its place frame after frame, and one read gives the line modulo 4 and the cycle. The CIA counts the 1 MHz clock with or without the turbo, so the clock means the same on every tier. (A CIA timer locked to the raster is an old technique for stable raster interrupts; here it is only a clock, and no single source is claimed for it.) The group's start line anchors its first stamp and each stamp the next: a stamp is at the first time after the one before that matches its count. That is exact while events are under four lines apart; at 1 MHz the code between two of them is under 70 cycles, and the VIC-II can steal at most about 62 more a line, so they are under 200 cycles apart. The phase of the count is found at start: `mux_clock` samples the count just after the raster moves to a new line, with a 10-cycle polling loop (10 is prime to 63, so the samples land at every cycle of the line), and the earliest sample is the line's start.

**What it checks,** from snapshots taken while the harness is frozen (the host writes 1 to $E020; the harness stops building lists, the engine shows the same list every frame, and three frames later the harness writes 1 to $E021): no group starts before every member's previous occupant is shown (Y + 22, Bauer 3.8); every entry's Y is written before cycle 55 of its line and its pointer before the pointer fetch (at 1 MHz the Y store is at least 28 cycles before the stamp and the pointer store 4; with the turbo the stamp itself stands for both, which can only err towards late); the blank's group 0 comes after every sprite's last occupant is shown; and the groups cover the list once, in y order. It also reports what the timing model is set from: the lines from a group's line to its first entry's stamp (`mux_lead1` should be that plus a line) and between entries of a group (`mux_step`), and the least slack before any deadline.

**The instrument is checked too.** On VICE, `--validate` breaks just after each stamp's read and compares the rebuilt time with the emulator's own line and cycle: every stamp lands on the emulator's line, 0 to 2 cycles after its cycle and never before (`muxhw.clock` in `make check`).

**Measuring changes what it measures.** The first version read the timer and the raster line for every entry (18 cycles) and logged each group's end as well (18 more). That slowed the chain enough that the test build wrote entries late where the plain build, checked cycle by cycle with `tools/b64muxtiming.py`, wrote none. The stamp is now one read (9 cycles) and a group logs only its start (7). The allocation is the same in both builds and the test build's chain is the slower, so a pass in the test build is a pass in the real one; a failure there is a failure to check with the plain build before believing it.

## Rules

- `FTRACE` points stay in the source. Add one wherever a timing question might be asked; they cost nothing outside probe builds.
- The `probe_event` routine and everything else in the probe never sits at the code segment's first byte, which is the entry jump; the first attempt did, and the program returned to BASIC.
- Never read a raster line from the probe's numbers without the frame: the VIC gives the low eight bits, so lines 256 to 311 read as 0 to 55.
- A number from a probe build is an upper bound; confirm a budget with the plain build's benchmark before writing it down.

The sampling and histogram design is after Honza Slesinger, DOOM C64U (`src/instrument.asm`, `src/clock.asm`). Changed: a prime-interval timer instead of the frame boundary, so the samples cover the frame; and samples carry the VM thread and script offset, so one run profiles the p-code as well as the engine.
