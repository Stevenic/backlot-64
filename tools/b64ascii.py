#!/usr/bin/env python3
"""The city drawn in text, the way PETSCII art does it.

An exploration asked for 2026-09-19: what if the playfield were characters
rather than pictures?  In hires text mode every 8x8 cell shows one glyph in
any of the sixteen colours over a shared background, at full horizontal
resolution -- 320 pixels across, not 160.  The trade against multicolour is
exact: a cell gets one colour instead of four, but it gets twice the
horizontal detail and its colour may be any of the sixteen rather than the
first eight.

The glyphs below are the PETSCII vocabulary: blocks and half blocks,
shades, box lines and corners, and a few marks.  A game could use the ROM
font and spend nothing on a charset at all.

With --mono the city is drawn in one colour on black -- the whole playfield
monochrome, as a printed map or a blueprint -- and the only colour on screen
belongs to the sprites: the cars and the people.  That costs the engine
less than anything else here, because colour RAM never changes: the
scroller moves screen codes and nothing else.

usage: b64ascii.py <out.png> [--zoom 3] [--night] [--mono]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from b64palette import RGB  # noqa: E402
from b64png import write_png  # noqa: E402
from b64art import (  # noqa: E402
    BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW,
    ORANGE, BROWN, PINK, DGRAY, MGRAY, LGREEN, LBLUE, LGRAY,
    car_frames_mc, ped_frames_mc,
)

W_CELLS, H_CELLS = 40, 25


def glyphs():
    """PETSCII-ish characters as eight bytes each."""
    g = {}
    g[" "] = [0x00] * 8
    g["full"] = [0xFF] * 8
    g["upper"] = [0xFF] * 4 + [0x00] * 4
    g["lower"] = [0x00] * 4 + [0xFF] * 4
    g["left"] = [0xF0] * 8
    g["right"] = [0x0F] * 8
    g["shade1"] = [0x88, 0x00, 0x22, 0x00] * 2            # a quarter lit
    g["shade2"] = [0xAA, 0x55] * 4                        # half, chequered
    g["shade3"] = [0xDD, 0xFF, 0x77, 0xFF] * 2            # three quarters
    g["hline"] = [0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00]
    g["vline"] = [0x18] * 8
    g["tl"] = [0x00, 0x00, 0x00, 0x1F, 0x18, 0x18, 0x18, 0x18]
    g["tr"] = [0x00, 0x00, 0x00, 0xF8, 0x18, 0x18, 0x18, 0x18]
    g["bl"] = [0x18, 0x18, 0x18, 0x1F, 0x00, 0x00, 0x00, 0x00]
    g["br"] = [0x18, 0x18, 0x18, 0xF8, 0x00, 0x00, 0x00, 0x00]
    g["cross"] = [0x18, 0x18, 0x18, 0xFF, 0x18, 0x18, 0x18, 0x18]
    g["dot"] = [0x00, 0x00, 0x18, 0x3C, 0x3C, 0x18, 0x00, 0x00]
    g["tiny"] = [0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00]
    g["win"] = [0x00, 0x7E, 0x42, 0x42, 0x42, 0x42, 0x7E, 0x00]
    g["win2"] = [0x00, 0x6C, 0x6C, 0x00, 0x6C, 0x6C, 0x00, 0x00]
    g["door"] = [0x00, 0x3C, 0x7E, 0x7E, 0x7E, 0x7E, 0x7E, 0x00]
    g["tree"] = [0x18, 0x3C, 0x7E, 0xFF, 0x7E, 0x3C, 0x18, 0x18]
    g["grass"] = [0x00, 0x00, 0x00, 0x00, 0x44, 0x00, 0x11, 0x00]
    g["dash"] = [0x00, 0x00, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x00]
    g["car_h"] = [0x00, 0x00, 0x7E, 0xFF, 0xFF, 0x7E, 0x00, 0x00]
    g["car_v"] = [0x00, 0x3C, 0x7E, 0x7E, 0x7E, 0x7E, 0x3C, 0x00]
    g["sign"] = [0x00, 0xFF, 0x81, 0xBD, 0xBD, 0x81, 0xFF, 0x00]
    g["awning"] = [0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    g["kerb"] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF]
    g["kerb_up"] = [0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    g["ped"] = [0x18, 0x18, 0x3C, 0x5A, 0x18, 0x24, 0x24, 0x00]
    return g


def city_mono(g):
    """The city in one colour on black: the playfield as a printed map.
    Every cell is the same colour, so colour RAM never changes and the
    scroller has nothing to move but screen codes."""
    ink = WHITE
    grid = [[(" ", ink) for _ in range(W_CELLS)] for _ in range(H_CELLS)]

    def put(x, y, name):
        if 0 <= x < W_CELLS and 0 <= y < H_CELLS:
            grid[y][x] = (name, ink)

    for y in range(H_CELLS):                              # open ground: a regular grain,
        for x in range(W_CELLS):                          # like a parking apron, not a starfield
            put(x, y, "tiny" if (x % 4 == 2 and y % 3 == 1) else " ")
    for y in range(11, 16):                               # the road: black, with markings
        for x in range(W_CELLS):
            put(x, y, " ")
    for x in range(W_CELLS):
        put(x, 11, "kerb"); put(x, 15, "kerb_up")
        if x % 3 == 0:
            put(x, 13, "dash")
    for x in range(W_CELLS):                              # pavements, a dotted band
        put(x, 10, "shade1"); put(x, 16, "shade1")
    for x in range(0, W_CELLS, 6):                        # street lamps along them
        put(x, 9, "dot"); put(x, 17, "dot")
    for x in (8, 9, 27, 28):
        for y in range(12, 15):
            put(x, y, "vline")

    def block(x, y, w, h, hatch="shade1"):
        for j in range(h):
            for i in range(w):
                put(x + i, y + j, hatch)
        for i in range(w):
            put(x + i, y, "hline"); put(x + i, y + h - 1, "hline")
        for j in range(h):
            put(x, y + j, "vline"); put(x + w - 1, y + j, "vline")
        put(x, y, "tl"); put(x + w - 1, y, "tr")
        put(x, y + h - 1, "bl"); put(x + w - 1, y + h - 1, "br")
        for j in range(1, h - 1):                         # windows as marks
            for i in range(1, w - 1):
                if (i + j) % 2:
                    put(x + i, y + j, "win" if (i * j) % 3 else "win2")

    block(1, 5, 7, 5); block(9, 4, 6, 6, "shade2"); block(16, 6, 5, 4)
    block(22, 3, 8, 7, "shade2"); block(31, 5, 7, 5)
    block(2, 17, 8, 5, "shade2"); block(12, 17, 6, 6); block(20, 18, 7, 4, "shade2")
    block(29, 17, 8, 5)
    for tx, ty in ((0, 3), (15, 2), (21, 1), (39, 8), (11, 23), (19, 16), (38, 20)):
        put(tx, ty, "tree")
    return grid, BLACK


def city(g, night=False):
    """A street of blocks: shopfronts with signs and windows, a road with
    lanes and crossings, pavements, trees, traffic.  Every cell is one
    glyph in one colour."""
    bg = BLACK
    grid = [[(" ", bg) for _ in range(W_CELLS)] for _ in range(H_CELLS)]

    def put(x, y, name, col):
        if 0 <= x < W_CELLS and 0 <= y < H_CELLS:
            grid[y][x] = (name, col)

    for y in range(H_CELLS):                              # ground: grass, filled so the
        for x in range(W_CELLS):                          # screen is a place, not a terminal
            n = (x * 7 + y * 3) % 6
            put(x, y, "shade3" if n < 3 else ("shade2" if n < 5 else "grass"),
                GREEN if n < 5 else LGREEN)

    for y in range(11, 16):                               # the road, dark but filled
        for x in range(W_CELLS):
            put(x, y, "shade3", DGRAY)
    for x in range(W_CELLS):
        put(x, 11, "kerb", MGRAY)
        put(x, 15, "kerb_up", MGRAY)
        if x % 3 == 0:
            put(x, 13, "dash", WHITE)
    for x in range(W_CELLS):                              # pavements
        put(x, 10, "shade3", LGRAY)
        put(x, 16, "shade3", LGRAY)
    for x in (8, 9, 27, 28):                              # crossings
        for y in range(11, 16):
            put(x, y, "vline", WHITE)

    def block(x, y, w, h, wall, sign_col, win_col, name=None):
        for j in range(h):
            for i in range(w):
                put(x + i, y + j, "full", wall)
        for i in range(w):                                # its edges, in box lines
            put(x + i, y, "hline", LGRAY)
            put(x + i, y + h - 1, "hline", LGRAY)
        for j in range(h):
            put(x, y + j, "vline", LGRAY)
            put(x + w - 1, y + j, "vline", LGRAY)
        put(x, y, "tl", LGRAY); put(x + w - 1, y, "tr", LGRAY)
        put(x, y + h - 1, "bl", LGRAY); put(x + w - 1, y + h - 1, "br", LGRAY)
        for j in range(1, h - 1):                         # windows, lit at night
            for i in range(1, w - 1):
                if (i + j) % 2:
                    put(x + i, y + j, "win" if (i * j) % 3 else "win2", win_col)
        if h > 2:                                         # a sign band along the front
            for i in range(1, w - 1):
                put(x + i, y + h - 2, "sign" if i % 2 else "awning", sign_col)
        if name and w > 3:
            put(x + w // 2, y + h - 1, "door", YELLOW if night else BROWN)

    win_day, win_night = LBLUE, YELLOW
    win = win_night if night else win_day
    block(1, 5, 7, 5, BROWN, RED, win, True)
    block(9, 4, 6, 6, MGRAY, CYAN, win, True)
    block(16, 6, 5, 4, PURPLE, YELLOW, win, True)
    block(22, 3, 8, 7, BROWN, CYAN, win, True)
    block(31, 5, 7, 5, DGRAY, PINK, win, True)
    block(2, 17, 8, 5, MGRAY, YELLOW, win, True)
    block(12, 17, 6, 6, BROWN, RED, win, True)
    block(20, 18, 7, 4, PURPLE, CYAN, win, True)
    block(29, 17, 8, 5, BROWN, LGREEN, win, True)

    for tx, ty in ((0, 3), (15, 2), (21, 1), (39, 8), (11, 23), (19, 16), (38, 20)):
        put(tx, ty, "tree", LGREEN if not night else GREEN)
    for x, y, col in ((5, 12, RED), (17, 14, CYAN), (33, 12, YELLOW), (24, 14, WHITE)):
        put(x, y, "car_h", col)                           # traffic, as characters
    for x, y, col in ((7, 10, WHITE), (19, 16, PINK), (30, 10, CYAN)):
        put(x, y, "ped", col)
    return grid, bg


def render(grid, g, bg, zoom):
    w, h = W_CELLS * 8 * zoom, H_CELLS * 8 * zoom
    rows = [bytearray(RGB[bg] * w) for _ in range(h)]
    for cy, line in enumerate(grid):
        for cx, (name, col) in enumerate(line):
            bits = g[name]
            for y in range(8):
                b = bits[y]
                for x in range(8):
                    c = col if (b >> (7 - x)) & 1 else bg
                    r, gg, bb = RGB[c]
                    for zy in range(zoom):
                        row = rows[(cy * 8 + y) * zoom + zy]
                        for zx in range(zoom):
                            p = (cx * 8 + x) * zoom + zx
                            row[3 * p:3 * p + 3] = bytes((r, gg, bb))
    return w, h, rows


def sprites_over(rows, zoom, h):
    """The only colour on the screen: cars and people, as sprites."""
    cars, peds = car_frames_mc(), ped_frames_mc()
    put = [(cars[1], 40, 100, RED), (cars[3], 150, 116, CYAN), (cars[1], 250, 100, YELLOW),
           (cars[3], 300, 116, LGREEN), (peds[0], 70, 84, PINK), (peds[1], 130, 132, ORANGE),
           (peds[0], 215, 84, CYAN), (peds[1], 290, 132, WHITE)]
    for frame, sx, sy, colour in put:
        for j, line in enumerate(frame):
            for i, ch in enumerate(line):
                if ch == ".":
                    continue
                col = {"1": BLACK, "2": colour, "3": WHITE}[ch]
                r, g, b = RGB[col]
                for zy in range(zoom):
                    yy = (sy + j) * zoom + zy
                    if not 0 <= yy < h:
                        continue
                    row = rows[yy]
                    for zx in range(2 * zoom):
                        p = (sx + 2 * i) * zoom + zx
                        if 0 <= 3 * p < len(row) - 3:
                            row[3 * p:3 * p + 3] = bytes((r, g, b))


def main():
    out = sys.argv[1]
    zoom = int(sys.argv[sys.argv.index("--zoom") + 1]) if "--zoom" in sys.argv else 3
    night = "--night" in sys.argv
    g = glyphs()
    grid, bg = city_mono(g) if "--mono" in sys.argv else city(g, night)
    w, h, rows = render(grid, g, bg, zoom)
    if "--mono" in sys.argv:
        sprites_over(rows, zoom, h)
    write_png(out, w, h, rows)
    used = {name for line in grid for name, _ in line}
    cols = {col for line in grid for _, col in line}
    print(f"{out}: {W_CELLS}x{H_CELLS} cells, {len(used)} different glyphs, "
          f"{len(cols)} colours on screen (any of 16 a cell), hires: 320 pixels across")


if __name__ == "__main__":
    main()
