#!/usr/bin/env python3
"""An isometric city in one colour, with the traffic in sprites.

The synthesis the user reached on 2026-09-19: if the playfield is drawn in
a single colour, the two things that stopped isometric stop mattering.
Colour cannot clash when there is one colour, so every cell is legal by
construction; and a building may overlap the ground behind it cheaply,
because that ground is mostly empty -- the combinations that would outrun
the charset in a coloured city never arise.

It also buys back the resolution: a hires character is eight pixels across,
so the diagonals are one pixel thick and the city is drawn at the full
320x200 rather than 160x200.

What it costs is the charset: every distinct 8x8 pattern is a character,
and there are 256.  This counts them.  Colour arrives only as sprites --
cars and people -- which is what makes them read.

usage: b64isomono.py <out.png> [--zoom 3] [--no-sprites]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from b64palette import RGB  # noqa: E402
from b64png import write_png  # noqa: E402
from b64art import (  # noqa: E402
    BLACK, WHITE, RED, CYAN, YELLOW, ORANGE, PINK, LGREEN,
    car_frames_mc, ped_frames_mc,
)

W, H = 320, 200                       # hires: one bit a pixel
INK, PAPER = WHITE, BLACK


def line(buf, x0, y0, x1, y1):
    """A one-pixel line, which multicolour could not draw on the diagonal."""
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        if 0 <= x0 < W and 0 <= y0 < H:
            buf[y0][x0] = 1
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy; x0 += sx
        if e2 <= dx:
            err += dx; y0 += sy


def hatch(buf, pts, step=4, phase=0):
    """Fill a quadrilateral with horizontal rules, at absolute rows so the
    same patterns recur cell after cell: grid-aligned shading is what keeps
    the character count inside 256."""
    ys = [p[1] for p in pts]
    for y in range(min(ys), max(ys) + 1):
        if y % step != phase % step:
            continue
        xs = []
        for i in range(len(pts)):                      # where the outline crosses this row
            (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
            if (ay <= y < by) or (by <= y < ay):
                xs.append(ax + (bx - ax) * (y - ay) / (by - ay))
        xs.sort()
        for k in range(0, len(xs) - 1, 2):
            for x in range(int(xs[k]) + 1, int(xs[k + 1])):
                if 0 <= x < W and 0 <= y < H:
                    buf[y][x] = 1


def lot(buf, cx, cy, w, h):
    """An isometric ground tile, outlined."""
    line(buf, cx - w // 2, cy, cx, cy - h // 2)
    line(buf, cx, cy - h // 2, cx + w // 2, cy)
    line(buf, cx + w // 2, cy, cx, cy + h // 2)
    line(buf, cx, cy + h // 2, cx - w // 2, cy)


def building(buf, cx, cy, w, h, lift, windows=True):
    """A block: two hatched faces, a top, and windows in rows."""
    hw, hh = w // 2, h // 2
    top = cy - lift
    left = [(cx - hw, cy), (cx, cy + hh), (cx, cy + hh - lift), (cx - hw, cy - lift)]
    right = [(cx + hw, cy), (cx, cy + hh), (cx, cy + hh - lift), (cx + hw, cy - lift)]
    hatch(buf, left, 4, 0)                             # the shaded face, ruled every 4 rows
    hatch(buf, right, 8, 4)                            # the lit face, every 8: lighter
    for pts in (left, right):                          # their outlines
        for i in range(len(pts)):
            line(buf, *pts[i], *pts[(i + 1) % len(pts)])
    lot(buf, cx, top, w, h)                            # the roof
    line(buf, cx - hw, cy, cx - hw, cy - lift)         # the corners
    line(buf, cx + hw, cy, cx + hw, cy - lift)
    line(buf, cx, cy + hh, cx, cy + hh - lift)
    # no windows cut into the faces: every cut makes a character of its own,
    # and the ruling already reads as storeys


def city(buf):
    TW, TH = 48, 24
    lots = [(r, c) for r in range(-1, 6) for c in range(-1, 6)]
    lots.sort(key=lambda rc: rc[0] + rc[1])            # back to front
    for row, col in lots:
        cx = 160 + (col - row) * TW // 2
        cy = 50 + (col + row) * TH // 2
        if not (-TW < cx < W + TW and -TH < cy < H + TH):
            continue
        kind = (col * 5 + row * 3) % 7
        lot(buf, cx, cy, TW, TH)
        if kind in (0, 3, 4):                          # streets and empty lots
            continue
        storeys = 1 if kind in (1, 5) else (2 if kind == 2 else 3)
        building(buf, cx, cy, TW - 12, TH - 6, storeys * 16)


def render(buf, zoom, sprites):
    w, h = W * zoom, H * zoom
    rows = [bytearray(RGB[PAPER] * w) for _ in range(h)]
    for y in range(H):
        for x in range(W):
            if not buf[y][x]:
                continue
            r, g, b = RGB[INK]
            for zy in range(zoom):
                row = rows[y * zoom + zy]
                for zx in range(zoom):
                    p = x * zoom + zx
                    row[3 * p:3 * p + 3] = bytes((r, g, b))
    for frame, sx, sy, colour in sprites:              # the only colour on the screen
        for j, l in enumerate(frame):
            for i, ch in enumerate(l):
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
    return w, h, rows


def main():
    out = sys.argv[1]
    zoom = int(sys.argv[sys.argv.index("--zoom") + 1]) if "--zoom" in sys.argv else 3
    buf = [[0] * W for _ in range(H)]
    city(buf)
    chars = {tuple(tuple(buf[cy * 8 + y][cx * 8:cx * 8 + 8]) for y in range(8))
             for cy in range(H // 8) for cx in range(W // 8)}
    spr = []
    if "--no-sprites" not in sys.argv:
        cars, peds = car_frames_mc(), ped_frames_mc()
        spr = [(cars[1], 92, 92, RED), (cars[3], 150, 120, CYAN), (cars[0], 196, 60, YELLOW),
               (cars[2], 118, 150, LGREEN), (peds[0], 140, 84, PINK), (peds[1], 176, 112, ORANGE)]
    w, h, rows = render(buf, zoom, spr)
    write_png(out, w, h, rows)
    print(f"{out}: {W}x{H} hires pixels, {len(chars)} different characters of 256, "
          f"{len(spr)} sprites carrying every colour on screen")


if __name__ == "__main__":
    main()
