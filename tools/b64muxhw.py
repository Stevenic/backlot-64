#!/usr/bin/env python3
"""The multiplexer's test, on VICE or on a C64 Ultimate.

Runs the harness (examples/mux, a test build made with -DB64_MUXLOG), and
takes snapshots through the harness's freeze protocol: the host asks it to
stop building lists, the engine then shows the same list every frame, so
every table and the group log hold still, and the host reads them at its
leisure.  From each snapshot it checks what the VIC-II requires:

  - a group's interrupt starts no earlier than the line after every
    member's previous occupant was last shown (an occupant with Y = y is
    shown on lines y+1..y+21, so its sprite is free from y+22), else a
    sprite would be cut short;
  - every entry's Y is written before cycle 55 of its line, when the VIC-II
    compares it, and its pointer before the pointer's fetch (Bauer 3.8),
    else it is late.  Each entry is stamped just after its pointer is
    written with the log clock, CIA1 timer A counting four lines over and
    over (mux_clock in src/b64_sprites.s), which gives the line modulo 4
    and the cycle.  The group's start line (the raster, read as its
    interrupt begins) anchors the first stamp and each stamp the next: a
    stamp is at the first time after the one before that matches its
    count.  That is exact while events are under four lines apart; at
    1 MHz the code between them is under 70 cycles and the VIC-II can
    steal at most ~62 more a line, so they are under 200 cycles apart.
    At 1 MHz the Y store is at least 28 cycles before the stamp and the
    pointer store 4; with the turbo the stamp itself is taken as both,
    which can only err towards late.  The stamp costs 9 cycles an entry
    and the start line 7 a group, so the test build's chain is a little
    slower than the real one's: a pass here is a pass there;
  - group 0, which the blank writes for the next frame, starts after every
    hardware sprite's last occupant has been shown, as far as the display
    window shows it (lines 51 to 250; below that the border hides the
    sprite), else the bottom sprite is cut short (the vblank interrupt is
    at line 255, so a logged start below 64 is on lines 256 and up);
  - every accepted entry is in exactly one group, in y order.

It also reports the chain's measured costs, the figures the timing model
in b64_turbo_set (src/b64_plat.s) is set from: the lines from a group's
line to its first entry's stamp (mux_lead1 should be that plus a line),
and the lines between entries within a group (mux_step).

It reports, per snapshot: entries shown, entries dropped, groups, and any
violation, plus the harness's own measurements (list build time and the
speed it ran at).  On VICE it drives x64sc through the monitor
(tools/b64vice.py); on the Ultimate it uses the REST API (firmware 3.11+):
POST /v1/runners:run_prg, GET /v1/machine:readmem, PUT /v1/machine:writemem.
The REU image must already be loaded on the Ultimate (docs/ULTIMATE.md).

The instrument is itself checked on VICE (--validate): with the harness
frozen, it breaks just after each stamp's read and compares the time the
stamp is rebuilt as with the emulator's own line and cycle.

usage: b64muxhw.py --vice build/mlog/mux64.prg [--reu build/world8.reu --reusize 8192] [--validate]
       b64muxhw.py --host 192.168.1.64 [--password P] --prg build/mlog/mux64.prg
       options: --snapshots 5  --json out.json
UNTESTED on hardware as of 2026-09-18: the REST path waits for the machine.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from b64vice import Vice, load_labels            # noqa: E402

N2 = 128                                        # two halves of B64_MAX_SPRITES (64)
T = {"b_xlo": 0, "b_y": 1, "b_ptr": 2, "b_col": 3, "b_flg": 4, "acc": 5, "g_line": 6,
     "g_pos": 7, "g_cnt": 8, "rr_lo": 9, "rr_hi": 10, "rr_bit": 11}
RES, FREEZE_REQ, FREEZE_ACK = 0xE000, 0xE020, 0xE021
LOG = 0xE800                                    # B64_MUXLOG_AT: see include/b64.inc
ZP_COUNT_S, ZP_BASE_S = 0x42, 0x44


class ViceTarget:
    def __init__(self, prg, lbl, reu, reusize, port=6680):
        self.v = Vice(prg, reusize, reu, lbl, port)
        self.labels = self.v.labels

    def settle(self, seconds):
        self.v.frames(int(seconds * 50))

    def read(self, addr, n):
        out = b""
        while n > 0:                            # the monitor reads a few KB at a time comfortably
            k = min(n, 2048)
            out += self.v.mem(addr, k)
            addr += k
            n -= k
        return out

    def write(self, addr, data):
        self.v.poke(addr, data)

    def wait_until(self, addr, value, timeout=10):
        for _ in range(int(timeout * 50)):
            self.v.frames(1)
            if self.v.mem(addr)[0] == value:
                return True
        return False

    def close(self):
        self.v.close()


class UltimateTarget:
    """The C64 Ultimate's REST API.  UNTESTED until the hardware arrives."""
    def __init__(self, host, password, prg, lbl):
        self.base = f"http://{host}"
        self.hdr = {"X-Password": password} if password else {}
        self.labels = load_labels(lbl)
        req = urllib.request.Request(f"{self.base}/v1/runners:run_prg", data=open(prg, "rb").read(),
                                     headers={**self.hdr, "Content-Type": "application/octet-stream"}, method="POST")
        urllib.request.urlopen(req, timeout=20).read()

    def settle(self, seconds):
        time.sleep(seconds)

    def read(self, addr, n):
        req = urllib.request.Request(f"{self.base}/v1/machine:readmem?address={addr:04X}&length={n}", headers=self.hdr)
        return urllib.request.urlopen(req, timeout=20).read()

    def write(self, addr, data):
        req = urllib.request.Request(f"{self.base}/v1/machine:writemem?address={addr:04X}&data={bytes(data).hex()}",
                                     headers=self.hdr, method="PUT")
        urllib.request.urlopen(req, timeout=20).read()

    def wait_until(self, addr, value, timeout=10):
        end = time.time() + timeout
        while time.time() < end:
            if self.read(addr, 1)[0] == value:
                return True
            time.sleep(0.05)
        return False

    def close(self):
        pass


def snapshot(t):
    """Freeze, read everything, thaw."""
    t.write(FREEZE_REQ, b"\x01")
    if not t.wait_until(FREEZE_ACK, 1):
        raise RuntimeError("the harness did not freeze")
    L = t.labels
    snap = {
        "tables": t.read(L["mux_tables"], 12 * N2),
        "log": t.read(LOG, 512),
        "plat": t.read(L["b64_plat"], 1)[0],
        "turbo": t.read(L["b64_turbo"], 1)[0],
        "zp": t.read(0x40, 0x10),
        "mux_first": t.read(L["mux_first"], 1)[0],
        "rejected": t.read(L["spr_rejected"], 1)[0],
        "res": t.read(RES, 16),
    }
    t.write(FREEZE_REQ, b"\x00")
    return snap


WINDOW_END = 250            # the display window's last line (PAL, 25 rows); the border hides a sprite below it
K_CAL = 10                  # cycles from a line's start to the count's read at the earliest sample, at 1 MHz:
                            # 9 from the read that sees the new line, and one more so that on VICE a rebuilt
                            # stamp is 1-2 cycles after the emulator's (--validate), never before
GAP_Y, GAP_PTR = 28, 4      # at 1 MHz, the Y and pointer stores are at least this long before the stamp


def clock_phase(log):
    """The count's offset d0 from the calibration samples: at a line l's
    start the count reads 251 - ((l mod 4) * 63 - d0) mod 252."""
    r = sorted(((251 - log[256 + i]) - 63 * (log[384 + i] & 3)) % 252 for i in range(128))
    gaps = [((r[(i + 1) % len(r)] - r[i]) % 252, i) for i in range(len(r))]
    first = r[(max(gaps)[1] + 1) % len(r)]       # the start of the cluster, on the circle
    return (K_CAL - first) % 252


def stamp(log, x, d0, after):
    """The time (line * 63 + cycle) of list position x's stamp: the first
    time at or after `after` whose line modulo 4 and cycle match the count."""
    rel = ((251 - log[128 + x]) + d0) % 252
    t = after - after % 252 + rel
    return t if t >= after else t + 252


def ptr_deadline(h, y):
    """The last cycle (as line * 63 + cycle) a pointer store is in time for:
    sprite h's p-access is in cycle 58 + 2h (h = 0..2) of line y, or cycle
    2h - 5 of line y + 1 (h = 3..7); Bauer numbers cycles from 1."""
    return y * 63 + 57 + 2 * h - 1 if h <= 2 else (y + 1) * 63 + 2 * h - 7


def evaluate(snap):
    tb = snap["tables"]
    log = snap["log"]

    def col(name, i):
        return tb[T[name] * N2 + i]
    base, n = snap["zp"][ZP_BASE_S - 0x40], snap["zp"][ZP_COUNT_S - 0x40]
    first_hw = snap["mux_first"]
    hwc = 8 - first_hw
    res = snap["res"]
    turbo = bool(snap["plat"] & 0x04) and (snap["turbo"] & 0x0F) != 0
    gy, gp = (0, 0) if turbo else (GAP_Y, GAP_PTR)
    d0 = clock_phase(log)
    out = {"shown": n, "dropped": snap["rejected"], "groups": 0, "violations": [],
           "build_us": int.from_bytes(res[4:7], "little"), "speed": res[13], "limit": res[14], "hw": hwc,
           "turbo": turbo, "slack": None}
    ys = [col("b_y", col("acc", base + k)) for k in range(n)]
    if ys != sorted(ys):
        out["violations"].append(("list not in y order", ys))
    # group 0 is written in the blank for the next frame (the vblank interrupt
    # is at line 255, so a logged start below 64 is on line 256 and up): every
    # sprite's last occupant must be shown by then
    g0 = log[base]
    g0 = g0 + 256 if g0 < 64 else g0
    last = {}
    for k in range(n):
        last[k % hwc] = ys[k]
    for h, y in last.items():
        if n > hwc and min(y + 22, WINDOW_END + 1) > g0:
            out["violations"].append(("cut short by the blank", h, y, g0))
    seen, firsts, steps, slack = [], [], [], []
    g = base
    while True:
        line = col("g_line", g) if g != base else 0
        if g != base and line == 255:
            break
        pos, cnt = col("g_pos", g), col("g_cnt", g)
        members = list(range(pos, pos + cnt))
        seen += members
        out["groups"] += 1
        if g != base and cnt:
            start = log[g]
            prev_t = None
            after = start * 63
            for k in members:
                y = col("b_y", col("acc", k))
                h = (k - base) % hwc + first_hw
                prev = k - hwc
                if prev >= base and start < col("b_y", col("acc", prev)) + 22:
                    out["violations"].append(("cut short", g - base, k - base, start, col("b_y", col("acc", prev))))
                t = stamp(log, k, d0, after)
                after = t
                ydl, pdl = y * 63 + 54, ptr_deadline(h, y)
                if t - gy > ydl or t - gp > pdl:
                    out["violations"].append(("late", g - base, k - base, divmod(t, 63), y))
                slack.append(min(ydl - (t - gy), pdl - (t - gp)))
                if prev_t is None:
                    firsts.append((t - line * 63) / 63)
                else:
                    steps.append((t - prev_t) / 63)
                prev_t = t
        g += 1
        if g >= base + 64:
            out["violations"].append(("no end marker",))
            break
    if seen != list(range(base, base + n)):
        out["violations"].append(("groups do not cover the list once, in order",))
    out["first_lines"] = round(max(firsts), 2) if firsts else None
    out["step_lines"] = round(max(steps), 2) if steps else None
    out["slack"] = min(slack) if slack else None
    return out


STAMP_AT = 30                   # the instruction after the stamp's read, in a generated routine


def validate(t, hits=160):
    """VICE only: rebuilt stamps against the emulator's clock.  -> list of
    (list position, emulator time - rebuilt time) in cycles."""
    v = t.v
    t.settle(3)
    t.write(FREEZE_REQ, b"\x01")
    if not t.wait_until(FREEZE_ACK, 1):
        raise RuntimeError("the harness did not freeze")
    rout = v.addr("mux_rout")
    nums = [int(re.search(r"BREAK: (\d+)", v.cmd(f"break {rout + 64 * h + STAMP_AT:04x}")).group(1)) for h in range(8)]
    seen = {}
    for _ in range(hits):
        v.cmd("x", 20)
        m = re.search(r"\.;([0-9a-f]{4}) ([0-9a-f]{2}) ([0-9a-f]{2}) ([0-9a-f]{2}) \S+ \S+ \S+ \S+\s+(\d+) +(\d+)", v.cmd("r"))
        x, lin, cyc = int(m.group(3), 16), int(m.group(5)), int(m.group(6))
        if lin < 250:                           # group 0, in the blank, is not stamped against a group line
            seen[x] = lin * 63 + cyc - 1        # the read was the cycle before
    v.cmd("z")                                  # let the last stamp be stored
    for n in nums:
        v.cmd(f"del {n:x}")
    snap = snapshot(t)
    tb, log = snap["tables"], snap["log"]
    base, n = snap["zp"][ZP_BASE_S - 0x40], snap["zp"][ZP_COUNT_S - 0x40]
    d0 = clock_phase(log)
    out = []
    g = base + 1
    while tb[T["g_line"] * N2 + g] != 255 and g < base + 64:
        pos, cnt = tb[T["g_pos"] * N2 + g], tb[T["g_cnt"] * N2 + g]
        after = log[g] * 63
        for k in range(pos, pos + cnt):
            after = stamp(log, k, d0, after)
            if k in seen:
                out.append((k - base, seen[k] - after))
        g += 1
    return out


def valid(d):
    """Every rebuilt stamp on the emulator's line, and never before it: late by 0 to 3 cycles."""
    return bool(d) and all(-3 <= e <= 0 for _, e in d)


def run(target, snapshots=5, settle=3.0, between=0.7):
    target.settle(settle)
    results = []
    for _ in range(snapshots):
        results.append(evaluate(snapshot(target)))
        target.settle(between)
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vice")
    ap.add_argument("--host")
    ap.add_argument("--password")
    ap.add_argument("--prg")
    ap.add_argument("--reu", default="build/world8.reu")
    ap.add_argument("--reusize", default="8192")
    ap.add_argument("--snapshots", type=int, default=5)
    ap.add_argument("--json")
    ap.add_argument("--validate", action="store_true")
    a = ap.parse_args()
    if a.validate:
        t = ViceTarget(a.vice, os.path.splitext(a.vice)[0] + ".lbl", a.reu, int(a.reusize))
        try:
            d = validate(t)
        finally:
            t.close()
        errs = sorted(set(e for _, e in d))
        print(f"{len(d)} stamps compared with the emulator's clock; emulator minus rebuilt, in cycles: {errs}")
        sys.exit(0 if valid(d) else 1)
    if a.vice:
        t = ViceTarget(a.vice, os.path.splitext(a.vice)[0] + ".lbl", a.reu, int(a.reusize))
    else:
        t = UltimateTarget(a.host, a.password, a.prg, os.path.splitext(a.prg)[0] + ".lbl")
    try:
        results = run(t, a.snapshots)
    finally:
        t.close()
    for i, r in enumerate(results):
        print(f"snapshot {i}: {r['shown']} shown, {r['dropped']} dropped, {r['groups']} groups, "
              f"{len(r['violations'])} violations; list build {r['build_us']} us; $D031 {r['speed']:02X}, "
              f"limit {r['limit']}, {r['hw']} hardware sprites")
        print(f"    {'turbo' if r['turbo'] else '1 MHz'}: first entry {r['first_lines']} lines after its group's line "
              f"at worst, {r['step_lines']} lines between entries of a group at worst; "
              f"least slack before a deadline {r['slack']} cycles")
        for v in r["violations"][:5]:
            print("   ", v)
    if a.json:
        json.dump(results, open(a.json, "w"), indent=1, default=str)
    sys.exit(1 if any(r["violations"] for r in results) else 0)


if __name__ == "__main__":
    main()
