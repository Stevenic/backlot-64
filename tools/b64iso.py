#!/usr/bin/env python3
"""An isometric city, drawn freely and then checked against the chip.

Asked 2026-09-19, against a city-builder screenshot: is that look possible
here?  Rather than argue, this draws a 2:1 isometric city into a pixel
buffer using whatever colours it likes, then does what the VIC-II would
force: every 8x8 cell may show three colours shared by the whole screen
plus one of its own.  It reports how many cells break that, quantises each
cell to the nearest legal set, and writes both pictures.

The answer it gives is about colour.  The other limit is overlap: a
character cell shows one character, so a tall building cannot be drawn over
the ground behind it unless that ground is part of the same tiles -- or
unless the building is a sprite, which can overlap anything.

usage: b64iso.py <out-prefix> [--zoom 3]
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
)

W, H = 160, 200                       # multicolour pixels: 320x200 on screen
TOWERS = []                           # in sprite mode: where the tall ones go
SHARED = (BLACK, MGRAY, LGRAY)        # what the screen shares, chosen below


def diamond(buf, cx, cy, w, h, col):
    """A 2:1 isometric ground tile, w by h pixels, centred at (cx, cy)."""
    for y in range(-h // 2, h // 2 + 1):
        span = int(w / 2 * (1 - abs(y) / (h / 2))) if h else 0
        for x in range(-span, span + 1):
            px, py = cx + x, cy + y
            if 0 <= px < W and 0 <= py < H:
                buf[py][px] = col


def box(buf, cx, cy, w, h, storeys, top, left, right, edge=BLACK, rise=7):
    """An isometric block standing on the lot centred at (cx, cy): its two
    visible faces, then its top, drawn over them.  `rise` is how tall a
    storey is, which shrinks with the lots on a map screen."""
    lift = storeys * rise
    half_w, half_h = w // 2, h // 2
    for dx in range(-half_w, half_w + 1):              # the faces, column by column
        edge_y = int(half_h * (1 - abs(dx) / half_w)) if half_w else 0
        y0 = cy - lift + edge_y                        # the top face's lower edge
        y1 = cy + edge_y                               # the lot's lower edge
        col = left if dx < 0 else right
        for y in range(y0, y1 + 1):
            px = cx + dx
            if 0 <= px < W and 0 <= y < H:
                buf[y][px] = edge if dx in (-half_w, half_w) or y == y1 else col
    diamond(buf, cx, cy - lift, w, h, top)             # the top face, lit
    for dx in range(-half_w, half_w + 1):              # its outline
        edge_y = int(half_h * (1 - abs(dx) / half_w)) if half_w else 0
        for y in (cy - lift - edge_y, cy - lift + edge_y):
            px = cx + dx
            if 0 <= px < W and 0 <= y < H:
                buf[y][px] = edge


def city(buf, mode="flip"):
    """A corner of an isometric city.  The mode says which of the four ways
    of living with the hardware it is drawn for:

        flip     one authored screen, towers and all: the Last Ninja model
        map      the whole city small, as a picture for a map screen
        lots     scrolling, but every building confined to its own lot
        sprites  scrolling low tiles, the towers drawn as sprites over them
    """
    for y in range(H):                                 # the sea, then the sand
        for x in range(W):
            buf[y][x] = BLUE if y > 150 + (x % 7) // 4 else (YELLOW if y > 140 else GREEN)
    TW, TH = (8, 4) if mode == "map" else (16, 8)      # a lot, in multicolour pixels
    span = 30 if mode == "map" else 14
    lots = [(row, col) for row in range(-2, span) for col in range(-2, span)]
    lots.sort(key=lambda rc: rc[0] + rc[1])            # back to front, so blocks overlap right
    for row, col in lots:
        if True:
            cx = 40 + (col - row) * TW // 2
            cy = 30 + (col + row) * TH // 2
            if not (0 <= cx < W and 0 <= cy < H - 60):
                continue
            kind = (col * 7 + row * 5) % 9
            if kind in (0, 3):                          # a street
                diamond(buf, cx, cy, TW, TH, DGRAY)
                continue
            diamond(buf, cx, cy, TW, TH, LGREEN)        # the lot's ground
            if kind == 1:
                continue
            storeys = 1 if kind in (2, 4) else (2 if kind in (5, 6) else 5)
            if mode == "lots":                          # nothing may reach the lot behind
                storeys = 1
            if mode == "sprites" and storeys > 2:       # the towers are sprites, drawn later
                TOWERS.append((cx, cy - 2, storeys))
                storeys = 1
            top, left, right = ((LGRAY, MGRAY, DGRAY) if kind % 2 else
                                (WHITE, LBLUE, BLUE) if storeys > 2 else
                                (ORANGE, BROWN, RED))
            box(buf, cx, cy - 2, TW - 4, TH - 2, storeys, top, left, right,
                rise=3 if mode == "map" else 7)


def cell_colours(buf, cx, cy):
    out = {}
    for y in range(8):
        for x in range(4):
            c = buf[cy * 8 + y][cx * 4 + x]
            out[c] = out.get(c, 0) + 1
    return out


def check_and_quantise(buf, shared):
    """How many cells break the rule, and the same picture made legal."""
    bad, out = 0, [row[:] for row in buf]
    for cy in range(H // 8):
        for cx in range(W // 4):
            counts = cell_colours(buf, cx, cy)
            extra = {c: n for c, n in counts.items() if c not in shared}
            if len(extra) > 1:
                bad += 1
            own = max(extra, key=lambda c: extra[c]) if extra else WHITE
            keep = set(shared) | {own}
            for y in range(8):                          # the cell, made legal
                for x in range(4):
                    px, py = cx * 4 + x, cy * 8 + y
                    c = buf[py][px]
                    if c in keep:
                        continue
                    lum = {BLACK: 0, BLUE: 1, DGRAY: 2, BROWN: 2, RED: 3, PURPLE: 3,
                           MGRAY: 4, GREEN: 4, ORANGE: 4, LBLUE: 5, LGRAY: 6,
                           CYAN: 6, LGREEN: 7, YELLOW: 7, PINK: 5, WHITE: 8}
                    out[py][px] = min(keep, key=lambda k: abs(lum.get(k, 4) - lum.get(c, 4)))
    return bad, out


def render(buf, zoom):
    rows = [bytearray() for _ in range(H * zoom)]
    for y in range(H):
        line = bytearray()
        for x in range(W):
            r, g, b = RGB[buf[y][x]]
            line += bytes((r, g, b)) * 2 * zoom
        for z in range(zoom):
            rows[y * zoom + z] = bytearray(line)
    return W * 2 * zoom, H * zoom, rows


def main():
    prefix = sys.argv[1]
    zoom = int(sys.argv[sys.argv.index("--zoom") + 1]) if "--zoom" in sys.argv else 3
    mode = sys.argv[sys.argv.index("--mode") + 1] if "--mode" in sys.argv else "flip"
    TOWERS.clear()
    buf = [[BLACK] * W for _ in range(H)]
    city(buf, mode)
    bad, legal = check_and_quantise(buf, SHARED)
    cells = (W // 4) * (H // 8)
    chars = len({tuple(tuple(legal[cy * 8 + y][cx * 4:cx * 4 + 4]) for y in range(8))
                 for cy in range(H // 8) for cx in range(W // 4)})
    if mode == "sprites":                               # the towers, over the finished tiles
        for cx, cy, storeys in TOWERS[:6]:
            box(legal, cx, cy, 10, 6, storeys, WHITE, LBLUE, BLUE)
    w, h, rows = render(legal, zoom)
    write_png(f"{prefix}-{mode}.png", w, h, rows)
    extra = f", {min(len(TOWERS), 6) * 2} sprites for the towers" if mode == "sprites" else ""
    print(f"{prefix}-{mode}: {bad} of {cells} cells wanted more than four colours "
          f"({100 * bad // cells}%); {chars} different characters of 256{extra}")


if __name__ == "__main__":
    main()
