#!/usr/bin/env python3
"""Measure the scroller from the emulator's own cycle counter.

Runs the autodrive scroller and records, for every frame, the cycles from
the entry of b64_scroll_prepare to the engine's next step (interrupts
included, which is what the frame pays) and the cycles scr_vblank takes in
the vertical blank.  Crossing frames are told apart by scr_pending.

usage: b64scrollcost.py [frames]      (after make build/scroll-auto.prg)
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from b64vice import Vice                         # noqa: E402


def cyc(out):
    return int(re.findall(r"(\d+)\s*\n\(C:", out)[-1])


def measure(frames=300, port=6550, image=("build/world8.reu", 8192)):
    v = Vice("build/scroll-auto.prg", image[1], image[0], "build/scroll-auto.lbl", port)
    try:
        v.frames(60)                            # past the first full draw
        L = v.labels
        after_prepare = L["b64_scroll_prepare_ret"] if "b64_scroll_prepare_ret" in L else None
        prep, vbl = [], []
        for _ in range(frames):
            a = cyc(v.run_to("b64_scroll_prepare"))
            b = cyc(v.run_to("b64_bench_end"))
            pend = v.mem(0x1B)[0]               # scr_pending: 3 = a crossing was prepared
            c = cyc(v.run_to("scr_vblank"))
            d = cyc(v.run_to("hud_flush"))      # scr_vblank's work ends where it flushes the HUD
            prep.append((b - a, pend))
            vbl.append((d - c, pend))
    finally:
        v.close()
    return prep, vbl


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    prep, vbl = measure(n)
    cross = [c for c, p in prep if p == 3]
    still = [c for c, p in prep if p != 3]
    vcross = [c for c, p in vbl if p == 3]
    print(f"frames {len(prep)}, crossings {len(cross)}")
    if cross:
        cross.sort()
        print(f"prepare on a crossing: median {cross[len(cross) // 2]}, worst {cross[-1]}, best {cross[0]}")
    if still:
        print(f"prepare without a crossing: worst {max(still)}")
    if vcross:
        vcross.sort()
        print(f"vertical blank after a crossing: median {vcross[len(vcross) // 2]}, worst {vcross[-1]}")


if __name__ == "__main__":
    main()
