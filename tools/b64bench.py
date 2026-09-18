#!/usr/bin/env python3
"""Run build/bench.prg in VICE and print the measured cycle counts.

The benchmark (examples/bench/main.s) times REU fetches of five sizes from
the border and from inside the display, one VM tick of three scripts, and
64 iterations of the cutscene drive step written in assembly.  Results are
24-bit cycle counts at $E000; this reads them through the remote monitor.
"""
import re, socket, subprocess, sys, time

NAMES = [
    ("fetch 64 B, border", 64), ("fetch 256 B, border", 256), ("fetch 1 KB, border", 1024),
    ("fetch 4 KB, border", 4096), ("fetch 8 KB, border", 8192),
    ("fetch 64 B, display", 64), ("fetch 256 B, display", 256), ("fetch 1 KB, display", 1024),
    ("fetch 4 KB, display", 4096), ("fetch 8 KB, display", 8192),
    ("VM tick, 64 x LOOP", 64), ("VM tick, drive body, 71 ops (4 steps)", 71),
    ("asm, 64 x drive step", 64), ("VM tick, 63 x ADD + YIELD + JMP", 65),
]

def main():
    reu = sys.argv[1] if len(sys.argv) > 1 else "build/world.reu"
    size = sys.argv[2] if len(sys.argv) > 2 else "16384"
    p = subprocess.Popen(["x64sc", "-default", "-reu", "-reusize", size, "-reuimage", reu, "+reuimagerw",
                          "+sound", "+confirmonexit", "-remotemonitor", "-remotemonitoraddress",
                          "ip4://127.0.0.1:6510", "-autostartprgmode", "1", "build/bench.prg"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(5.0)
    s = socket.create_connection(("127.0.0.1", 6510), timeout=5)

    def cmd(c, wait=0.5):
        s.sendall((c + "\n").encode()); time.sleep(wait); out = b""; s.settimeout(0.5)
        try:
            while True:
                d = s.recv(65536)
                if not d:
                    break
                out += d
        except Exception:
            pass
        return out.decode(errors="replace")

    out = cmd("m e000 e02f")
    plat = cmd("m e02a e02b")
    b = []
    for line in out.splitlines():
        m = re.search(r'>C:[0-9a-f]{4}\s+((?:[0-9a-f]{2} {1,2}){16})', line)
        if m:
            b += [int(t, 16) for t in m.group(1).split()]
    cmd("quit"); p.wait(timeout=5)
    pm = re.search(r'>C:e02a\s+([0-9a-f]{2}) +([0-9a-f]{2})', plat)
    if pm:
        f = int(pm.group(1), 16); mb = int(pm.group(2), 16)
        names = [n for bit, n in ((1, "reu"), (2, "reu16"), (4, "turbo"), (8, "audio"), (16, "uci")) if f & bit]
        print(f"platform: {' '.join(names) or 'stock, no REU'}; REU {mb} MB")
    print(f"{'test':32s} {'cycles':>8s} {'per unit':>9s}")
    for i, (n, unit) in enumerate(NAMES):
        v = b[3 * i] | (b[3 * i + 1] << 8) | (b[3 * i + 2] << 16)
        per = "%.1f/B" % (v / unit) if "fetch" in n else "%.0f/op" % (v / unit)
        print(f"{n:32s} {v:8d} {per:>9s}")

if __name__ == "__main__":
    main()
