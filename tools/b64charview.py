#!/usr/bin/env python3
"""Show single characters of a tileset, big, as the VIC-II draws them.

For working through a character set one tile at a time (2026-09-19): it
takes names from a tileset's character set, renders each at whatever zoom,
and writes a PNG with the characters side by side on black.  A multicolour
character is four double-wide pixels across, three shared colours and one
of its own; a hires character is eight pixels, the shared background and
one colour.

usage: b64charview.py <out.png> <name> [<name> ...] [--zoom 24] [--set city]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from b64palette import RGB  # noqa: E402
from b64png import write_png  # noqa: E402
import b64tileset  # noqa: E402

SETS = {"city": (b64tileset.city_chars, (0, 12, 15))}   # black, mid grey, light grey


def swatch(ch, shared, zoom, pad):
    """One character as rows of RGB, with a border of the page's black."""
    size = 8 * zoom
    rows = [bytearray(RGB[0] * (size + 2 * pad)) for _ in range(size + 2 * pad)]
    for y in range(8):
        for x in range(ch.w):
            v = ch.px[y][x]
            if ch.mc:
                col = shared[v] if v < 3 else ch.colour
                wide = 2
            else:
                col = ch.colour if v else shared[0]
                wide = 1
            r, g, b = RGB[col]
            for zy in range(zoom):
                row = rows[pad + y * zoom + zy]
                for zx in range(wide * zoom):
                    p = pad + (x * wide) * zoom + zx
                    row[3 * p:3 * p + 3] = bytes((r, g, b))
    return rows


def building(chars, shared, w, h, zoom, ground="grass"):
    """A building w by h characters, from the roof's edge set, standing on
    the ground: the way the reference sheets build one."""
    pad = 2
    W_, H_ = w + 2 * pad, h + 2 * pad
    grid = [[("grass", "grass1", "grass2", "grass3")[((x * 11) ^ (y * 5)) % 4] for x in range(W_)]
            for y in range(H_)]
    for j in range(h):
        for i in range(w):
            ns = "corner" if (j in (0, h - 1) and i in (0, w - 1)) else None
            if ns:
                name = f"corner_{'n' if j == 0 else 's'}{'w' if i == 0 else 'e'}"
            elif j == 0:
                name = "edge_n"
            elif j == h - 1:
                name = "edge_s"
            elif i == 0:
                name = "edge_w"
            elif i == w - 1:
                name = "edge_e"
            else:                                    # the fills, picked by place
                name = ("fill", "fill1", "fill2", "fill3")[((i * 7) ^ (j * 13)) % 4]
            grid[pad + j][pad + i] = name
    grid[pad + 1][pad + w - 2] = "ac" if w > 3 and h > 3 else grid[pad + 1][pad + w - 2]
    rows = [bytearray(RGB[shared[0]] * (W_ * 8 * zoom)) for _ in range(H_ * 8 * zoom)]
    for gy, line in enumerate(grid):
        for gx, name in enumerate(line):
            ch = chars[name]
            for y in range(8):
                for x in range(ch.w):
                    v = ch.px[y][x]
                    col = (shared[v] if v < 3 else ch.colour) if ch.mc else (ch.colour if v else shared[0])
                    wide = 2 if ch.mc else 1
                    r, g, b = RGB[col]
                    for zy in range(zoom):
                        row = rows[(gy * 8 + y) * zoom + zy]
                        for zx in range(wide * zoom):
                            p = (gx * 8 + x * wide) * zoom + zx
                            row[3 * p:3 * p + 3] = bytes((r, g, b))
    return W_ * 8 * zoom, H_ * 8 * zoom, rows


def main():
    out = sys.argv[1]
    flags = {"--zoom", "--set", "--building"}
    names, skip = [], False
    for a in sys.argv[2:]:                          # names, minus the flags and their values
        if skip:
            skip = False
            continue
        if a in flags:
            skip = True
            continue
        if not a.startswith("--"):
            names.append(a)
    zoom = int(sys.argv[sys.argv.index("--zoom") + 1]) if "--zoom" in sys.argv else 24
    which = sys.argv[sys.argv.index("--set") + 1] if "--set" in sys.argv else "city"
    chars, shared = SETS[which]
    chars = chars()
    if "--building" in sys.argv:
        spec = sys.argv[sys.argv.index("--building") + 1]
        bw, bh = (int(v) for v in spec.split("x"))
        w, h, rows = building(chars, shared, bw, bh, zoom)
        write_png(out, w, h, rows)
        print(f"{out}: a building {bw}x{bh} characters at {zoom}x ({w}x{h})")
        return
    pad = zoom
    tiles = [swatch(chars[n], shared, zoom, pad) for n in names]
    h = len(tiles[0])
    w = sum(len(t[0]) // 3 for t in tiles)
    rows = [bytearray() for _ in range(h)]
    for t in tiles:
        for y in range(h):
            rows[y] += t[y]
    write_png(out, w, h, rows)
    print(f"{out}: {', '.join(names)} at {zoom}x ({w}x{h})")


if __name__ == "__main__":
    main()
