#!/usr/bin/env python3
"""Read the engine's probe block and print a profile.

A probe build (make build/prof/<example>.prg) records events, program
counter samples, opcode counts and tick timings into 2 KB at $F800
(src/b64_probe.s).  This tool pulls that block from one of two sources and
decodes it the same way:

  --vice <prg>     run the program in x64sc with the remote monitor, wait,
                   and read the block through the monitor
  --host <ip>      read the block from a C64 Ultimate over its REST
                   interface (GET /v1/machine:readmem); --run <prg> uploads
                   and starts the program first (POST /v1/runners:run_prg)
  --file <bin>     decode a block saved earlier

Symbols come from the program's label file (--labels, from ld65 -Ln) and
the script's (--script-labels).  --json writes the decoded profile for the
optimizer.  The hardware path is written from the REST documentation and
UNTESTED until the C64 Ultimate arrives.
"""
import argparse, json, os, re, socket, subprocess, sys, time, urllib.request

PROBE = 0xF800
SIZE = 1440
TAGS = {1: "irq vblank entry", 2: "irq vblank done", 3: "callback start", 6: "callback done",
        4: "spr_begin enter", 5: "spr_begin released", 7: "irq took list", 8: "vm tick start",
        9: "vm tick end", 10: "spr_end start", 11: "thread done", 12: "slot dma"}
OPNAMES = ["END", "WAIT", "YIELD", "JMP", "SPAWN", "CALL", "RET", "LOOP", "LDI", "MOV", "ADD", "ADDI",
           "SUB", "SUBI", "AND", "ANDI", "MIN", "MINI", "MAX", "MAXI", "SHR", "SHL", "JLT", "JLTI",
           "JGE", "JGEI", "JEQ", "JEQI", "JNE", "JNEI", "LDT", "FRAME", "JOY", "STILL", "OBJECT",
           "SHIMMER", "TEXT", "CLEARTEXT", "BLIT", "RESTORE", "PARK", "UNPARK", "OBJSPR", "OBJANIM",
           "SPRITE", "PCM"]


def read_labels(path, script=False):
    """Labels from ld65 -Ln.  With -g the file also carries every constant
    from c64.inc (all-capitals names), which are not code; for a script,
    whose offsets start at 0, those would shadow the real labels, so they
    are dropped."""
    out = []
    if not path or not os.path.exists(path):
        return out
    for line in open(path):
        m = re.match(r"al ([0-9A-Fa-f]{6}) \.([A-Za-z_@][A-Za-z0-9_@]*)$", line.strip())
        if not m or m.group(2).startswith("@"):
            continue
        name = m.group(2)
        if script and name.upper() == name:
            continue
        out.append((int(m.group(1), 16), name))
    out.sort()
    return out


def nearest(labels, addr):
    best = None
    for a, n in labels:
        if a <= addr:
            best = (a, n)
        else:
            break
    return f"{best[1]}+{addr - best[0]}" if best else f"${addr:04X}"


# ---------------------------------------------------------------- sources
def from_vice(prg, reu, reusize, seconds):
    p = subprocess.Popen(["x64sc", "-default", "-reu", "-reusize", str(reusize), "-reuimage", reu, "+reuimagerw",
                          "+sound", "+confirmonexit", "-remotemonitor", "-remotemonitoraddress",
                          "ip4://127.0.0.1:6512", "-autostartprgmode", "1", prg],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(seconds)
    s = socket.create_connection(("127.0.0.1", 6512), timeout=5)

    def cmd(c, wait=0.4):
        s.sendall((c + "\n").encode()); time.sleep(wait); out = b""; s.settimeout(0.3)
        try:
            while True:
                d = s.recv(65536)
                if not d:
                    break
                out += d
        except Exception:
            pass
        return out.decode(errors="replace")

    cmd("r")
    tmp = os.path.abspath("build/probe.bin")
    cmd(f'save "{tmp}" 0 {PROBE:04x} {PROBE + SIZE - 1:04x}', 1.0)
    cmd("quit"); p.wait(timeout=5)
    return open(tmp, "rb").read()[2:]


def from_host(host, password, run):
    hdr = {"X-Password": password} if password else {}
    if run:
        req = urllib.request.Request(f"http://{host}/v1/runners:run_prg", data=open(run, "rb").read(),
                                     headers={**hdr, "Content-Type": "application/octet-stream"}, method="POST")
        urllib.request.urlopen(req).read()
        time.sleep(8)
    req = urllib.request.Request(f"http://{host}/v1/machine:readmem?address={PROBE:04X}&length={SIZE}", headers=hdr)
    return urllib.request.urlopen(req).read()


# ---------------------------------------------------------------- decode
def decode(b, labels, slabels):
    if b[:4] != b"B64P":
        raise SystemExit("no probe block: is this a probe build (make build/prof/<example>.prg)?")
    plat, reumb, frame = b[5], b[6], b[7]
    evidx = b[8] | (b[9] << 8)
    smidx = b[10] | (b[11] << 8)
    tick_last = b[12] | (b[13] << 8) | (b[14] << 16)
    tick_max = b[15] | (b[16] << 8) | (b[17] << 16)
    hist = [b[32 + 2 * i] | (b[33 + 2 * i] << 8) for i in range(16)]
    events = []
    n = min(evidx, 160)
    start = evidx - n
    for k in range(start, evidx):
        i = 64 + (k % 160) * 3
        events.append({"tag": TAGS.get(b[i], str(b[i])), "frame": b[i + 1], "line": b[i + 2]})
    samples = []
    n = min(smidx, 128)
    for k in range(smidx - n, smidx):
        i = 64 + 480 + (k % 128) * 5
        pc = b[i] | (b[i + 1] << 8)
        vm = b[i + 2]
        samples.append({"pc": pc, "where": nearest(labels, pc), "thread": vm - 1 if vm else None,
                        "offset": (b[i + 3] << 8) | b[i + 4] if vm else None})
    ops = {}
    for i in range(0, 128, 2):          # counters are indexed by the doubled opcode byte
        c = b[64 + 480 + 640 + i] | (b[64 + 480 + 640 + 128 + i] << 8)
        if c:
            ops[OPNAMES[i // 2] if i // 2 < len(OPNAMES) else f"op{i // 2}"] = c
    return {"platform": plat, "reu_mb": reumb, "frame": frame, "tick_last": tick_last, "tick_max": tick_max,
            "tick_hist_1k": hist, "events": events, "samples": samples, "opcodes": ops}


def report(pr, slabels):
    names = [n for bit, n in ((1, "reu"), (2, "reu16"), (4, "turbo"), (8, "audio"), (16, "uci")) if pr["platform"] & bit]
    print(f"platform: {' '.join(names)}; REU {pr['reu_mb']} MB; frame {pr['frame']}")
    # the CIA timers count the 1 MHz clock at every turbo speed (measured on
    # hardware for DOOM C64U and on an Ultimate 64 Elite), so under turbo the
    # tick is wall time in microseconds, not CPU cycles executed
    unit = "microseconds (turbo: the CIA clock stays at 1 MHz)" if pr["platform"] & 4 else "cycles"
    print(f"tick: last {pr['tick_last']} {unit}, worst {pr['tick_max']}")
    hist = pr["tick_hist_1k"]; total = sum(hist) or 1
    print("tick histogram (1,024-cycle buckets): " + " ".join(f"{i}k:{h}" for i, h in enumerate(hist) if h))
    # engine hot spots
    where = {}
    for s in pr["samples"]:
        w = s["where"].split("+")[0]
        where[w] = where.get(w, 0) + 1
    n = len(pr["samples"]) or 1
    print(f"engine samples ({n}, CIA timer at 4,093-cycle intervals; percent of time by routine):")
    for w, c in sorted(where.items(), key=lambda kv: -kv[1])[:8]:
        print(f"  {c * 100 // n:3d}%  {w}")
    vm = [s for s in pr["samples"] if s["thread"] is not None]
    if vm:
        spots = {}
        for s in vm:
            key = (s["thread"], nearest(slabels, s["offset"]) if slabels else f"${s['offset']:04X}")
            spots[key] = spots.get(key, 0) + 1
        print(f"script samples ({len(vm)} of {n} were inside the VM):")
        for (t, w), c in sorted(spots.items(), key=lambda kv: -kv[1])[:8]:
            print(f"  {c:4d}  thread {t}  {w}")
    if pr["opcodes"]:
        tot = sum(pr["opcodes"].values())
        print(f"opcode mix ({tot} executed): " + ", ".join(f"{k} {v * 100 // tot}%" for k, v in sorted(pr["opcodes"].items(), key=lambda kv: -kv[1])[:10]))
    ev = pr["events"]
    if ev:
        print(f"last events ({len(ev)} kept):")
        for e in ev[-24:]:
            print(f"  {e['tag']:20s} frame={e['frame']:3d} line={e['line']:3d}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vice"); ap.add_argument("--reu", default="build/world.reu"); ap.add_argument("--reusize", default="16384")
    ap.add_argument("--seconds", type=float, default=6.0)
    ap.add_argument("--host"); ap.add_argument("--password"); ap.add_argument("--run")
    ap.add_argument("--file")
    ap.add_argument("--labels"); ap.add_argument("--script-labels")
    ap.add_argument("--json")
    a = ap.parse_args()
    if a.vice:
        b = from_vice(a.vice, a.reu, a.reusize, a.seconds)
    elif a.host:
        b = from_host(a.host, a.password, a.run)
    elif a.file:
        b = open(a.file, "rb").read()
        if b[:4] != b"B64P" and b[2:6] == b"B64P":
            b = b[2:]                       # a VICE save carries a two-byte load address
    else:
        ap.error("one of --vice, --host, --file")
    labels = read_labels(a.labels)
    slabels = read_labels(a.script_labels, script=True)
    pr = decode(b, labels, slabels)
    report(pr, slabels)
    if a.json:
        json.dump(pr, open(a.json, "w"), indent=1)
        print(f"wrote {a.json}")


if __name__ == "__main__":
    main()
