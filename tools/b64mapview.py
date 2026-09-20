#!/usr/bin/env python3
"""Render a tileset's metatiles as the VIC-II would show them.

A preview for judging playfield art without starting the emulator: it reads
a tileset straight from tools/b64tileset.py, lays out a demonstration city
(or a piece of the real world map) and writes a PNG.  The arithmetic is the
chip's: a multicolour cell takes three shared colours and one of its own; a
cell whose colour is under 8 is drawn in hires instead, two colours at full
horizontal resolution.

usage: b64mapview.py <tileset> <out.png> [--zoom 3] [--demo flat|reveal]
       b64mapview.py <tileset> <out.png> --world build/world.map --at 1300,1000 --size 12x8
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from b64palette import RGB  # noqa: E402
from b64png import write_png  # noqa: E402
import b64tileset  # noqa: E402


def render_map(ts, grid, zoom, bands=None):
    """grid: rows of metatile ids.  bands: (first row in pixels, (bg0, bg1,
    bg2)) pairs, as a raster split would set them."""
    shared0 = ts.bg
    gh, gw = len(grid), max(len(r) for r in grid)
    w, h = gw * 32 * zoom, gh * 32 * zoom

    def shared(y):
        out = shared0
        for start, cols in (bands or ()):
            if y >= start:
                out = cols
        return out

    rows = [bytearray(RGB[shared(y // zoom)[0]] * w) for y in range(h)]
    for gy, line in enumerate(grid):
        for gx, mt in enumerate(line):
            cells, cols, _ = ts.metatiles[mt]
            for cy in range(4):
                for cx in range(4):
                    bits = ts.order[cells[cy * 4 + cx]]
                    col = cols[cy * 4 + cx]
                    for r in range(8):
                        y = gy * 32 + cy * 8 + r
                        sh = shared(y)
                        b = bits[r]
                        for i in range(4):          # multicolour: four double pixels
                            v = (b >> (6 - 2 * i)) & 3
                            if col >= 8:
                                c = sh[v] if v < 3 else (col & 7)
                            else:                   # hires: two colours, eight pixels
                                c = None
                            if c is None:
                                continue
                            px = gx * 32 + cx * 8 + i * 2
                            r8, g8, b8 = RGB[c]
                            for zy in range(zoom):
                                row = rows[y * zoom + zy]
                                for zx in range(2 * zoom):
                                    p = px * zoom + zx
                                    row[3 * p:3 * p + 3] = bytes((r8, g8, b8))
                        if col < 8:                 # hires cell: one bit a pixel
                            for i in range(8):
                                c = (col & 7) if (b >> (7 - i)) & 1 else sh[0]
                                px = gx * 32 + cx * 8 + i
                                r8, g8, b8 = RGB[c]
                                for zy in range(zoom):
                                    row = rows[y * zoom + zy]
                                    for zx in range(zoom):
                                        p = px * zoom + zx
                                        row[3 * p:3 * p + 3] = bytes((r8, g8, b8))
    return w, h, rows


def block(grid, mt, x, y, w, h, storeys, style):
    """One building on its plot, drawn the way its style tells height.  The
    roof is w by h metatiles with its north-west corner at (x, y); storeys
    picks the depth class (short, medium, tall)."""
    reach = 1 if storeys <= 4 else (2 if storeys <= 9 else 3)
    tag = {1: "low", 2: "mid", 3: "high"}[reach]

    def roof(x0, y0, w0, h0, north=("roof_nw", "roof_n", "roof_ne"),
             middle=("roof_w", "roof_mid", "roof_e"), south=("roof_sw", "roof_s", "roof_se")):
        for j in range(h0):
            row = north if j == 0 else (south if j == h0 - 1 else middle)
            for i in range(w0):
                name = row[0] if i == 0 else (row[2] if i == w0 - 1 else row[1])
                put(grid, mt[name], x0 + i, y0 + j)

    def shade(cells):
        for k in range(1, reach + 1):
            for (i, j) in cells:
                put(grid, mt["shadow"], i + k, j + k)

    cells = [(x + i, y + j) for j in range(h) for i in range(w)]
    if style == "flat":
        shade(cells)
        roof(x, y, w, h)
    elif style == "reveal":
        shade([(i, j + 1) for (i, j) in cells])          # behind the faces
        roof(x, y, w, h, south=("roof_w", "roof_mid", "roof_e"))
        for i in range(w):
            put(grid, mt[f"front_{tag}"], x + i, y + h)
        for j in range(h):
            put(grid, mt[f"side_{tag}"], x + w, y + j)
        put(grid, mt[f"corner_{tag}"], x + w, y + h)
    elif style == "tiers":
        shade(cells)
        roof(x, y, w, h)
        for t in range(1, reach):                        # a setback every tier
            tx, ty, tw, th = x + t, y + t, w - 2 * t, h - 2 * t
            if tw < 1 or th < 1:
                break
            roof(tx, ty, tw, th, north=("step_nw", "step_n", "step_n"),
                 middle=("step_w", "roof_mid", "roof_e"),
                 south=("step_w", "roof_s", "roof_se"))
    elif style == "bands":
        shade(cells)
        roof(x, y, w, h, south=("roof_w", "roof_mid", "roof_e"))
        for i in range(w):
            put(grid, mt[f"bands_{tag}"], x + i, y + h)
    elif style == "cut":
        shade(cells)
        roof(x, y, w, h, south=("roof_w", "roof_mid", "roof_e"))
        for i in range(w):
            put(grid, mt[f"cut_{tag}"], x + i, y + h)
    if storeys >= 6:                                     # something on the roof
        put(grid, mt["roof_ac"], x + (w - 1 if w > 1 else 0), y)
    if storeys >= 10 and h > 1:
        put(grid, mt["roof_vent"], x, y + 1)


def put(grid, v, x, y):
    if 0 <= y < len(grid) and 0 <= x < len(grid[0]):
        grid[y][x] = v


def demo_city(ts, style):
    """The reference's layout: a block between two streets, three buildings
    of different heights on grass, pavement around the block."""
    mt = ts.names
    W_, H_ = 20, 13
    grid = [[mt["grass"]] * W_ for _ in range(H_)]
    for x in range(W_):                             # streets north and south
        grid[0][x] = grid[1][x] = mt["road_h"]
        grid[H_ - 2][x] = grid[H_ - 1][x] = mt["road_h"]
    for y in range(H_):                             # and one down each side
        grid[y][0] = grid[y][1] = mt["road_v"]
        grid[y][W_ - 2] = grid[y][W_ - 1] = mt["road_v"]
    for x in range(W_):
        for y in (0, 1, H_ - 2, H_ - 1):
            if x in (0, 1, W_ - 2, W_ - 1):
                grid[y][x] = mt["cross"]
    for x in range(2, W_ - 2):                      # the pavement around the block
        grid[2][x] = grid[H_ - 3][x] = mt["sidewalk"]
    for y in range(2, H_ - 2):
        grid[y][2] = grid[y][W_ - 3] = mt["sidewalk"]
    for tx, ty in ((3, 3), (8, 3), (13, 3), (5, 9), (11, 9), (16, 6)):
        if "grass_tree" in mt:                      # trees on the plots
            put(grid, mt["grass_tree"], tx, ty)
    block(grid, mt, 4, 4, 3, 2, 3, style)           # short
    block(grid, mt, 9, 4, 3, 3, 8, style)           # medium
    block(grid, mt, 14, 4, 2, 4, 16, style)         # tall
    return grid


def sheet(out, zoom):
    """Every style, the same three buildings, one above another."""
    styles = ("flat", "reveal", "tiers", "bands", "cut")
    blocks = []
    for st in styles:
        ts = b64tileset.TILESETS[f"bellamar_{st}"]()
        ts.pack()
        w, h, rows = render_map(ts, demo_city(ts, st), zoom)
        blocks.append((w, h, rows))
    W_ = max(b[0] for b in blocks)
    rows = []
    for w, h, r in blocks:
        rows += r
        rows += [bytearray(bytes((0, 0, 0)) * W_) for _ in range(4 * zoom)]
    write_png(out, W_, len(rows), rows)
    print(f"{out}: {', '.join(styles)}, {W_}x{len(rows)} at {zoom}x")


def main():
    name, out = sys.argv[1], sys.argv[2]
    zoom = int(sys.argv[sys.argv.index("--zoom") + 1]) if "--zoom" in sys.argv else 3
    style = sys.argv[sys.argv.index("--demo") + 1] if "--demo" in sys.argv else "flat"
    ts = b64tileset.TILESETS[name]()
    ts.pack()                                       # assign codes, so colours are final
    if "--sheet" in sys.argv:
        sheet(out, zoom)
        return
    if "--world" in sys.argv:
        world = open(sys.argv[sys.argv.index("--world") + 1], "rb").read()
        ax, ay = (int(v) for v in sys.argv[sys.argv.index("--at") + 1].split(","))
        gw, gh = (int(v) for v in sys.argv[sys.argv.index("--size") + 1].split("x"))
        grid = [[world[((ay + j) << 11) | (ax + i)] for i in range(gw)] for j in range(gh)]
    else:
        grid = demo_city(ts, style)
    w, h, rows = render_map(ts, grid, zoom)
    write_png(out, w, h, rows)
    print(f"{out}: {name}, {len(grid[0])}x{len(grid)} metatiles, {w}x{h} at {zoom}x")


if __name__ == "__main__":
    main()
