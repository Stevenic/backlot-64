#!/usr/bin/env python3
"""Check the multiplexer's timing in VICE, frame by frame.

A hardware sprite may be moved to a new occupant only after its previous
occupant's last line has been drawn, and must be moved before the new
occupant's first line.  This breaks at every generated routine (one per
hardware sprite, mux_rout + 64h) and records the raster line, the sprite's
Y before the write (its previous occupant) and the Y it is given.  Group 0
runs in the vertical blank, where every sprite is finished.
"""
import re
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from b64vice import Vice                         # noqa: E402



def regs(v):
    m = re.search(r"\.;([0-9a-f]{4}) ([0-9a-f]{2}) ([0-9a-f]{2}) ([0-9a-f]{2}) \S+ \S+ \S+ \S+\s+(\d+) +(\d+)", v.cmd("r"))
    return int(m.group(1), 16), int(m.group(3), 16), int(m.group(5)), int(m.group(6))


# The VIC-II's rules (Bauer, "The MOS 6567/6569 video controller", 3.8
# and the 6569 timing diagram): a sprite's Y is compared with the raster in
# cycle 55 of each line, and a match starts the sprite, shown on the next
# 21 lines, so a sprite with Y = y is shown on lines y+1 .. y+21.  Its
# pointer is fetched in the same line: sprite h's p-access is in cycle
# 58 + 2h for h = 0..2, and in cycles 1, 3, 5, 7, 9 of the next line for
# h = 3..7.  A generated routine stores Y about 12 cycles after it starts
# and the pointer about 36 cycles after.
Y_AT, PTR_AT = 12, 36


def ptr_deadline(h, y):
    return y * 63 + 58 + 2 * h if h <= 2 else (y + 1) * 63 + 2 * h - 5
def run(prg, lbl, image, reusize, port, frames=60, skip=100, dense=False):
    v = Vice(prg, reusize, image, lbl, port)
    out = {"frames": 0, "writes": 0, "violations": [], "rejected": 0, "shown": 0}
    try:
        v.frames(skip)
        while dense and not v.mem(v.addr("res") + 12)[0]:
            v.frames(10)                        # until the harness says its lines are overloaded
        if dense:
            v.frames(4)
        rout = v.addr("mux_rout")
        nums = [int(re.search(r"BREAK: (\d+)", v.cmd(f"break {rout + 64 * h:04x}")).group(1)) for h in range(8)]
        fw = int(re.search(r"(?:WATCH): (\d+)", v.cmd("watch store 0010")).group(1))
        by = None
        while out["frames"] < frames:
            v.cmd("x", 20)
            pc, x, line, cyc = regs(v)
            if pc not in range(rout, rout + 512):  # the frame counter: a new frame
                out["frames"] += 1
                out["rejected"] += v.mem("spr_rejected")[0]
                out["shown"] += v.mem(0x42)[0]
                by = None
                continue
            h = (pc - rout) // 64
            if by is None:
                by = v.mem("mux_b_y", 64)
                acc = v.mem("mux_acc", 64)
            old_y = v.mem(0xD001 + 2 * h)[0]
            new_y = by[acc[x]]
            out["writes"] += 1
            if line >= 250:
                continue                        # group 0, in the blank: everything is finished
            if old_y <= line <= old_y + 21:
                out["violations"].append(("cut short", out["frames"], h, line, cyc, old_y, new_y))
            start = line * 63 + cyc
            if start + Y_AT > new_y * 63 + 55 or start + PTR_AT > ptr_deadline(h, new_y):
                out["violations"].append(("late", out["frames"], h, line, cyc, old_y, new_y))
        for n in nums + [fw]:
            v.cmd(f"del {n:x}")
    finally:
        v.close()
    return out


if __name__ == "__main__":
    r = run("build/mux.prg", "build/mux.lbl", "build/world8.reu", 8192, 6620, frames=int(sys.argv[1]) if len(sys.argv) > 1 else 60)
    print(r["frames"], "frames,", r["writes"], "sprite moves,", len(r["violations"]), "timing violations,", r["rejected"], "entries dropped,", r["shown"], "shown")
    for viol in r["violations"][:10]:
        print("  ", viol)
