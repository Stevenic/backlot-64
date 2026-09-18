#!/usr/bin/env python3
"""Cycles spent in interrupts per frame, from the emulator's counter.

Breaks at the handler's entry (irq) and its RTI (irq_rti) and sums the
difference plus the 13 cycles of the interrupt sequence and the RTI.
usage: b64irqcost.py <prg> <labels> [frames]
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from b64vice import Vice                         # noqa: E402


def cycles(v):
    return int(re.search(r"\.;[0-9a-f]{4} .*?\d+ +\d+ +(\d+)\s*\n", v.cmd("r")).group(1))


def measure(prg, lbl, frames=30, skip=150, port=6630, image=("build/world8.reu", 8192)):
    v = Vice(prg, image[1], image[0], lbl, port)
    try:
        v.frames(skip)
        a, b = v.addr("irq"), v.addr("irq_rti")
        na = int(re.search(r"BREAK: (\d+)", v.cmd(f"break {a:04x}")).group(1))
        nb = int(re.search(r"BREAK: (\d+)", v.cmd(f"break {b:04x}")).group(1))
        per, cur, f0, start = [], 0, v.mem(0x10)[0], None
        while len(per) < frames:
            v.cmd("x", 20)
            m = re.search(r"\.;([0-9a-f]{4})", v.cmd("r"))
            pc = int(m.group(1), 16)
            c = cycles(v)
            if pc == a:
                start = c
            elif pc == b and start is not None:
                cur += c - start + 13
                start = None
                f = v.mem(0x10)[0]
                if f != f0:
                    per.append(cur)
                    cur, f0 = 0, f
        v.cmd(f"del {na:x}")
        v.cmd(f"del {nb:x}")
    finally:
        v.close()
    return per


if __name__ == "__main__":
    per = measure(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 30)
    per.sort()
    print(f"interrupt cycles per frame: median {per[len(per) // 2]}, worst {per[-1]}, best {per[0]}")
