#!/usr/bin/env python3
"""Render a letter matrix as character-mode graphics, and encode it.

Art can be specified as a grid of letters, one letter a screen pixel, with
a mode per 8x8 character cell (2026-09-19).  This checks it against what
the chip can show, renders it as the VIC-II would, and prints the eight
bytes of every character so the art can go straight into a tileset.

The letters name colours: R the first shared colour ($D021), B the second
($D022), G the third ($D023), W the cell's own.  In a multicolour cell the
pixels pair, so every horizontal pair must match; a hires cell takes one
letter a pixel, shows only R and W, and its W must be one of the first
eight colours.

File format: a line `design <name...>`, a line `modes MMM MMM MMM` (one
letter a cell, row major, M or H), then the rows of letters.  Blank lines
and lines starting with # are ignored.

usage: b64matrix.py <file> <out.png> [--zoom 10] [--bytes] [--palette 12,9,5,1]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from b64palette import RGB  # noqa: E402
from b64png import write_png  # noqa: E402


def read_designs(path):
    designs, cur = [], None
    for line in open(path):
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.startswith("design "):
            cur = {"name": line[7:].strip(), "modes": [], "rows": []}
            designs.append(cur)
        elif line.startswith("modes "):
            cur["modes"] = list(line[6:].replace(" ", ""))
        else:
            cur["rows"].append(line.replace("|", "").strip())
    return designs


def check(d):
    """Every complaint the chip would have, as text."""
    out = []
    rows, modes = d["rows"], d["modes"]
    h, w = len(rows), max(len(r) for r in rows)
    if h % 8 or w % 8:
        out.append(f"{w}x{h} pixels: not a whole number of characters")
    cells_w, cells_h = w // 8, h // 8
    if len(modes) != cells_w * cells_h:
        out.append(f"{len(modes)} modes for {cells_w * cells_h} cells")
        return out, cells_w, cells_h
    for cy in range(cells_h):
        for cx in range(cells_w):
            mc = modes[cy * cells_w + cx] == "M"
            for y in range(8):
                row = rows[cy * 8 + y]
                for x in range(0, 8, 2 if mc else 1):
                    a = row[cx * 8 + x]
                    if mc and row[cx * 8 + x + 1] != a:
                        out.append(f"cell {cx},{cy} row {y}: multicolour pair "
                                   f"{a}{row[cx * 8 + x + 1]} does not match")
    return out, cells_w, cells_h


def encode(d, cells_w, cells_h):
    """Every character's eight bytes, as the charset would hold them."""
    rows, modes = d["rows"], d["modes"]
    bits = {"R": 0, "B": 1, "G": 2, "W": 3}
    out = []
    for cy in range(cells_h):
        for cx in range(cells_w):
            mc = modes[cy * cells_w + cx] == "M"
            byts = []
            for y in range(8):
                row = rows[cy * 8 + y]
                b = 0
                if mc:
                    for i in range(4):
                        b |= bits[row[cx * 8 + 2 * i]] << (6 - 2 * i)
                else:
                    for i in range(8):
                        b |= (1 if row[cx * 8 + i] == "W" else 0) << (7 - i)
                byts.append(b)
            out.append((cx, cy, "multicolour" if mc else "hires", byts))
    return out


def render(d, cells_w, cells_h, palette, zoom):
    """As the chip draws it: R/B/G the shared colours, W the cell's own."""
    shared = {"R": palette[0], "B": palette[1], "G": palette[2], "W": palette[3]}
    rows, modes = d["rows"], d["modes"]
    h, w = len(rows), cells_w * 8
    out = [bytearray(RGB[palette[0]] * (w * zoom)) for _ in range(h * zoom)]
    for y in range(h):
        for x in range(w):
            cy, cx = y // 8, x // 8
            mc = modes[cy * cells_w + cx] == "M"
            letter = rows[y][x]
            if not mc and letter not in ("R", "W"):      # a hires cell has two colours
                letter = "W" if letter in ("B", "G") else "R"
            col = shared[letter]
            r, g, b = RGB[col]
            for zy in range(zoom):
                line = out[y * zoom + zy]
                for zx in range(zoom):
                    p = x * zoom + zx
                    line[3 * p:3 * p + 3] = bytes((r, g, b))
    return w * zoom, h * zoom, out


def main():
    path, out = sys.argv[1], sys.argv[2]
    zoom = int(sys.argv[sys.argv.index("--zoom") + 1]) if "--zoom" in sys.argv else 10
    pal = [int(v) for v in sys.argv[sys.argv.index("--palette") + 1].split(",")] \
        if "--palette" in sys.argv else [12, 9, 5, 1]
    designs = read_designs(path)
    sheets, names = [], []
    for d in designs:
        problems, cw, ch = check(d)
        chars = encode(d, cw, ch)
        uniq = len({tuple(b) for _, _, _, b in chars})
        print(f"{d['name']}: {cw}x{ch} cells, {len(chars)} characters, {uniq} of them different"
              + (f"; {len(problems)} problems" if problems else "; the chip can show it"))
        for p in problems[:4]:
            print(f"   {p}")
        if "--bytes" in sys.argv:
            for cx, cy, mode, byts in chars:
                print(f"   cell {cx},{cy} {mode}: " + " ".join(f"${b:02X}" for b in byts))
        sheets.append(render(d, cw, ch, pal, zoom))
        names.append(d["name"])
    gap = 8 * zoom // 2
    height = max(s[1] for s in sheets)
    width = sum(s[0] for s in sheets) + gap * (len(sheets) - 1)
    rows = [bytearray(bytes((0, 0, 0)) * width) for _ in range(height)]
    x = 0
    for w, h, px in sheets:
        for y in range(h):
            rows[y][3 * x:3 * (x + w)] = px[y]
        x += w + gap
    write_png(out, width, height, rows)
    print(f"{out}: {len(sheets)} designs at {zoom}x ({width}x{height})")


if __name__ == "__main__":
    main()
