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


def traffic(R, port):
    """The traffic demo (examples/traffic).  Driving itself for 3,000 frames,
    sampled every 10: no two cars' bodies overlap, the band table matches
    the cars' positions, no band holds more than seven, the multiplexer
    drops nothing, there is traffic, and the player's car gets somewhere.
    Driven by hand through the test byte: holding up turns it north at the
    next crossing, it runs at two pixels a frame, and pulling back holds it.
    And the frames it loses at 1 MHz."""
    P, BOT = 24, 28
    def box(h, x, y):
        return (x - 12, y - 3, x + 12, y + 3) if h in (1, 3) else (x - 6, y - 7, x + 6, y + 8)
    def cars(v):
        m = {n: v.mem(n, 25) for n in ("c_hd", "c_xl", "c_xh", "c_yl", "c_yh")}
        return {i: (m["c_hd"][i], m["c_xl"][i] | m["c_xh"][i] << 8, m["c_yl"][i] | m["c_yh"][i] << 8)
                for i in range(25) if m["c_hd"][i] != 255}
    v = Vice("build/traffic-auto.prg", *TIERS[8], labels="build/traffic-auto.lbl", port=port)
    try:
        v.frames(50)
        t0 = v.word("tick")
        overlaps = bad_bands = worst = 0
        lives, travel = [], 0
        last = cars(v)[P]
        for _ in range(300):
            v.frames(10)
            cs = cars(v)
            ids = sorted(cs)
            for a in range(len(ids)):
                for b in range(a + 1, len(ids)):
                    A, B = box(*cs[ids[a]]), box(*cs[ids[b]])
                    overlaps += A[0] < B[2] and B[0] < A[2] and A[1] < B[3] and B[1] < A[3]
            exp = [0] * 64
            for i, (h, x, y) in cs.items():
                if i == P:
                    continue
                b, b1 = ((y - 10) >> 3) & 63, ((y + BOT) >> 3) & 63
                while True:
                    exp[b] += 1
                    if b == b1:
                        break
                    b = (b + 1) & 63
            bad_bands += exp != list(v.mem("band", 64))
            worst = max(worst, max(exp))
            lives.append(v.mem("live")[0])
            h, x, y = cs[P]
            travel += abs(x - last[1]) + abs(y - last[2])
            last = cs[P]
        lost = 3000 - (v.word("tick") - t0)
        dropped = v.word("dropped")
    finally:
        v.close()
    mean = sum(lives) / len(lives)
    R.check("traffic.auto", not overlaps and not bad_bands and worst <= 7 and dropped == 0 and mean >= 8 and travel >= 1000,
            f"3,000 frames: {overlaps} overlapping pairs, band table wrong {bad_bands} times, busiest band {worst}, "
            f"{dropped} sprites dropped, {mean:.1f} cars live on average, the player drove {travel} pixels")
    R.measure("traffic.frames_lost", lost)
    v = Vice("build/traffic.prg", *TIERS[8], labels="build/traffic.lbl", port=port)
    try:
        v.frames(30)
        v.poke(v.addr("joy_test"), b"\x01")
        turned = None
        for f in range(400):
            v.frames(1)
            if cars(v)[P][0] == 0:
                turned = f + 1
                break
        a = cars(v)[P]
        v.frames(10)
        b = cars(v)[P]
        speed = (abs(b[1] - a[1]) + abs(b[2] - a[2])) / 10
        v.poke(v.addr("joy_test"), b"\x02")
        v.frames(2)
        a = cars(v)[P]
        v.frames(30)
        held = cars(v)[P] == a
    finally:
        v.close()
    R.check("traffic.by_hand", turned is not None and speed >= 1.9 and held,
            f"holding up turned it north after {turned} frames; {speed} pixels a frame; pulling back held it: {held}")


def physics(R, port):
    """The physics module (modules/physics) in examples/physics playing its
    tape: walk to a sedan, get in, drive into the sports car and the truck,
    brake, reverse, turn, drift, stop, get out, walk.  Every frame, no
    body's box has a corner in a wall, judged here from the world map and
    the tileset's properties, not from the module's cache.  The first ram
    conserves momentum along the axis it happened on, to within the engine's
    push that frame.  The abandoned car comes to rest and sleeps.  Two runs
    of the tape end in the same state.  And the step's cost and the frames
    it loses."""
    import re
    world = open("build/world.map", "rb").read()
    props = open("build/bellamar_day.bin", "rb").read()[0x2800:0x2900]
    syms = {m.group(1): int(m.group(2), 16)
            for f in ("build/physics_syms.inc", "build/collision_syms.inc")
            for m in re.finditer(r"^(\w+)\s*=\s*\$([0-9A-Fa-f]+)", open(f).read(), re.M)}
    HW, MASS = [3, 7, 7, 9, 4], [1, 8, 6, 15, 3]
    names = ("pb_mov", "pb_cls", "pb_xf", "pb_xl", "pb_xh", "pb_yf", "pb_yl", "pb_yh",
             "pb_vxl", "pb_vxh", "pb_vyl", "pb_vyh", "pb_st", "pb_hit")

    def s16(lo, hi):
        x = lo | hi << 8
        return x - 65536 if x & 0x8000 else x

    def bodies(v):
        m = {n: v.mem(syms[n], 12) for n in names}
        return {i: {"cls": m["pb_cls"][i], "x": m["pb_xl"][i] | m["pb_xh"][i] << 8, "y": m["pb_yl"][i] | m["pb_yh"][i] << 8,
                    "fx": m["pb_xf"][i], "fy": m["pb_yf"][i],
                    "vx": s16(m["pb_vxl"][i], m["pb_vxh"][i]), "vy": s16(m["pb_vyl"][i], m["pb_vyh"][i]),
                    "st": m["pb_st"][i], "hit": m["pb_hit"][i]} for i in range(12) if m["pb_mov"][i]}

    def in_wall(b):
        h = HW[b["cls"]]
        for cx in (b["x"] - h, b["x"] + h):
            for cy in (b["y"] - h, b["y"] + h):
                if props[world[((cy >> 5) << 11) | (cx >> 5)]] & 0xC0:
                    return True
        return False

    finals, walls, ram, prev = [], 0, None, None
    shots_in_wall, fired, stops, bad_stops = 0, 0, 0, 0
    throws_in_wall, blasts, reached, responded, asleep = 0, 0, 0, 0, False

    def solid(x, y):
        return props[world[((y >> 5) << 11) | (x >> 5)]] & 0x80
    for run in range(3):
        v = Vice("build/physics-auto.prg", *TIERS[8], labels="build/physics-auto.lbl", port=port)
        try:
            v.frames(10)                        # past the start: the module loaded, the tick counting
            t0 = v.word("tick")
            if run == 2:                                                 # the third run times every step
                costs = []
                for _ in range(800):
                    a = int(re.findall(r"(\d+)\s*\n\(C:", v.run_to(syms["phys_step"]))[-1])
                    c = int(re.findall(r"(\d+)\s*\n\(C:", v.run_to("after_step"))[-1])
                    costs.append(c - a)
                continue
            for f in range(800):
                v.frames(1)
                bs = bodies(v)
                walls += sum(1 for b in bs.values() if in_wall(b))
                on = v.mem(syms["sh_on"], 8)
                sx = [a | b << 8 for a, b in zip(v.mem(syms["sh_xl"], 8), v.mem(syms["sh_xh"], 8))]
                sy = [a | b << 8 for a, b in zip(v.mem(syms["sh_yl"], 8), v.mem(syms["sh_yh"], 8))]
                fired += sum(1 for k in range(8) if on[k] == 39)      # fired this frame (40, less one step)
                shots_in_wall += sum(1 for k in range(8) if on[k] and solid(sx[k], sy[k]))
                ton = v.mem(syms["th_on"], 4)
                tx = [a | b << 8 for a, b in zip(v.mem(syms["th_xl"], 4), v.mem(syms["th_xh"], 4))]
                ty = [a | b << 8 for a, b in zip(v.mem(syms["th_yl"], 4), v.mem(syms["th_yh"], 4))]
                throws_in_wall += sum(1 for k in range(4) if ton[k] and solid(tx[k], ty[k]))
                fxt, fxk = v.mem(syms["fx_t"])[0], v.mem(syms["fx_k"])[0]
                if fxt == 12 and fxk == 2:                               # a grenade went off this frame
                    blasts += 1
                    fx, fy = v.word(syms["fx_x"]), v.word(syms["fx_y"])
                    for b in bs.values():                                # each body in reach shows it
                        if abs(b["x"] - fx) < 40 and abs(b["y"] - fy) < 40:
                            reached += 1
                            responded += bool(b["hit"] == 32 and (b["cls"] != 0 or b["st"] & 2))
                if f == 530:
                    asleep = any(b["cls"] == 1 and b["st"] & 0x80 for b in bs.values())
                if fxt == 6 and fxk == 1:                                # a shot stopped this frame
                    stops += 1
                    bad_stops += bool(solid(v.word(syms["fx_x"]), v.word(syms["fx_y"])))
                if ram is None and prev:
                    car = [i for i, b in bs.items() if b["cls"] == 2 and b["hit"]]
                    if car:
                        j = car[0]
                        i = min((k for k in bs if bs[k]["cls"] == 1), default=None)
                        if i is not None and i in prev and j in prev:
                            axis = "vx" if abs(prev[i]["vx"] - prev[j]["vx"]) >= abs(prev[i]["vy"] - prev[j]["vy"]) else "vy"
                            p0 = MASS[1] * prev[i][axis] + MASS[2] * prev[j][axis]
                            p1 = MASS[1] * bs[i][axis] + MASS[2] * bs[j][axis]
                            ram = (axis, p0, p1)
                prev = bs
            if not run:
                lost = 800 - (v.word("tick") - t0)
            finals.append(bodies(v))

        finally:
            v.close()
    R.check("physics.walls", walls == 0, f"800 frames of the tape: {walls} body-frames with a corner in a wall")
    R.check("collision.thrown", blasts > 0 and reached > 0 and responded == reached and throws_in_wall == 0,
            f"{blasts} blasts reaching {reached} bodies, {responded} of them pushed and marked (and down, "
            f"on foot); {throws_in_wall} thrown-frames inside a wall")
    R.check("collision.shots", fired > 0 and stops > 0 and shots_in_wall == 0 and bad_stops == 0,
            f"{fired} shots fired, {stops} stopped; {shots_in_wall} shot-frames inside a wall, "
            f"{bad_stops} stopping points inside one")
    # the sedan's engine pushes it that frame too: its mass (8) x its acceleration (8/256 px/frame) = 64;
    # the shares of the change are 1/128ths of a table's rounding: allow 64 more
    R.check("physics.momentum", ram is not None and abs(ram[2] - ram[1] - 64) <= 64,
            f"the first ram, along {ram[0] if ram else '?'}: momentum {ram[1] if ram else '?'} before and "
            f"{ram[2] if ram else '?'} after, the engine's push 64 (mass x 1/256 pixel a frame)")
    R.check("physics.rest", asleep, "the abandoned sedan came to rest and sleeps (frame 530)" if asleep
            else "the abandoned sedan is still awake at frame 530")
    costs.sort()
    R.check("physics.repeat", finals[0] == finals[1], "two runs of the tape end in the same state" if finals[0] == finals[1]
            else "two runs of the tape end in different states")
    R.measure("physics.step_median", costs[len(costs) // 2])
    R.measure("physics.step_worst", costs[-1])
    R.measure("physics.frames_lost", lost)


def module_scene(port, prg, frames, swaps, extra=None, col=False):
    """Run examples/physics built for a scene that swaps physics modules
    (the coast, the sky), four times: once a frame at a time, reading every
    body each frame; again for the final state; once stopped at each swap
    (the body tables before and after the fetch, and the module in place);
    and once timing every step through the jump table at $6009, so either
    module is timed; with col, the collision step too (shot_step to the
    example's after_shots).  extra(v, syms), if given, reads more each
    frame of the first run.  Returns what the judges need."""
    import re
    syms = {m.group(1): int(m.group(2), 16)
            for f in ("build/physics_syms.inc", "build/collision_syms.inc")
            for m in re.finditer(r"^(\w+)\s*=\s*\$([0-9A-Fa-f]+)", open(f).read(), re.M)}
    bins = [open(f"build/{n}.bin", "rb").read() for n in ("physics", "water", "air")]
    PB, PB_END = syms["pb_mov"], syms["phys_tiles"] + 3
    names = ("pb_mov", "pb_cls", "pb_xl", "pb_xh", "pb_yl", "pb_yh", "pb_vtl", "pb_vth", "pb_st", "pb_hit",
             "pb_zh", "pb_vzl", "pb_vzh", "pb_ang")

    def bodies(v):
        m = {n: v.mem(syms[n], 12) for n in names}
        return {i: {"mov": m["pb_mov"][i], "cls": m["pb_cls"][i],
                    "x": m["pb_xl"][i] | m["pb_xh"][i] << 8, "y": m["pb_yl"][i] | m["pb_yh"][i] << 8,
                    "vt": int.from_bytes(bytes([m["pb_vtl"][i], m["pb_vth"][i]]), "little", signed=True),
                    "vz": int.from_bytes(bytes([m["pb_vzl"][i], m["pb_vzh"][i]]), "little", signed=True),
                    "z": m["pb_zh"][i], "st": m["pb_st"][i], "hit": m["pb_hit"][i], "ang": m["pb_ang"][i]}
                for i in range(12) if m["pb_mov"][i]}

    out = {"frames": [], "finals": [], "swaps": [], "costs": [], "col_costs": [], "lost": 0, "end": None}
    for run in range(4):
        lbl = prg[:-4] + ".lbl"
        v = Vice(prg, *TIERS[8], labels=lbl, port=port)
        try:
            v.frames(10)
            t0 = v.word("tick")
            if run == 2:
                for _ in range(swaps):
                    v.run_to("use_module")
                    before = v.mem(PB, PB_END - PB)
                    v.run_to("swapped")
                    after = v.mem(PB, PB_END - PB)
                    mod = v.mem("module")[0]
                    out["swaps"].append((mod, before == after, v.mem(0x6000, len(bins[mod])) == bins[mod]))
                continue
            if run == 3:
                for _ in range(frames):
                    a = int(re.findall(r"(\d+)\s*\n\(C:", v.run_to(0x6009))[-1])
                    c = int(re.findall(r"(\d+)\s*\n\(C:", v.run_to("after_step"))[-1])
                    out["costs"].append(c - a)
                    if col:
                        c = int(re.findall(r"(\d+)\s*\n\(C:", v.run_to(syms["shot_step"]))[-1])
                        e = int(re.findall(r"(\d+)\s*\n\(C:", v.run_to("after_shots"))[-1])
                        out["col_costs"].append(e - c)
                out["costs"].sort()
                out["col_costs"].sort()
                continue
            for f in range(frames):
                v.frames(1)
                if not run:
                    out["frames"].append((v.mem("player")[0], bodies(v), extra(v, syms) if extra else None))
            if not run:
                out["lost"] = frames - (v.word("tick") - t0)
                out["end"] = (v.mem("player")[0], v.mem("module")[0])
            out["finals"].append(bodies(v))
        finally:
            v.close()
    return out


def scene_map():
    """The world map, the tileset's properties and heights (storeys of 8
    pixels), and a test of a body's box against what its mover counts as a
    wall: land and marsh for a boat, land for an airboat; a solid metatile
    standing higher than it for an aircraft; walls and water for feet and
    wheels."""
    world = open("build/world.map", "rb").read()
    ts = open("build/bellamar_day.bin", "rb").read()
    props, heights = ts[0x2800:0x2900], ts[0x2900:0x2A00]
    HW = [3, 7, 7, 9, 4, 7, 9, 4, 8, 8, 7]

    def cells(b):
        h = HW[b["cls"]]
        for cx in (b["x"] - h, b["x"] + h):
            for cy in (b["y"] - h, b["y"] + h):
                yield world[((cy >> 5) << 11) | (cx >> 5)]

    def in_wall(b):
        for m in cells(b):
            p = props[m]
            if b["mov"] == 3:                    # a boat: land and marsh (the shallow bit)
                bad = not p & 0x40 or p & 0x01
            elif b["mov"] == 7:                  # an airboat: land
                bad = not p & 0x40
            elif b["mov"] in (4, 6):
                bad = p & 0x80 and heights[m] * 8 > b["z"]
            else:
                bad = p & 0xC0
            if bad:
                return True
        return False

    def over_building(b):
        return any(props[m] & 0x80 for m in cells(b))

    return in_wall, over_building, props, heights, world


def boats(R, port):
    """The water module in examples/physics built at the coast (-D COAST),
    playing its tape: walk to the speedboat and get in, which swaps the
    water module in over the ground module; ram the launch, turn away on the
    propeller's wash, slide through a turn, run into the beach, get out on
    the sand, which swaps the ground module back, and walk.  Every frame, no
    body's box has a corner in what its mover counts as a wall, judged from
    the world map and the tileset.  At each swap the body tables are the
    same before and after, and the module in place is the one asked for,
    byte for byte.  The boat slides and hits the shore; the launch is
    rammed; the player ends on land with the ground module in.  Two runs
    end alike.  And the step's cost and the frames lost."""
    in_wall, _, _, _, _ = scene_map()
    d = module_scene(port, "build/boats-auto.prg", 700, 2)
    walls = sum(1 for _, bs, _ in d["frames"] for b in bs.values() if in_wall(b))
    boat = [bs[p] for p, bs, _ in d["frames"] if p in bs and bs[p]["mov"] == 3]
    slide = max((abs(b["vt"]) for b in boat), default=0)
    spray = sum(1 for b in boat if b["st"] & 1)
    shore = sum(1 for b in boat if b["st"] & 8)
    rammed = any(b["cls"] == 6 and b["hit"] for _, bs, _ in d["frames"] for b in bs.values())
    p, mod = d["end"]
    last = d["finals"][0][p]
    landed = (last["mov"], mod, in_wall(last)) == (1, 0, False)
    sw = d["swaps"]
    R.check("boats.walls", walls == 0, f"700 frames of the tape: {walls} body-frames with a corner in its mover's walls "
            "(land for a boat, walls and water for feet and wheels)")
    R.check("boats.swap", len(sw) == 2 and all(s[1] and s[2] for s in sw) and [s[0] for s in sw] == [1, 0],
            f"{len(sw)} swaps ({', '.join(('water', 'air')[s[0] - 1] if s[0] else 'ground' for s in sw)}): body tables "
            f"{'unchanged' if all(s[1] for s in sw) else 'CHANGED'} across each; the module in place "
            f"{'matches' if all(s[2] for s in sw) else 'DOES NOT match'} its binary")
    R.check("boats.slide", slide > 64 and spray > 0, f"the speedboat's sideways speed peaked at {slide}/256 pixel a frame, "
            f"spray for {spray} frames")
    R.check("boats.shore", shore > 0, f"the speedboat met the shore in {shore} frames")
    R.check("boats.ram", rammed, "the launch was rammed" if rammed else "the launch was never hit")
    R.check("boats.landed", landed, "the player ends on foot, on land, with the ground module in" if landed
            else f"the player ends as mover {last['mov']} with module {mod}")
    R.check("boats.repeat", d["finals"][0] == d["finals"][1], "two runs of the tape end in the same state"
            if d["finals"][0] == d["finals"][1] else "two runs of the tape end in different states")
    R.measure("boats.step_median", d["costs"][len(d["costs"]) // 2])
    R.measure("boats.step_worst", d["costs"][-1])
    R.measure("boats.frames_lost", d["lost"])


def sky(R, port):
    """The air module in examples/physics built with a helicopter (-D SKY),
    playing its tape: walk to the helicopter and get in, which swaps the air
    module in; climb, fly south over a six-storey block, settle onto its
    roof; climb, fly back north and settle onto the road; get out, which
    swaps the ground module back, and walk.  Every frame, no body's box has
    a corner in what its mover counts as a wall: for the helicopter, a
    building standing higher than it, judged from the map and the
    tileset's heights.  The swaps as for the boats; the helicopter crosses
    a building in the air, rests on its roof at the roof's height, and
    never flies above the ceiling; the player ends on land with the ground
    module in; two runs end alike.  And the step's cost."""
    in_wall, over_building, _, _, _ = scene_map()
    d = module_scene(port, "build/sky-auto.prg", 700, 2)
    walls = sum(1 for _, bs, _ in d["frames"] for b in bs.values() if in_wall(b))
    heli = [bs[p] for p, bs, _ in d["frames"] if p in bs and bs[p]["mov"] == 4]
    crossed = sum(1 for b in heli if over_building(b) and b["z"] > 48)
    roof = sum(1 for b in heli if over_building(b) and b["z"] == 48 and b["vz"] == 0)
    top = max((b["z"] for b in heli), default=0)
    p, mod = d["end"]
    last = d["finals"][0][p]
    landed = (last["mov"], mod, in_wall(last)) == (1, 0, False)
    sw = d["swaps"]
    R.check("sky.walls", walls == 0, f"700 frames of the tape: {walls} body-frames with a corner in its mover's walls "
            "(for the helicopter, a building standing higher than it)")
    R.check("sky.swap", len(sw) == 2 and all(s[1] and s[2] for s in sw) and [s[0] for s in sw] == [2, 0],
            f"{len(sw)} swaps ({', '.join(('water', 'air')[s[0] - 1] if s[0] else 'ground' for s in sw)}): body tables "
            f"{'unchanged' if all(s[1] for s in sw) else 'CHANGED'} across each; the module in place "
            f"{'matches' if all(s[2] for s in sw) else 'DOES NOT match'} its binary")
    R.check("sky.flight", crossed > 0 and roof > 0 and 0 < top <= 112,
            f"over a building in the air for {crossed} frames, resting on its roof (48 pixels) for {roof}; "
            f"highest {top} of a 112-pixel ceiling")
    R.check("sky.landed", landed, "the player ends on foot, on land, with the ground module in" if landed
            else f"the player ends as mover {last['mov']} with module {mod}")
    R.check("sky.repeat", d["finals"][0] == d["finals"][1], "two runs of the tape end in the same state"
            if d["finals"][0] == d["finals"][1] else "two runs of the tape end in different states")
    R.measure("sky.step_median", d["costs"][len(d["costs"]) // 2])
    R.measure("sky.step_worst", d["costs"][-1])
    R.measure("sky.frames_lost", d["lost"])


def hover(R, port):
    """Shots and height, in examples/physics built with a hovering
    helicopter (-D HOVER), in the air module from the start: the player
    fires three shots at a helicopter holding 32 pixels up across the road,
    which pass beneath it, and tosses a grenade under it, whose blast does
    not reach that high; the helicopter settles, and the same shots hit it.
    Every frame, while it is 8 pixels or more up, it is never hit, and shots
    are seen inside its footprint; a blast goes off within reach of it
    while it is 16 or more up, and it is not marked; on the ground it is
    hit.  No body in its walls; two runs alike; the cost."""
    in_wall, _, _, _, _ = scene_map()

    def shots(v, syms):
        on = v.mem(syms["sh_on"], 8)
        xs = [a | b << 8 for a, b in zip(v.mem(syms["sh_xl"], 8), v.mem(syms["sh_xh"], 8))]
        ys = [a | b << 8 for a, b in zip(v.mem(syms["sh_yl"], 8), v.mem(syms["sh_yh"], 8))]
        fx = (v.mem(syms["fx_t"])[0], v.mem(syms["fx_k"])[0], v.word(syms["fx_x"]), v.word(syms["fx_y"]))
        return [(x, y) for k, (x, y) in enumerate(zip(xs, ys)) if on[k]], fx
    d = module_scene(port, "build/hover-auto.prg", 600, 0, shots)
    walls = sum(1 for _, bs, _ in d["frames"] for b in bs.values() if in_wall(b))
    up_hits = beneath = blasts = marked = down_hits = 0
    for _, bs, (sh, fx) in d["frames"]:
        h = next(b for b in bs.values() if b["mov"] == 4)
        if h["z"] >= 8:
            up_hits += bool(h["hit"])
            beneath += sum(1 for x, y in sh if abs(x - h["x"]) <= 8 and abs(y - h["y"]) <= 8)
        elif h["z"] == 0:
            down_hits += bool(h["hit"])
        if fx[0] == 12 and fx[1] == 2 and abs(fx[2] - h["x"]) < 40 and abs(fx[3] - h["y"]) < 40 and h["z"] >= 16:
            blasts += 1
            marked += bool(h["hit"])
    R.check("hover.walls", walls == 0, f"600 frames of the tape: {walls} body-frames with a corner in its mover's walls")
    R.check("hover.beneath", up_hits == 0 and beneath > 0, f"while the helicopter was up: shots inside its footprint in "
            f"{beneath} frames, {up_hits} frames hit")
    R.check("hover.blast", blasts > 0 and marked == 0, f"{blasts} blasts within reach while it was 16 pixels or more up, "
            f"{marked} of them marking it")
    R.check("hover.down", down_hits > 0, f"on the ground it was hit in {down_hits} frames")
    R.check("hover.repeat", d["finals"][0] == d["finals"][1], "two runs of the tape end in the same state"
            if d["finals"][0] == d["finals"][1] else "two runs of the tape end in different states")
    R.measure("hover.step_median", d["costs"][len(d["costs"]) // 2])
    R.measure("hover.step_worst", d["costs"][-1])
    R.measure("hover.frames_lost", d["lost"])


def plane(R, port):
    """The plane, in examples/physics built with one on the road (-D PLANE):
    get in, which swaps the air module in; the throttle along the road;
    at flying speed climb over the blocks and fly a full circle; back on the
    road's line, throttle back and sink onto it; brake, get out, which swaps
    the ground module back.  No body in its walls, a building standing
    higher than the plane counting for it; the swaps as for the boats; the
    plane leaves the road at flying speed, is over a building in the air,
    turns through every heading in the air, comes down on the road and
    stops there; the player ends on land with the ground module in; two
    runs alike; the cost."""
    in_wall, over_building, props, _, world = scene_map()
    d = module_scene(port, "build/plane-auto.prg", 880, 2)
    walls = sum(1 for _, bs, _ in d["frames"] for b in bs.values() if in_wall(b))
    craft = [next(b for b in bs.values() if b["mov"] == 6) for _, bs, _ in d["frames"]]
    up = [b for b in craft if b["z"] > 0]
    crossed = sum(1 for b in up if over_building(b))
    headings = len({(b["ang"] + 8) >> 4 & 15 for b in up})
    last_up = max((i for i, b in enumerate(craft) if b["z"] > 0), default=None)
    end = d["finals"][0]
    pl = next(b for b in end.values() if b["mov"] == 6)
    on_road = bool(props[world[((pl["y"] >> 5) << 11) | (pl["x"] >> 5)]] & 0x0F)
    down = last_up is not None and pl["z"] == 0 and on_road and pl["st"] & 0x80
    p, mod = d["end"]
    last = end[p]
    landed = (last["mov"], mod, in_wall(last)) == (1, 0, False)
    sw = d["swaps"]
    R.check("plane.walls", walls == 0, f"880 frames of the tape: {walls} body-frames with a corner in its mover's walls "
            "(for the plane, a building standing higher than it)")
    R.check("plane.swap", len(sw) == 2 and all(s[1] and s[2] for s in sw) and [s[0] for s in sw] == [2, 0],
            f"{len(sw)} swaps: body tables {'unchanged' if all(s[1] for s in sw) else 'CHANGED'} across each; the "
            f"module in place {'matches' if all(s[2] for s in sw) else 'DOES NOT match'} its binary")
    R.check("plane.flight", crossed > 0 and headings == 16 and max((b["z"] for b in up), default=0) <= 112,
            f"in the air {len(up)} frames, over buildings for {crossed}, through {headings} of 16 headings; highest "
            f"{max((b['z'] for b in up), default=0)}")
    R.check("plane.down", bool(down), "down on the road and stopped, asleep" if down else
            f"ends at height {pl['z']}, {'on' if on_road else 'off'} the road, {'asleep' if pl['st'] & 0x80 else 'awake'}")
    R.check("plane.landed", landed, "the player ends on foot, on land, with the ground module in" if landed
            else f"the player ends as mover {last['mov']} with module {mod}")
    R.check("plane.repeat", d["finals"][0] == d["finals"][1], "two runs of the tape end in the same state"
            if d["finals"][0] == d["finals"][1] else "two runs of the tape end in different states")
    R.measure("plane.step_median", d["costs"][len(d["costs"]) // 2])
    R.measure("plane.step_worst", d["costs"][-1])
    R.measure("plane.frames_lost", d["lost"])


def debris(R, port):
    """Debris, in examples/physics built with a tape of crashes and a blast
    (-D DEBRIS): drive into the parked cars, back off, get out, toss a
    grenade at the wrecks.  A car hit hard throws out pieces, and so does a
    blast; no piece ever goes below the ground, and each lies still on it
    before it goes.  No body in its walls; two runs alike; the costs of the
    physics step and of the collision step, debris and all."""
    in_wall, _, _, _, _ = scene_map()

    def pieces(v, syms):
        t = v.mem(syms["db_t"], 12)
        z = v.mem(syms["db_zh"], 12)
        fx = (v.mem(syms["fx_t"])[0], v.mem(syms["fx_k"])[0])
        return t, z, fx
    d = module_scene(port, "build/debris-auto.prg", 560, 0, pieces, col=True)
    walls = sum(1 for _, bs, _ in d["frames"] for b in bs.values() if in_wall(b))
    crash_bursts = blast_bursts = under = unsettled = 0
    prev = [0] * 12
    for _, bs, (t, z, fx) in d["frames"]:
        new = sum(1 for k in range(12) if t[k] and not prev[k])
        if new:
            if fx[0] == 12 and fx[1] == 2:
                blast_bursts += 1
            elif any(b["mov"] == 2 and b["hit"] >= 16 for b in bs.values()):
                crash_bursts += 1
        under += sum(1 for k in range(12) if t[k] and z[k] & 0x80)
        unsettled += sum(1 for k in range(12) if t[k] == 1 and z[k] != 0)
        prev = t
    R.check("debris.walls", walls == 0, f"560 frames of the tape: {walls} body-frames with a corner in its mover's walls")
    R.check("debris.thrown", crash_bursts > 0 and blast_bursts > 0,
            f"{crash_bursts} bursts from crashes, {blast_bursts} from blasts")
    R.check("debris.ground", under == 0 and unsettled == 0, f"{under} piece-frames below the ground; {unsettled} pieces "
            "off the ground as they went")
    R.check("debris.repeat", d["finals"][0] == d["finals"][1], "two runs of the tape end in the same state"
            if d["finals"][0] == d["finals"][1] else "two runs of the tape end in different states")
    R.measure("debris.step_median", d["costs"][len(d["costs"]) // 2])
    R.measure("debris.step_worst", d["costs"][-1])
    R.measure("debris.col_median", d["col_costs"][len(d["col_costs"]) // 2])
    R.measure("debris.col_worst", d["col_costs"][-1])
    R.measure("debris.frames_lost", d["lost"])


def marsh(R, port):
    """Airboats and marsh, in examples/physics built on the sand beside a
    marsh (-D MARSH), in the water module from the start: walk to the
    airboat and get in; south through the reeds, a quarter turn east and on
    out into the sea.  A speedboat at sea holds its throttle west into the
    marsh.  No body in its walls, the marsh being one for the speedboat and
    water for the airboat; the airboat is in the marsh and then clear of it
    at sea; the speedboat is stopped at the marsh's edge; two runs alike."""
    in_wall, _, props, _, world = scene_map()
    d = module_scene(port, "build/marsh-auto.prg", 400, 0)
    walls = sum(1 for _, bs, _ in d["frames"] for b in bs.values() if in_wall(b))

    def marsh_corners(b):
        return sum(1 for cx in (b["x"] - 7, b["x"] + 7) for cy in (b["y"] - 7, b["y"] + 7)
                   if props[world[((cy >> 5) << 11) | (cx >> 5)]] & 0x41 == 0x41)
    boat = [next(b for b in bs.values() if b["mov"] == 7) for _, bs, _ in d["frames"]]
    in_marsh = sum(1 for b in boat if marsh_corners(b) == 4)
    at_sea = sum(1 for b in boat if marsh_corners(b) == 0 and b["x"] > 1712 * 32)
    spd = [next(b for b in bs.values() if b["mov"] == 3) for _, bs, _ in d["frames"]]
    pinned = sum(1 for b in spd if b["st"] & 8 and b["x"] - 7 <= 1712 * 32 + 1)
    R.check("marsh.walls", walls == 0, f"400 frames of the tape: {walls} body-frames with a corner in its mover's walls "
            "(the marsh a wall to a boat, water to an airboat)")
    R.check("marsh.crossed", in_marsh > 0 and at_sea > 0, f"the airboat wholly in the marsh for {in_marsh} frames, "
            f"clear of it at sea for {at_sea}")
    R.check("marsh.pinned", pinned > 0, f"the speedboat against the marsh's edge in {pinned} frames")
    R.check("marsh.repeat", d["finals"][0] == d["finals"][1], "two runs of the tape end in the same state"
            if d["finals"][0] == d["finals"][1] else "two runs of the tape end in different states")
    R.measure("marsh.step_median", d["costs"][len(d["costs"]) // 2])
    R.measure("marsh.step_worst", d["costs"][-1])
    R.measure("marsh.frames_lost", d["lost"])


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
        for name, fn in (("boot", boot_failures), ("scroller", scroller), ("ticks", cutscene_ticks), ("probe", probe_block), ("mux", multiplexer), ("muxhw", mux_instrument), ("traffic", traffic), ("physics", physics), ("boats", boats), ("sky", sky), ("hover", hover), ("plane", plane), ("debris", debris), ("marsh", marsh)):
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
