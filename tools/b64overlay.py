#!/usr/bin/env python3
"""Link a code overlay against a resident program.

An overlay is assembled like any other module and may import engine
routines.  Those live at fixed addresses in the resident program, so this
tool reads the program's VICE label file (ld65 -Ln), takes every symbol
the engine declares .global in include/b64.inc, turns each into a linker
define, and links the overlay for its window with overlay.cfg.

usage: b64overlay.py <program.lbl> <overlay.cfg> <overlay.o> <out.bin>
"""
import re, subprocess, sys


def engine_globals():
    text = open("include/b64.inc").read()
    return set(re.findall(r"^\.global\s+([A-Za-z_][A-Za-z0-9_]*)", text, re.M))


def labels(lbl_path):
    out = {}
    for line in open(lbl_path):
        m = re.match(r"al ([0-9A-Fa-f]{6}) \.([A-Za-z_][A-Za-z0-9_]*)$", line.strip())
        if m:
            out[m.group(2)] = m.group(1)
    return out


def main():
    lbl_path, cfg, obj, out = sys.argv[1:5]
    wanted = engine_globals()
    found = labels(lbl_path)
    defs = []
    for name in sorted(wanted):
        if name in found:
            defs += ["-D", f"{name}=${found[name]}"]
    cmd = ["ld65", "-C", cfg, "-o", out] + defs + [obj]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.stderr.write(r.stderr)
        raise SystemExit(f"overlay link failed for {obj}")
    size = len(open(out, "rb").read())
    print(f"  {out}: {size} bytes")


if __name__ == "__main__":
    main()
