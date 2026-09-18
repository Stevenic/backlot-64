#!/usr/bin/env python3
"""Quantise any PNG into a legal C64 picture and render what the chip shows.

    b64quant.py block <in.png> <out.png> [cells_w cells_h]   default 16 12
    b64quant.py still <in.png> <out.png> [--bin out.bin]
    b64quant.py bblock <in.png> <out.png> cells_w cells_h --bg <colour> [--bin out.bin]
    b64quant.py sprites <in.png> <out.png> grid_w grid_h --colours mc0,ind,mc1 [--bin out.spr]

still --bin writes VIC data: 1 byte background, 8000 bitmap, 1000 screen,
1000 colour RAM, padded to 10240.  bblock writes a block in bitmap layout for
blitting into a still that shares its background: w, h, then per cell row
w*8 bitmap bytes, then w*h screen bytes, then w*h colour bytes.  sprites
writes grid_w*grid_h multicolour sprite frames (64 bytes each, row-major)
with the edge-connected background made transparent.

block: multicolour character block.  Three shared colours (chosen as the
three most used) plus one per-cell colour from the first eight of the
palette.  Output is cells_w*4 x cells_h*8 multicolour pixels.

still: multicolour bitmap.  One shared background (the most used colour)
plus three per-cell colours from all sixteen.  160x200 multicolour pixels.

Uses sips (macOS) to crop and resample, so it needs no image libraries.
Writes <out.png> at 2x and <out>.json with the palette choices and how many
cells had to be fixed.
"""
import json
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from b64palette import RGB, write_png, COLOUR_NAMES  # noqa: E402
from b64tileset import LUMA  # noqa: E402
from b64formats import Pix  # noqa: E402
import copy
import itertools

CELL_COLOURS = set(range(8))
GREYS = {0, 1, 11, 12, 15}


def remap(c, allowed):
    """Nearest allowed colour.  A grey maps to the nearest grey by brightness
    if the cell has one, so shading never turns into a hue."""
    if c in GREYS:
        greys = [a for a in allowed if a in GREYS]
        if greys:
            return min(greys, key=lambda a: abs(LUMA[a] - LUMA[c]))
    return min(allowed, key=lambda a: dist(a, c) + 4000 * abs(LUMA[a] - LUMA[c]))


def bmp_pixels(path, w, h):
    """Crop to w:h aspect (centred), resample to w x h, return rows of RGB."""
    tmp = tempfile.mktemp(suffix=".bmp")
    # sips: crop to the target aspect using the source's larger dimension, then resample
    info = subprocess.check_output(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path]).decode()
    sw = int(info.split("pixelWidth:")[1].split()[0])
    sh = int(info.split("pixelHeight:")[1].split()[0])
    if sw * h > sh * w:           # source is wider than target: crop width
        cw, ch = sh * w // h, sh
    else:
        cw, ch = sw, sw * h // w
    # sips misapplies -c and -z when combined, so crop to a temp PNG first, then resample
    tmp_png = tempfile.mktemp(suffix=".png")
    subprocess.check_call(["sips", "-c", str(ch), str(cw), path, "--out", tmp_png],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.check_call(["sips", "-z", str(h), str(w), "-s", "format", "bmp", tmp_png, "--out", tmp],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.unlink(tmp_png)
    with open(tmp, "rb") as f:
        data = f.read()
    os.unlink(tmp)
    off = struct.unpack_from("<I", data, 10)[0]
    bw, bh = struct.unpack_from("<ii", data, 18)
    bpp = struct.unpack_from("<H", data, 28)[0]
    assert bpp in (24, 32), f"unexpected bmp depth {bpp}"
    step = bpp // 8
    stride = (bw * step + 3) & ~3
    flip = bh > 0
    bh = abs(bh)
    rows = []
    for y in range(bh):
        src = bh - 1 - y if flip else y
        base = off + src * stride
        row = []
        for x in range(bw):
            b, g, r = data[base + x * step], data[base + x * step + 1], data[base + x * step + 2]
            row.append((r, g, b))
        rows.append(row)
    return rows


def nearest(rgb):
    """Nearest palette colour by weighted RGB.  Low-saturation pixels only
    map to the five greys, so warm or cool highlights never pick up a hue."""
    r, g, b = rgb
    cands = GREYS if max(rgb) - min(rgb) < 40 else range(16)
    best, bd = 0, 1e12
    for i in cands:
        pr, pg, pb = RGB[i]
        d = 0.30 * (r - pr) ** 2 + 0.59 * (g - pg) ** 2 + 0.11 * (b - pb) ** 2
        if d < bd:
            best, bd = i, d
    return best


# blend pairs: two colours within 3 luminance steps, drawn as a checkerboard,
# read as their average on a CRT (docs/ART.md)
BLENDS = [(a, b) for a in range(16) for b in range(a + 1, 16) if abs(LUMA[a] - LUMA[b]) <= 3]
BLEND_RGB = [tuple((RGB[a][i] + RGB[b][i]) // 2 for i in range(3)) for (a, b) in BLENDS]


def wdist(rgb, q):
    return 0.30 * (rgb[0] - q[0]) ** 2 + 0.59 * (rgb[1] - q[1]) ** 2 + 0.11 * (rgb[2] - q[2]) ** 2


def nearest_blend(rgb):
    best, bd = None, 1e12
    grey_only = max(rgb) - min(rgb) < 40
    for k, (a, b) in enumerate(BLENDS):
        if grey_only and not (a in GREYS and b in GREYS):
            continue
        d = wdist(rgb, BLEND_RGB[k])
        if d < bd:
            best, bd = (a, b), d
    return best, bd


def to_pix(rows, fat_w, h, blends=False):
    """Average horizontal pairs into multicolour pixels and map to the palette.
    With blends on, a pixel whose colour is much closer to a two-colour
    checkerboard than to any solid is drawn as that checkerboard."""
    p = Pix(fat_w, h, 0)
    for y in range(h):
        for x in range(fat_w):
            a, b = rows[y][2 * x], rows[y][2 * x + 1]
            rgb = tuple((a[i] + b[i]) // 2 for i in range(3))
            c = nearest(rgb)
            if blends:
                ds = wdist(rgb, RGB[c])
                pair, dp = nearest_blend(rgb)
                # only where the best solid is a poor match and the blend is much better
                if pair and ds > 900 and dp < 0.35 * ds:
                    c = pair[(x + y) & 1]
            p.p[y][x] = c
    return p


def histogram(p):
    h = {}
    for row in p.p:
        for c in row:
            h[c] = h.get(c, 0) + 1
    return h


DAMAGE = [0]


def quantise_cells(p, fixed, extra, extra_ok):
    """Per 4x8 cell: keep `fixed` colours plus up to `extra` others that pass
    extra_ok; remap the rest to the nearest kept colour.  DAMAGE[0] collects
    a visual cost: 1 per grey-to-grey change, 8 per change of hue."""
    fixed_cells = 0
    DAMAGE[0] = 0
    for cy in range(0, p.h, 8):
        for cx in range(0, p.w, 4):
            counts = {}
            for yy in range(cy, cy + 8):
                for xx in range(cx, cx + 4):
                    c = p.p[yy][xx]
                    if c not in fixed:
                        counts[c] = counts.get(c, 0) + 1
            cands = [c for c in sorted(counts, key=lambda c: -counts[c]) if extra_ok(c)]
            keep = cands[:extra]
            allowed = list(fixed) + keep
            bad = [c for c in counts if c not in keep]
            if not bad:
                continue
            fixed_cells += 1
            for yy in range(cy, cy + 8):
                for xx in range(cx, cx + 4):
                    c = p.p[yy][xx]
                    if c not in allowed:
                        n = remap(c, allowed)
                        DAMAGE[0] += 1 if (c in GREYS and n in GREYS) else 8
                        p.p[yy][xx] = n
    return fixed_cells


def best_trio(p, extra_ok):
    """Try every trio drawn from the six most used colours and keep the one
    that leaves the fewest cells needing repair."""
    hist = histogram(p)
    top = [c for c in sorted(hist, key=lambda c: -hist[c])][:6]
    best, best_score = None, None
    for trio in itertools.combinations(top, 3):
        trial = copy.deepcopy(p)
        quantise_cells(trial, set(trio), 1, extra_ok)
        score = DAMAGE[0]
        if best_score is None or score < best_score:
            best, best_score = trio, score
    return list(best)


def dist(a, b):
    return sum((RGB[a][i] - RGB[b][i]) ** 2 for i in range(3))


# ---------------------------------------------------------------------------
# VIC data exports
# ---------------------------------------------------------------------------
def cell_codes(p, cx, cy, bg):
    """Assign the cell's up to three non-background colours to bit pairs
    01 (screen hi nibble), 10 (screen lo nibble), 11 (colour RAM)."""
    counts = {}
    for yy in range(cy * 8, cy * 8 + 8):
        for xx in range(cx * 4, cx * 4 + 4):
            c = p.p[yy][xx]
            if c != bg:
                counts[c] = counts.get(c, 0) + 1
    order = sorted(counts, key=lambda c: -counts[c])[:3]
    while len(order) < 3:
        order.append(order[-1] if order else bg)
    codes = {bg: 0, order[0]: 1, order[1]: 2, order[2]: 3}
    return codes, order


def export_bitmap(p, bg, cw, ch):
    """Return (bitmap, screen, colour) bytes for a ch x cw cell region of p."""
    bitmap, screen, colour = bytearray(), bytearray(), bytearray()
    for cy in range(ch):
        for cx in range(cw):
            codes, order = cell_codes(p, cx, cy, bg)
            for r in range(8):
                b = 0
                for i in range(4):
                    b |= codes.get(p.p[cy * 8 + r][cx * 4 + i], 0) << (6 - 2 * i)
                bitmap.append(b)
            screen.append((order[0] << 4) | order[1])
            colour.append(order[2])
    return bitmap, screen, colour


def shimmer_cells(p, bg, horizon):
    """Cells below `horizon` (a cell row) that hold a dithered mix of two
    non-background colours: candidates for the engine's shimmer, which swaps
    the two colours' codes every few frames so the reflection moves."""
    out = []
    for cy in range(horizon, 25):
        for cx in range(40):
            counts = {}
            for y in range(cy * 8, cy * 8 + 8):
                for x in range(cx * 4, cx * 4 + 4):
                    c = p.p[y][x]
                    if c != bg:
                        counts[c] = counts.get(c, 0) + 1
            # the two colours that share the cell's first two codes must both be
            # present in quantity, so swapping them moves something visible
            top = sorted(counts.values(), reverse=True)
            if len(top) >= 2 and top[0] >= 6 and top[1] >= 6:
                out.append((cx, cy))
    return out[:119]


def write_still_bin(p, bg, path, horizon=None):
    bitmap, screen, colour = export_bitmap(p, bg, 40, 25)
    blob = bytes([bg]) + bitmap + screen + colour
    # shimmer list in the padding: count, then 16-bit cell indices
    cells = shimmer_cells(p, bg, horizon) if horizon is not None else []
    blob += bytes([len(cells)]) + b"".join(bytes([cx, cy]) for (cx, cy) in cells)
    blob += bytes(10240 - len(blob))
    with open(path, "wb") as f:
        f.write(blob)
    return len(cells)


def write_bblock_bin(p, bg, cw, ch, path):
    bitmap, screen, colour = export_bitmap(p, bg, cw, ch)
    with open(path, "wb") as f:
        f.write(bytes([cw, ch]) + bitmap + screen + colour)


def sprite_grid(p, gw, gh, mc0, ind, mc1, transparent):
    """Encode p (12*gw x 21*gh fat px) as gw*gh multicolour sprites.
    Colour values: 00 transparent, 01 mc0, 10 individual, 11 mc1."""
    code = {mc0: 1, ind: 2, mc1: 3}
    out = bytearray()
    for gy in range(gh):
        for gx in range(gw):
            for r in range(21):
                y = gy * 21 + r
                for byte in range(3):
                    b = 0
                    for i in range(4):
                        x = gx * 12 + byte * 4 + i
                        c = p.p[y][x]
                        v = 0 if transparent[y][x] else code.get(c, 0)
                        b |= v << (6 - 2 * i)
                    out.append(b)
            out.append(0)
    return bytes(out)


def edge_fill(p, bg):
    """Cells of colour bg reachable from the image edge become transparent."""
    w, h = p.w, p.h
    seen = [[False] * w for _ in range(h)]
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while stack:
        x, y = stack.pop()
        if not (0 <= x < w and 0 <= y < h) or seen[y][x] or p.p[y][x] != bg:
            continue
        seen[y][x] = True
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return seen


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = {a.split("=")[0][2:]: a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--") and "=" in a}
    mode, src, out = args[0], args[1], args[2]
    if mode == "bblock":
        cw, ch = int(args[3]), int(args[4])
        bg = COLOUR_NAMES.index(opts.get("bg", "black"))
        fat_w, h = cw * 4, ch * 8
        rows = bmp_pixels(src, fat_w * 2, h)
        p = to_pix(rows, fat_w, h, blends=True)
        fixed = quantise_cells(p, {bg}, 3, lambda c: True)
        meta = {"mode": "bblock", "cells": [cw, ch], "background": COLOUR_NAMES[bg],
                "cells_fixed": fixed, "cells_total": cw * ch, "damage": DAMAGE[0]}
        if "bin" in opts:
            write_bblock_bin(p, bg, cw, ch, opts["bin"])
        write_png(out, p.render(2))
        print(json.dumps(meta))
        return
    if mode == "sprites":
        gw, gh = int(args[3]), int(args[4])
        names = opts.get("colours", "black,white,blue").split(",")
        mc0, ind, mc1 = (COLOUR_NAMES.index(n) for n in names)
        fat_w, h = gw * 12, gh * 21
        rows = bmp_pixels(src, fat_w * 2, h)
        p = to_pix(rows, fat_w, h)
        # every pixel becomes one of the three sprite colours or the transparent key
        key = p.p[0][0]
        trans = edge_fill(p, key)
        for y in range(h):
            for x in range(fat_w):
                if not trans[y][x] and p.p[y][x] not in (mc0, ind, mc1):
                    p.p[y][x] = remap(p.p[y][x], [mc0, ind, mc1])
        if "bin" in opts:
            with open(opts["bin"], "wb") as f:
                f.write(sprite_grid(p, gw, gh, mc0, ind, mc1, trans))
        for y in range(h):
            for x in range(fat_w):
                if trans[y][x]:
                    p.p[y][x] = 11      # show transparency as dark grey in the preview
        write_png(out, p.render(2))
        print(json.dumps({"mode": "sprites", "grid": [gw, gh], "frames": gw * gh, "colours": names}))
        return
    mode, src, out = sys.argv[1], sys.argv[2], sys.argv[3]
    if mode == "block":
        cw, ch = (int(sys.argv[4]), int(sys.argv[5])) if len(sys.argv) > 5 else (16, 12)
        fat_w, h = cw * 4, ch * 8
        rows = bmp_pixels(src, fat_w * 2, h)
        p = to_pix(rows, fat_w, h)
        shared = best_trio(p, lambda c: c in CELL_COLOURS)
        fixed = quantise_cells(p, set(shared), 1, lambda c: c in CELL_COLOURS)
        meta = {"mode": "block", "cells": [cw, ch], "shared": [COLOUR_NAMES[c] for c in shared],
                "cells_fixed": fixed, "cells_total": cw * ch, "damage": DAMAGE[0]}
    elif mode == "still":
        fat_w, h = 160, 200
        rows = bmp_pixels(src, 320, 200)
        p = to_pix(rows, fat_w, h, blends=True)
        hist = histogram(p)
        bg = max(hist, key=lambda c: hist[c])
        fixed = quantise_cells(p, {bg}, 3, lambda c: True)
        meta = {"mode": "still", "background": COLOUR_NAMES[bg], "cells_fixed": fixed, "cells_total": 1000,
                "damage": DAMAGE[0]}
        if "bin" in opts:
            horizon = int(opts["shimmer-from"]) if "shimmer-from" in opts else None
            n = write_still_bin(p, bg, opts["bin"], horizon)
            meta["shimmer_cells"] = n
    else:
        raise SystemExit("mode must be block or still")
    write_png(out, p.render(2))
    with open(os.path.splitext(out)[0] + ".json", "w") as f:
        json.dump(meta, f, indent=1)
    print(json.dumps(meta))


if __name__ == "__main__":
    main()
