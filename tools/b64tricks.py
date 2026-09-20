#!/usr/bin/env python3
"""The char-mode techniques, each demonstrated in the engine's own pixels.

Asked for 2026-09-19, while working out the city's character set: what the
C64's games actually do about four colours a cell, and what each looks like
here.  Every picture is drawn from Char objects and sprite frames under the
machine's rules, so what it shows is what the chip would draw.

    grid      colour changes land on cell boundaries, because they must
    keyline   a shared black outline, so neighbouring cells never clash
    identity  shading in the shared trio, the cell's colour says what it is
    lines     a one-pixel horizontal line is legal; a vertical one is not
    animate   rewriting a character's eight bytes changes every cell at once
    sprites   what will not obey the grid, and two overlaid for more colour

usage: b64tricks.py <out-directory> [--zoom 8]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from b64art import (  # noqa: E402
    Char, BLACK, WHITE, RED, CYAN, GREEN, YELLOW, MGRAY, LGRAY,
    car_frames_mc, ped_frames_mc,
)
from b64palette import RGB  # noqa: E402
from b64png import write_png  # noqa: E402
from b64tileset import city_chars  # noqa: E402

SHARED = (BLACK, MGRAY, LGRAY)


def render(grid, zoom, shared=SHARED, grid_lines=False):
    """A grid of Char objects -> (w, h, rows)."""
    gh, gw = len(grid), max(len(r) for r in grid)
    w, h = gw * 8 * zoom, gh * 8 * zoom
    rows = [bytearray(RGB[shared[0]] * w) for _ in range(h)]
    for gy, line in enumerate(grid):
        for gx, ch in enumerate(line):
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
    if grid_lines:                                   # the cell boundaries, for the eye
        for gy in range(gh + 1):
            y = min(h - 1, gy * 8 * zoom)
            for p in range(0, w, 3):
                rows[y][3 * p:3 * p + 3] = bytes((255, 0, 128))
        for gx in range(gw + 1):
            x = min(w - 1, gx * 8 * zoom)
            for y in range(0, h, 3):
                rows[y][3 * x:3 * x + 3] = bytes((255, 0, 128))
    return w, h, rows


def sprite_over(rows, frame, x, y, colour, zoom, mc0=BLACK, mc1=WHITE):
    """A multicolour sprite frame over what is already drawn: '.' shows the
    playfield, which is what a character cell can never do."""
    for j, line in enumerate(frame):
        for i, c in enumerate(line):
            if c == ".":
                continue
            col = {"1": mc0, "2": colour, "3": mc1}[c]
            r, g, b = RGB[col]
            for zy in range(zoom):
                row = rows[(y + j) * zoom + zy]
                for zx in range(2 * zoom):
                    p = (x + 2 * i) * zoom + zx
                    if 0 <= 3 * p < len(row) - 3:
                        row[3 * p:3 * p + 3] = bytes((r, g, b))


def roof_block(c, w, h, colour=WHITE, keyline=True):
    """A building's roof, w by h characters, in a given cell colour."""
    out = []
    for j in range(h):
        row = []
        for i in range(w):
            name = "fill"
            if j == 0:
                name = "corner_nw" if i == 0 else ("corner_ne" if i == w - 1 else "edge_n")
            elif j == h - 1:
                name = "corner_sw" if i == 0 else ("corner_se" if i == w - 1 else "edge_s")
            elif i == 0:
                name = "edge_w"
            elif i == w - 1:
                name = "edge_e"
            else:
                name = ("fill", "fill1", "fill2", "fill3")[((i * 7) ^ (j * 13)) % 4]
            ch = c[name].copy()
            ch.colour = colour
            if colour != WHITE:                      # the field takes the building's colour,
                for y in range(8):                   # the cap stays a shared light grey
                    for x in range(ch.w):
                        if ch.px[y][x] == 2:
                            ch.px[y][x] = 3
                        elif ch.px[y][x] == 3:
                            ch.px[y][x] = 2
            if not keyline:                          # the outline filled in with the roof
                for y in range(8):
                    for x in range(ch.w):
                        if ch.px[y][x] == 0:
                            ch.px[y][x] = 3 if colour != WHITE else 2
            out.append(ch)
        yield_row = out[-w:]
        row.extend(yield_row)
    return [out[j * w:(j + 1) * w] for j in range(h)]


def ground(c, w, h):
    return [[c[("grass", "grass1", "grass2", "grass3")[((x * 11) ^ (y * 5)) % 4]]
             for x in range(w)] for y in range(h)]


def main():
    out = sys.argv[1]
    zoom = int(sys.argv[sys.argv.index("--zoom") + 1]) if "--zoom" in sys.argv else 8
    os.makedirs(out, exist_ok=True)
    c = city_chars()

    # 1. the grid: a colour change cannot happen inside a cell
    g = ground(c, 12, 6)
    for row in g:
        for ch in row:
            pass
    block = roof_block(c, 5, 4, RED)
    for j in range(4):
        for i in range(5):
            g[1 + j][1 + i] = block[j][i]
    half = c["fill"].copy()                          # a roof that wants to end mid-cell:
    half.colour = CYAN                               # the whole cell takes its colour
    half.fill(0, 0, 2, 8, 3)
    half.fill(2, 0, 2, 8, 2)
    g[2][7] = half
    g[3][7] = half
    w, h, rows = render(g, zoom, grid_lines=True)
    write_png(f"{out}/trick-grid.png", w, h, rows)

    # 2. the keyline: two roofs of different colours, meeting
    left = roof_block(c, 4, 4, RED)
    right = roof_block(c, 4, 4, CYAN)
    g = ground(c, 12, 6)
    for j in range(4):
        for i in range(4):
            g[1 + j][i] = left[j][i]
            g[1 + j][4 + i] = right[j][i]
    left2 = roof_block(c, 2, 4, RED, keyline=False)   # the same two, with no outline
    right2 = roof_block(c, 2, 4, CYAN, keyline=False)
    for j in range(4):
        for i in range(2):
            g[1 + j][8 + i] = left2[j][i]
            g[1 + j][10 + i] = right2[j][i]
    w, h, rows = render(g, zoom)
    write_png(f"{out}/trick-keyline.png", w, h, rows)

    # 3. identity: the same characters, four cell colours
    g = ground(c, 20, 6)
    for n, col in enumerate((WHITE, RED, CYAN, YELLOW)):
        b = roof_block(c, 4, 4, col)
        for j in range(4):
            for i in range(4):
                g[1 + j][1 + n * 5 + i] = b[j][i]
    w, h, rows = render(g, zoom)
    write_png(f"{out}/trick-identity.png", w, h, rows)

    # 4. lines: one pixel across is legal, one pixel down is not
    mc_h = Char(True, WHITE).all(2)
    for y in (1, 3, 5):
        mc_h.hline(0, y, 4, 3)
    mc_v = Char(True, WHITE).all(2)
    for x in (0, 2):
        mc_v.vline(x, 0, 8, 3)                       # the thinnest multicolour column: two pixels
    hi_v = Char(False, WHITE)
    for x in (1, 3, 5, 7):
        hi_v.vline(x, 0, 8, 1)                       # hires: one pixel, but two colours only
    g = [[mc_h, mc_v, hi_v]]
    w, h, rows = render(g, 26)
    write_png(f"{out}/trick-lines.png", w, h, rows)

    # 5. charset animation: one character rewritten, every cell using it changes
    frames = []
    for phase in range(3):
        lamp = Char(True, WHITE).all(2)
        lamp.rect(0, 1, 4, 6, 0)
        lamp.fill(1, 2, 2, 4, 1)
        if phase:                                    # the beacon, dim then lit
            lamp.fill(1, 3, 2, 2, 3 if phase == 2 else 1)
        cc = dict(c)
        cc["ac"] = lamp
        g = ground(cc, 10, 6)
        b = roof_block(cc, 6, 4, WHITE)
        for j in range(4):
            for i in range(6):
                g[1 + j][2 + i] = b[j][i]
        g[2][6] = lamp
        w, h, rows = render(g, zoom)
        write_png(f"{out}/trick-animate-{phase}.png", w, h, rows)
        frames.append((w, h, rows))
    strip = [bytearray() for _ in range(frames[0][1])]
    for w0, h0, r0 in frames:
        for y in range(h0):
            strip[y] += r0[y] + bytearray(bytes((0, 0, 0)) * 8)
    write_png(f"{out}/trick-animate.png", len(strip[0]) // 3, len(strip), strip)

    # 6. sprites: what will not obey the grid, and two overlaid
    g = ground(c, 14, 6)
    b = roof_block(c, 5, 3, WHITE)
    for j in range(3):
        for i in range(5):
            g[0 + j][1 + i] = b[j][i]
    for x in range(14):                              # a road along the bottom
        g[4][x] = c["road"]
        g[5][x] = c["dash"] if x % 2 else c["road"]
    w, h, rows = render(g, zoom)
    cars = car_frames_mc()
    sprite_over(rows, cars[1], 12, 33, RED, zoom)
    sprite_over(rows, ped_frames_mc()[0], 60, 12, YELLOW, zoom)
    sprite_over(rows, cars[3], 74, 33, CYAN, zoom)   # two sprites, one over the other,
    sprite_over(rows, ped_frames_mc()[1], 76, 33, WHITE, zoom)   # for colours one cannot hold
    write_png(f"{out}/trick-sprites.png", w, h, rows)
    print(f"{out}: grid, keyline, identity, lines, animate, sprites at {zoom}x")


if __name__ == "__main__":
    main()
