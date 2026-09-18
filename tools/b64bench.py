#!/usr/bin/env python3
"""Run build/bench.prg in VICE and print the measured cycle counts.

The benchmark (examples/bench/main.s) times REU fetches of five sizes from
the border and from inside the display, one VM tick of three scripts, and
64 iterations of the cutscene drive step written in assembly.  Results are
24-bit cycle counts at $E000, read through the monitor when the program
reaches test_done.  `make check` holds the same numbers to budgets.txt.

usage: b64bench.py [<image.reu> [<reusize KiB>]]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from b64vice import Vice                         # noqa: E402

# (budget key, what it is, units it covers)
TESTS = [
    ("fetch_64_border", "fetch 64 B, border", 64), ("fetch_256_border", "fetch 256 B, border", 256),
    ("fetch_1k_border", "fetch 1 KB, border", 1024), ("fetch_4k_border", "fetch 4 KB, border", 4096),
    ("fetch_8k_border", "fetch 8 KB, border", 8192),
    ("fetch_64_display", "fetch 64 B, display", 64), ("fetch_256_display", "fetch 256 B, display", 256),
    ("fetch_1k_display", "fetch 1 KB, display", 1024), ("fetch_4k_display", "fetch 4 KB, display", 4096),
    ("fetch_8k_display", "fetch 8 KB, display", 8192),
    ("vm_64_loop", "VM tick, 64 x LOOP", 64), ("vm_drive_71", "VM tick, drive body, 71 ops (4 steps)", 71),
    ("asm_drive_64", "asm, 64 x drive step", 64), ("vm_add_65", "VM tick, 63 x ADD + YIELD + JMP", 65),
    None,                                       # 14: platform flags, not a time
    ("scroll_right", "scroll prepare, crossing right", 1), ("scroll_down", "scroll prepare, crossing down", 1),
    ("scroll_diag", "scroll prepare, crossing diagonally", 1),
    ("mux_first", "multiplexer, 32 sprites, first list", 32), ("mux_next", "multiplexer, 32 sprites, next frame", 32),
]


def main():
    reu = sys.argv[1] if len(sys.argv) > 1 else "build/world.reu"
    size = sys.argv[2] if len(sys.argv) > 2 else "16384"
    v = Vice("build/bench.prg", int(size), reu, "build/bench.lbl")
    try:
        v.run_to("test_done", timeout=120)
        b = v.mem(0xE000, 0x3C)
    finally:
        v.close()
    f, mb = b[0x2A], b[0x2B]
    names = [n for bit, n in ((1, "reu"), (2, "reu16"), (4, "turbo"), (8, "audio"), (16, "uci")) if f & bit]
    print(f"platform: {' '.join(names) or 'stock, no REU'}; REU {mb} MB")
    print(f"{'test':40s} {'cycles':>8s} {'per unit':>9s}")
    for i, test in enumerate(TESTS):
        if test is None:
            continue
        _, n, unit = test
        val = int.from_bytes(b[3 * i:3 * i + 3], "little")
        per = "%.1f/B" % (val / unit) if "fetch" in n else "" if unit == 1 else "%.0f/op" % (val / unit)
        print(f"{n:40s} {val:8d} {per:>9s}")


if __name__ == "__main__":
    main()
