#!/usr/bin/env python3
"""make check: everything the engine claims, proven in the emulator.

Static checks on the build, then VICE runs at both REU tiers driven through
the monitor (tools/b64vice.py): the boot check and its three failures, the
platform probe, the benchmark against budgets.txt, the overlay loader, the
cutscene (the park and the unpark change no pixel they should not), the
showcase (the object's lights alternate, the lamp is on the screen, the
light stays inside its radius, the park is exact), the scroller's worst
frame and the cutscene's worst tick.  Exit status 1 on any failure.

usage: b64check.py [--tier 8|16|both] [--only name,name] [--keep]
"""
import math
import os
import shutil
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from b64png import diff, px                      # noqa: E402
from b64vice import Vice, ViceError              # noqa: E402
import b64pack                                   # noqa: E402

OUT = "build/check"
X0, Y0 = 32, 35                                 # the display window inside VICE's 384x272 PAL screenshot
SET = (X0, Y0, X0 + 320, Y0 + 160)              # the 20 rows a cutscene set covers
TIERS = {8: (8192, "build/world8.reu"), 16: (16384, "build/world.reu")}


class Results:
    def __init__(self):
        self.lock = threading.Lock()
        self.rows, self.measures, self.failed = [], {}, False

    def check(self, name, ok, detail=""):
        with self.lock:
            self.rows.append((name, bool(ok), detail))
            if not ok:
                self.failed = True

    def measure(self, name, value):
        with self.lock:
            self.measures[name] = max(value, self.measures.get(name, 0))


def variation(frames, box=SET):
    """The pixels that differ anywhere among the frames: the shimmer, a flashing lamp."""
    out = set()
    for f in frames[1:]:
        out.update(diff(frames[0], f, box))
    return out


def grab(v, n, tag, every=1):
    out = []
    for i in range(n):
        v.frames(every)
        out.append(v.shot(f"{OUT}/{tag}-{i:02d}.png"))
    return out


# ---------------------------------------------------------------------------
def static_checks(R):
    for prg in ("cutscene", "showcase", "overlay", "bench", "scroll"):
        seg = {}
        for line in open(f"build/{prg}.map"):
            p = line.split()
            if len(p) == 5 and p[0] in ("CODE", "RODATA", "LOWRAM", "GAME") and "=" not in line:
                seg[p[0]] = int(p[3], 16)   # the segment list: name, start, end, size, align
        R.measure("engine.bytes", seg["CODE"] + seg["RODATA"])
        R.measure("lowram.bytes", seg["LOWRAM"])
    inc = dict(l.split("=") for l in open("build/slots.inc").read().replace(" ", "").splitlines() if "=" in l)
    size_kib, header, slots = b64pack.read_manifest("reu.manifest")
    for tier, (kib, image) in TIERS.items():
        d = open(image, "rb").read()
        R.check(f"image{tier}.size", len(d) == kib * 1024, f"{len(d)} bytes")
        ok = d[header:header + 4] == b"B64R" and d[header + 4] == int(inc["REU_FORMAT"])
        h = d[header + 5] | (d[header + 6] << 8)
        R.check(f"image{tier}.header", ok and h == int(inc["REU_LAYOUT_HASH"][1:], 16), f"hash ${h:04X} against slots.inc {inc['REU_LAYOUT_HASH']}")
        bad = []
        for i, (name, addr, path) in enumerate(slots):
            r = d[header + 16 + 16 * i: header + 32 + 16 * i]
            ln = os.path.getsize(path) if path != "-" else 0
            if int.from_bytes(r[0:3], "little") != addr or int.from_bytes(r[3:6], "little") != ln or int(inc[f"SLOT_{name}"][1:], 16) != addr:
                bad.append(name)
        R.check(f"image{tier}.slots", not bad, "descriptors, files and slots.inc disagree: " + ",".join(bad) if bad else f"{len(slots)} slots")
    # the baked lights agree with the object that declares them
    import b64light
    lights = b64light.read_object_lights("build/cruiser.b64o")
    nl = open("build/nightlight.bin", "rb").read()
    hdr = nl[1601:1601 + 6]
    want = 1 + sum(hdr[5] * len({c for c, f in L["pattern"] if c}) for L in lights)
    R.check("lights.file", hdr[0:1] == b"L" and hdr[1] == len(lights) and len(nl) == want * 2048,
            f"{len(lights)} lights, {len(nl) // 2048} states, {want} expected")


# ---------------------------------------------------------------------------
def boot_failures(R, port):
    cases = [("boot.no_reu", dict(reu=False), 2), ("boot.no_image", dict(reuimage=None), 7)]
    stale = f"{OUT}/stale8.reu"
    d = bytearray(open(TIERS[8][1], "rb").read())
    _, header, _ = b64pack.read_manifest("reu.manifest")
    d[header + 5] ^= 0xFF
    open(stale, "wb").write(d)
    cases.append(("boot.stale_image", dict(reuimage=stale), 8))
    for name, kw, want in cases:
        try:
            v = Vice("build/cutscene.prg", 8192, labels="build/cutscene.lbl", port=port, **kw)
            try:
                out = v.run_to("b64_boot_halt", timeout=20)
                a = int(out.split("A:")[1][:2], 16)
                R.check(name, a == want, f"halted with border code {a}, expected {want}")
            finally:
                v.close()
        except ViceError as e:
            R.check(name, False, str(e))
    os.unlink(stale)
    v = Vice("build/cutscene.prg", *TIERS[8], labels="build/cutscene.lbl", port=port)
    try:
        v.run_to("b64_cut_text", timeout=30)
        R.check("boot.good_image", True, "reached the scene")
    except ViceError as e:
        R.check("boot.good_image", False, str(e))
    finally:
        v.close()


def bench(R, tier, port):
    import b64bench
    kib, image = TIERS[tier]
    v = Vice("build/bench.prg", kib, image, "build/bench.lbl", port)
    try:
        v.run_to("test_done", timeout=120)
        b = v.mem(0xE000, 0x3C)
    finally:
        v.close()
    flags, mb = b[0x2A], b[0x2B]
    R.check(f"tier{tier}.platform", mb == tier and bool(flags & 1) and bool(flags & 2) == (tier == 16) and not flags & 0x1C,
            f"flags ${flags:02X}, REU {mb} MB")
    for i, test in enumerate(b64bench.TESTS):
        if test is not None:
            R.measure(f"bench.{test[0]}", int.from_bytes(b[3 * i:3 * i + 3], "little"))


def overlay(R, tier, port):
    kib, image = TIERS[tier]
    v = Vice("build/overlay.prg", kib, image, "build/overlay.lbl", port)
    try:
        v.run_to("test_done", timeout=60)
        b = v.mem(0xE000, 7)
    finally:
        v.close()
    R.check(f"tier{tier}.overlay", b[1] == 5 and b[2] == 4 and b[3] == 0xB2,
            f"{b[1]} calls, {b[2]} DMAs, last byte of the window ${b[3]:02X} (expected 5, 4, $B2)")
    R.measure("overlay.load_6k", int.from_bytes(b[4:7], "little"))


def cutscene(R, tier, port):
    kib, image = TIERS[tier]
    t = f"cut{tier}"
    v = Vice("build/cutscene.prg", kib, image, "build/cutscene.lbl", port)
    try:
        v.run_to("b64_cut_text")                 # the opening caption: the street is empty
        v.frames(20)
        empty = grab(v, 8, t + "-empty")
        v.run_to("b64_cut_text")                 # "OFFICER...": the car has stopped, the beacon is on
        v.frames(100)
        pre = grab(v, 12, t + "-pre")
        v.run_to("b64_obj_park")
        v.frames(3)
        post = grab(v, 8, t + "-post")
        v.run_to("op_end", timeout=120)          # unparked, driven off, the script ends
        v.frames(8)
        final = grab(v, 8, t + "-final")
    finally:
        v.close()
    mask = variation(pre) | variation(post)
    moved = max(len(diff(pre[-1], f, SET, mask)) for f in post)
    R.check(f"tier{tier}.cutscene.park", moved == 0, f"{moved} pixels changed outside the {len(mask)} that shimmer or flash")
    mask = variation(empty) | variation(final)
    left = max(len(diff(empty[-1], f, SET, mask)) for f in final)
    R.check(f"tier{tier}.cutscene.restore", left == 0, f"{left} pixels differ from the empty street after the unpark")


def showcase(R, tier, port):
    kib, image = TIERS[tier]
    t = f"show{tier}"
    v = Vice("build/showcase.prg", kib, image, "build/showcase.lbl", port)
    try:
        v.run_to("b64_obj_lights", timeout=120)  # lights on, the drive begins
        v.run_to("b64_cut_text")                 # the caption after the drive: the car has stopped
        v.frames(8)
        n = v.mem("obj_nlights")[0]
        rec = v.mem("obj_lights", 16 * n)
        ox, oy = v.word("obj_x"), v.mem("obj_y")[0]
        lit = grab(v, 32, t + "-lit")
        v.run_to("b64_obj_lights")               # lights off
        unlit = grab(v, 16, t + "-unlit")
        v.run_to("b64_obj_park")
        v.frames(3)
        post = grab(v, 8, t + "-post")
    finally:
        v.close()
    signed = lambda b: b - 256 if b > 127 else b
    lamps = [(ox + rec[16 * j] + 8, oy + signed(rec[16 * j + 1]) - 15 + 4, rec[16 * j + 2]) for j in range(n)]
    ref = unlit[-1]
    mask = variation(unlit[8:]) | variation(post)
    moved = max(len(diff(ref, f, SET, mask)) for f in post)
    R.check(f"tier{tier}.showcase.park", moved == 0, f"{moved} pixels changed outside the {len(mask)} that shimmer")

    def lamp_on(f, j):
        x, y, _ = lamps[j]
        c = px(f, x, y)
        solid = all(px(f, x + dx, y + dy) == c for dy in range(4) for dx in range(8))
        return c if solid and any(px(ref, x + dx, y + dy) != c for dy in range(4) for dx in range(8)) else None

    seq, colours, problems = [], {}, []
    for i, f in enumerate(lit):
        on = [j for j in range(n) if lamp_on(f, j)]
        if len(on) != 1:
            problems.append(f"frame {i}: {len(on)} lamps on screen")
            seq.append(None)
            continue
        seq.append(on[0])
        colours[on[0]] = lamp_on(f, on[0])
    runs = [len(list(g)) for _, g in __import__("itertools").groupby(seq)]
    R.check(f"tier{tier}.showcase.lamps", not problems and set(seq) == set(range(n)) and len(set(colours.values())) == n,
            "; ".join(problems[:3]) or f"each lamp drawn in its own colour at its declared offset")
    R.check(f"tier{tier}.showcase.pattern", all(r == 8 for r in runs[1:-1]) and max(runs) <= 8, f"runs of {runs} frames (8 expected)")
    for i in range(16):                         # the same strobe phase 16 frames apart differs only by the shimmer
        mask |= set(diff(lit[i], lit[i + 16], SET))
    worst_far, least = 0, 10 ** 9
    for i, f in enumerate(lit):
        if seq[i] is None:
            continue
        x, y, radius = lamps[seq[i]]
        changed = diff(f, ref, SET, mask)
        least = min(least, len(changed))
        reach = (radius + 1) * 8
        worst_far = max(worst_far, sum(1 for cx, cy in changed if math.hypot(cx - x - 4, cy - y - 2) > reach))
    R.check(f"tier{tier}.showcase.lit", least >= 200, f"at least {least} pixels relit in every frame")
    R.check(f"tier{tier}.showcase.local", worst_far == 0, f"{worst_far} relit pixels beyond the light's declared radius")


def scroller(R, port):
    """The autodrive scroller: its screen and colour RAM always equal a full
    redraw of the world at the camera, computed here from the world map and
    the tileset; how many frames go without a callback; its worst frame."""
    world = open("build/world.map", "rb").read()
    ts = open("build/bellamar_day.bin", "rb").read()
    mtchars = ts[0x800:0x1800]
    v = Vice("build/scroll-auto.prg", *TIERS[8], labels="build/scroll-auto.lbl", port=port)
    try:
        v.frames(50)                            # past the first full draw
        v.poke(0x3D, bytes(3))                  # bench_max: measure the scroll, not the start
        seq, wrong, checked, last = [], [], 0, -99
        for f in range(800):                    # twice round the autodrive square
            v.frames(1)
            seq.append(v.word("auto_t"))
            if f - last < 12 or v.mem(0x1B)[0]:  # about every 12 frames, when no work is pending
                continue
            last = f
            front = 0x4400 if v.mem(0x1A)[0] else 0x4000
            cx, cy = v.word(0x26), v.word(0x28)
            screen, colour = v.mem(front, 920), v.mem(0xD800, 920)
            for r in range(23):
                for c in range(40):
                    wx, wy = cx + c, cy + r
                    mid = world[(wy >> 2) * 2048 + (wx >> 2)]
                    code = mtchars[mid * 16 + (wy & 3) * 4 + (wx & 3)]
                    k = r * 40 + c
                    if screen[k] != code or (colour[k] & 15) != (code & 15):
                        wrong.append((f, r, c))
            checked += 1
        R.measure("scroll.worst_frame", int.from_bytes(v.mem(0x3D, 3), "little"))
    finally:
        v.close()
    R.check("scroll.picture", checked >= 10 and not wrong,
            f"{checked} frames compared with a full redraw of the world; {len(wrong)} cells wrong" + (f", first at frame, row, column {wrong[0]}" if wrong else ""))
    R.measure("scroll.frames_dropped", sum(1 for a, b in zip(seq, seq[1:]) if a == b))


def multiplexer(R, port):
    """The multiplexer harness (examples/mux): every hardware sprite move
    happens after its previous occupant's last line and before its new
    occupant's first, at normal density and overloaded; nothing is dropped
    at normal density and something is when lines carry more than seven;
    no sprite is ever drawn damaged; and its costs."""
    import b64muxtiming
    import b64irqcost
    from b64muxcheck import judge
    for phase, dense in (("normal", False), ("dense", True)):
        r = b64muxtiming.run("build/mux.prg", "build/mux.lbl", TIERS[8][1], TIERS[8][0], port, frames=40, skip=100, dense=dense)
        ok = not r["violations"] and (r["rejected"] == 0 if not dense else r["rejected"] > 0)
        R.check(f"mux.{phase}.timing", ok, f"{r['frames']} frames, {r['writes']} sprite moves, {len(r['violations'])} timing violations, "
                f"{r['rejected']} entries dropped" + (f"; first {r['violations'][0]}" if r["violations"] else ""))
    v = Vice("build/mux.prg", *TIERS[8], labels="build/mux.lbl", port=port)
    try:
        v.frames(100)
        damaged = 0
        for k in range(60):
            v.frames(1)
            rr = v.mem("res", 13)
            tb = rr[10] | (rr[11] << 8)
            rows = v.shot(f"{OUT}/mux-{k:02d}.png")
            best = min((judge(rows, t, False) for t in (tb - 1, tb - 2, tb)), key=lambda j: sum(1 for x in j.values() if x != "whole"))
            damaged += sum(1 for x in best.values() if x == "damaged")
    finally:
        v.close()
    R.check("mux.picture", damaged == 0, f"{damaged} sprites drawn damaged in 60 frames")
    per = sorted(b64irqcost.measure("build/mux.prg", "build/mux.lbl", frames=20, port=port))
    R.measure("mux.irq_frame", per[len(per) // 2])


def mux_instrument(R, port):
    """The multiplexer's hardware test (tools/b64muxhw.py) on VICE, both test
    builds: frozen snapshots judged entry by entry from the log clock, with
    no sprite cut short, none written late and the groups covering the
    list; and the log clock itself against the emulator's cycle counter.
    The 64-sprite build runs here at 1 MHz, beyond the tier that allows 64:
    the allocation must drop what the chain cannot write in time."""
    import b64muxhw
    for prg in ("build/mlog/mux.prg", "build/mlog/mux64.prg"):
        name = os.path.splitext(os.path.basename(prg))[0]
        t = b64muxhw.ViceTarget(prg, prg[:-4] + ".lbl", TIERS[8][1], TIERS[8][0], port)
        try:
            rs = b64muxhw.run(t, snapshots=3)
        finally:
            t.close()
        bad = [v for r in rs for v in r["violations"]]
        r = rs[-1]
        R.check(f"muxhw.{name}", not bad, f"{r['shown']} shown, {r['dropped']} dropped, {r['groups']} groups, "
                f"least slack {min(x['slack'] for x in rs)} cycles; {len(bad)} violations" + (f", first {bad[0]}" if bad else ""))
    t = b64muxhw.ViceTarget("build/mlog/mux64.prg", "build/mlog/mux64.lbl", TIERS[8][1], TIERS[8][0], port)
    try:
        d = b64muxhw.validate(t)
    finally:
        t.close()
    R.check("muxhw.clock", b64muxhw.valid(d), f"{len(d)} stamps against the emulator's clock, "
            f"emulator minus rebuilt {sorted(set(e for _, e in d))} cycles")


def cutscene_ticks(R, port):
    """The cost of a cutscene frame's main-loop work, from the emulator's own
    cycle counter in the plain build: from the callback to the end of the
    engine's frame work, interrupts included, over the drive and the hold."""
    import re
    v = Vice("build/cutscene.prg", *TIERS[8], labels="build/cutscene.lbl", port=port)
    try:
        v.run_to("b64_cut_text")
        v.frames(62)                            # the drive has begun
        cb = v.addr("call_cb")
        cyc = lambda out: int(re.findall(r"(\d+)\s*\n\(C:", out)[-1])
        ticks = []
        for _ in range(160):
            a = cyc(v.run_to(cb))
            ticks.append(cyc(v.run_to(cb - 3)) - a)     # the jmp back to the loop, just before call_cb
    finally:
        v.close()
    ticks.sort()
    R.measure("cutscene.tick_median", ticks[len(ticks) // 2])
    R.measure("cutscene.tick_worst", ticks[-1])


def probe_block(R, port):
    """The profile build links and fills its block; its numbers are upper bounds and are not budgeted."""
    v = Vice("build/prof/cutscene.prg", *TIERS[8], labels="build/prof/cutscene.lbl", port=port)
    try:
        v.run_to("b64_cut_text")
        v.frames(50)
        b = v.mem(0xF800, 18)
    finally:
        v.close()
    R.check("probe.block", b[:4] == b"B64P" and int.from_bytes(b[15:18], "little") > 0, f"magic {bytes(b[:4])!r}, worst tick {int.from_bytes(b[15:18], 'little')}")
    # the scroller runs no scripts: its profile must show no VM samples and
    # no opcodes, and the probe must not change how often the frame holds
    import b64probe
    v = Vice("build/prof/scroll-auto.prg", *TIERS[8], labels="build/prof/scroll-auto.lbl", port=port)
    try:
        v.frames(100)
        seq = []
        for _ in range(401):
            v.frames(1)
            seq.append(v.word("auto_t"))
        blk = v.mem(0xF800, 2048)
    finally:
        v.close()
    pr = b64probe.decode(blk, b64probe.read_labels("build/prof/scroll-auto.lbl"), {})
    stray = sum(1 for sm in pr["samples"] if sm["thread"] is not None)
    dropped = sum(1 for a, b in zip(seq, seq[1:]) if a == b)
    R.check("probe.clean", not pr["opcodes"] and stray == 0 and dropped <= 60,
            f"{len(pr['samples'])} samples, {stray} claiming a VM thread, {sum(pr['opcodes'].values())} opcodes counted, {dropped} of 400 frames dropped")


# ---------------------------------------------------------------------------
def main():
    args = sys.argv[1:]
    tiers = [8, 16]
    if "--tier" in args and args[args.index("--tier") + 1] != "both":
        tiers = [int(args[args.index("--tier") + 1])]
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else None
    want = lambda n: only is None or n in only
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT, exist_ok=True)
    R = Results()
    t0 = time.time()
    if want("static"):
        static_checks(R)

    def guarded(name, fn, *a):
        try:
            fn(R, *a)
        except Exception as e:                  # a hung emulator or a missing label is a failure, not a crash
            R.check(name, False, f"{type(e).__name__}: {e}")

    def tier_suite(tier, port):
        for name, fn in (("bench", bench), ("overlay", overlay), ("cutscene", cutscene), ("showcase", showcase)):
            if want(name):
                guarded(f"tier{tier}.{name}", fn, tier, port)

    def singles(port):
        for name, fn in (("boot", boot_failures), ("scroller", scroller), ("ticks", cutscene_ticks), ("probe", probe_block), ("mux", multiplexer), ("muxhw", mux_instrument)):
            if want(name):
                guarded(name, fn, port)

    threads = [threading.Thread(target=tier_suite, args=(t, 6520 + i)) for i, t in enumerate(tiers)]
    threads.append(threading.Thread(target=singles, args=(6530,)))
    for th in threads:
        th.start()
    for th in threads:
        th.join()

    # budgets: every budget needs a measurement and every measurement a budget
    budgets = {}
    for line in open("budgets.txt"):
        p = line.split("#")[0].split()
        if len(p) >= 2:
            budgets[p[0]] = int(p[1])
    for name, limit in budgets.items():
        if name in R.measures:
            R.check(f"budget.{name}", R.measures[name] <= limit, f"{R.measures[name]} against {limit}")
        elif only is None:
            R.check(f"budget.{name}", False, "nothing measured it")
    for name in R.measures:
        if name not in budgets:
            R.check(f"budget.{name}", False, f"{R.measures[name]} measured, no line in budgets.txt")

    width = max(len(n) for n, _, _ in R.rows)
    for name, ok, detail in sorted(R.rows):
        print(f"{'ok  ' if ok else 'FAIL'}  {name:<{width}}  {detail}")
    bad = [n for n, ok, _ in R.rows if not ok]
    print(f"\n{len(R.rows) - len(bad)} passed, {len(bad)} failed in {time.time() - t0:.0f}s" + (f"; frames kept in {OUT}" if bad else ""))
    if not bad and "--keep" not in args:
        shutil.rmtree(OUT, ignore_errors=True)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
