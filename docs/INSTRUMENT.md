# Instrumentation: the Probe

The engine measures itself the same way on the emulator and on the hardware, and the measurements feed the optimizer. This is the path.

## What a probe build records

`make build/prof/<example>.prg` assembles every engine source with `-DB64_PROFILE` into `build/prof/`. The probe module (`src/b64_probe.s`) then owns 2 KB at $F800, the top of the game's hot-state region, and records four things without stopping the program:

| Record | How | Cost in a probe build |
|---|---|---|
| **Events** | Every `FTRACE` point in the engine writes (tag, frame, raster line) into a 160-entry ring: the order of work within a frame | about 120 cycles per event, about 14 events a frame on the cutscene |
| **Samples** | CIA1 timer B fires every 4,093 cycles, a prime, so the samples sweep every phase of the frame; the handler records the interrupted program counter and, when the VM was running, the thread and its script offset, into a 128-entry ring | about 100 cycles per sample, 5 samples a frame |
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

## Rules

- `FTRACE` points stay in the source. Add one wherever a timing question might be asked; they cost nothing outside probe builds.
- The `probe_event` routine and everything else in the probe never sits at the code segment's first byte, which is the entry jump; the first attempt did, and the program returned to BASIC.
- Never read a raster line from the probe's numbers without the frame: the VIC gives the low eight bits, so lines 256 to 311 read as 0 to 55.
- A number from a probe build is an upper bound; confirm a budget with the plain build's benchmark before writing it down.

The sampling and histogram design is after Honza Slesinger, DOOM C64U (`src/instrument.asm`, `src/clock.asm`). Changed: a prime-interval timer instead of the frame boundary, so the samples cover the frame; and samples carry the VM thread and script offset, so one run profiles the p-code as well as the engine.
