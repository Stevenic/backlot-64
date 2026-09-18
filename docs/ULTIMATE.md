# Scaling from a stock C64 to the C64 Ultimate

The engine runs on one program that probes the machine at boot and grows into what it finds. Nothing per-frame depends on an extra; extras add headroom, memory and features. The reference machine is a stock C64 with an 8 MB REU, which is what VICE's x64sc emulates cycle-exactly, including the VIC stealing bus cycles from the REU. VICE reaches the 16 MB tier. Turbo, the sampler and the command interface exist only on the hardware.

## The tiers

| Tier | Machine | Probe | What the engine does with it |
|---|---|---|---|
| 0 | C64 + 8 MB REU (VICE `-reusize 8192`; RAD or an Ultimate set to 8 MB) | REU answers, $FF0000 wraps to $7F0000 | Everything in the plan. Game heap $600000-$7DFFFF. |
| 1 | + 16 MB REU (VICE `-reusize 16384`, Ultimate 64, C64 Ultimate) | $FF0000 does not wrap | Game heap $800000-$FEFFFF, 8 MB for run-time data. |
| 2 | + turbo CPU (Ultimate 64, C64 Ultimate) | $D031 reads not $FF and takes a write | VM budget 255 opcodes per thread per frame instead of 64. `b64_turbo_fast` for headroom. |
| 3 | + Ultimate Audio | $DF20 idle status 0, silent test loop raises the end flag (the first test alone is not enough: a real REU mirrors its status register at $DF20, and VICE mirrors it through $DFFF) | 7 PCM channels straight from the REU: `b64_pcm_*`, the PCM opcode. |
| 4 | + Command Interface | $DF1D reads $C9 after the unlock | Files from the Ultimate's storage into REU slots at run time: `b64_uci_load`. |

A real 1750 is 512 KB and has only three bank bits, so it also passes the wrap test. It never gets that far: `b64_boot_check` looks for the image header at $4FF000 first, which a 512 KB unit cannot hold, and halts with the no-image colour.

The probe is `b64_plat_probe` in `src/b64_plat.s`, run by `b64_init`. It leaves `b64_plat` (one bit per feature), `b64_reu_mb`, the VM budget and the heap bounds. A game reads the bits; it never probes registers itself. `make bench` prints what the probe found.

Measured in VICE on 2026-09-17: tier 0 with `make bench REUSIZE=8192` reports `reu; REU 8 MB`, tier 1 with the default reports `reu reu16; REU 16 MB`, and the cutscene example plays identically on both with a pixel-exact park. Tiers 2 to 4 are written from the register documentation and have not run on hardware yet.

## Registers

**Turbo, $D030 and $D031.** Bits 0 to 3 of $D031 pick a speed index, 0 for 1 MHz and 15 for the maximum (48 MHz on the Ultimate 64 and Elite I, 64 MHz on the Elite II and the C64 Ultimate). Bit 7 stops the VIC's badline stalls from halting the CPU. $D030 bit 0 is the C128-style enable and is set with any non-zero index. The register reads $FF when the Ultimate's menu has turbo control off, so the menu must be set to "U64 Turbo Registers". The VIC keeps bus priority at every speed, so graphics and raster splits stay correct; only the amount of CPU work per frame changes. CIA timers keep counting the 1 MHz clock at every turbo speed, so `make bench` under turbo reports elapsed microseconds, not CPU cycles executed (measured on hardware by Honza Slesinger for DOOM C64U, `src/clock.asm`, and on an Ultimate 64 Elite in JC-000/c64-https PR 205; the Ultimate's own documentation is silent). $D031 is live only when the menu's Turbo Control is "U64 Turbo Registers" or "Turbo Enable Bit", and reads $FF in "Off" and "Manual"; $D030 bit 0 (0 is 1 MHz with badlines, 1 uses the menu or $D031 setting) exists only in "Turbo Enable Bit" mode. Badline suppression through bit 7 applies to internal memory only: cartridge-port and socketed-SID accesses still wait for the VIC. The speed table behind the index differs between boards, so only index 0 and index 15 mean the same everywhere.

**Ultimate Audio, $DF20 to $DFFF.** Seven channels of 32 write-only registers at $DF20 + n × 32, from the Register API v0.2. Control at +0 (gate, repeat, irq, mode 00 = 8-bit PCM), volume at +1 (0 to 63), pan at +2 (0 to 15), start at +4 as $01 then the REU address big-endian, length at +9 big-endian, rate divider at +$0E big-endian where the divider is 6,250,000 over the sample rate, repeat points at +$11 and +$15, interrupt clear at +$1F. Reading $DF20 gives the interrupt status and $DF21 the module version. The module must be mapped in the "C64 and cartridge settings" menu and the audio outputs set to the sampler.

**Command interface, $DF1B to $DF1F** ($DF1B is the read-only SoftwareIEC bus id; the block masks the REU's last registers, and must be enabled in the menu's Command Interface setting unless unlocked). Status and control at $DF1C, command byte and id at $DF1D, response data at $DF1E, status data at $DF1F. Firmware 3.15 and later unlock the mapping with $AB to $D038 then $CD to $D036; the firmware's own loader then waits before reading the id, so the probe must too. Whether the unlock works from a program rather than cartridge software is not established. The engine speaks to the DOS target only: open (command $02, attribute $01, name), load into the REU (command $21, address and length as 32-bit little-endian), close ($03). Each command is pushed with control bit 0, waited on through status bits 4 and 5, drained, and acknowledged with control bit 1.

## Policy

- **Correctness at tier 0.** Every feature is checked in VICE at 8 MB before it is called done. A frame that needs turbo to fit is a bug.
- **Turbo is headroom.** The engine leaves the speed where the menu put it. A game calls `b64_turbo_fast` when it wants the budget (the default for Priors-64 when the register exists) and `b64_turbo_slow` around anything cycle-timed. The VM budget follows the probe automatically.
- **DMA does not speed up.** REU transfers stay bus-bound, so the paging numbers in `MEMORY.md` hold on every tier.
- **The 16 MB image is the build.** `reu.manifest` declares 16384; the stock tier runs the first 8 MB of the same image (`build/world8.reu`). Every packed asset lives below 8 MB; the upper half is the tier 1 heap.
- **Sound is optional data.** The PCM opcode plays a sample on tier 3 and does nothing elsewhere, so a script can ask for a sound on any machine. Samples are 8-bit PCM packed as slots.
- **The probe reads the same on every tier.** A probe build's block at $F800 is read through VICE's monitor on tiers 0 and 1 and through the Ultimate's REST interface (`GET /v1/machine:readmem`) on the hardware; `tools/b64probe.py --host <ip>` also uploads and starts a program (`POST /v1/runners:run_prg`). Same decoder, same report. Untested on the hardware until it arrives.
- **Code overlays are the same DMA on every tier.** The 6502 cannot run code from the REU on any machine; an overlay is 8 KB fetched into RAM and jumped to, which is what `b64_overlay_load` does and what `examples/overlay` verifies at tiers 0 and 1. The C64 Ultimate's REU presents the same 1750 register interface and its DMA lands in the same RAM (DOOM C64U streams its level data into RAM this way every frame), so nothing about tier 2 changes the mechanism; it is unverified there only because the hardware has not arrived.
- **Files are the hardware's job.** On VICE the image is complete before the program starts. On the Ultimate, `b64_uci_load` fills a slot from storage; the heap allocator (`b64_heap_alloc`) gives it somewhere to land.

## What is not covered

GeoRAM (the engine uses the REU), the SuperCPU-compatible turbo registers at $D07A (the U64 registers are the documented interface), the 16-bit and interleaved sample modes, Ultimate Audio interrupts, the network target, and the REST API. The turbo detection does not try to tell 48 from 64 MHz; that is a hardware identity, readable through the control target's hardware info (GET_HWINFO, marked deprecated) or the REST API if a game ever needs it.
