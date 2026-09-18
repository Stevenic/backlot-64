#!/usr/bin/env python3
"""The multiplexer harness (examples/mux) checked sprite by sprite.

The harness puts sprite i at x = 24 + (i mod 12) * 26, y = 60 + ((2t +
phase[i]) & 127) as a solid block in colour 1 + (i mod 15).  Given a
screenshot and the t of the list it shows, each sprite is judged: whole
(every pixel of its block, as far as the display window shows it, is one
colour and not the background), absent (none of it), or damaged (anything
else).  A multiplexer may leave a sprite out when a line is overloaded; it
may never show one damaged.
"""
X0, Y0 = 32 - 24, 35 - 50          # VIC sprite coordinates to screenshot pixels (PAL, VICE)
VIS = (32 + 7, 35, 32 + 320 - 9, 35 + 23 * 8)  # the 38-column playfield, above the HUD row
NSPR = 24


def phase(i, dense):
    return ((i % 12) * (2 if dense else 11) + (i // 12) * 64) & 255


def position(i, t, dense):
    x = 24 + (i % 12) * 26
    y = 60 + (((2 * t) & 255) + phase(i, dense)) & 127
    return x, 60 + ((((2 * t) & 255) + phase(i, dense)) & 127)


def judge(rows, t, dense):
    """-> {i: 'whole' | 'absent' | 'damaged'} and the rectangles used."""
    bg = bytes(3)
    out = {}
    for i in range(NSPR):
        x, y = position(i, t, dense)
        sx, sy = x + X0, y + Y0
        xs = range(max(sx, VIS[0]), min(sx + 24, VIS[2]))
        ys = range(max(sy, VIS[1]), min(sy + 21, VIS[3]))
        pix = [rows[yy][3 * xx:3 * xx + 3] for yy in ys for xx in xs]
        if not pix:
            continue
        lit = [p for p in pix if p != bg]
        if not lit:
            out[i] = "absent"
        elif len(lit) == len(pix) and len(set(pix)) == 1:
            out[i] = "whole"
        else:
            out[i] = "damaged"
    return out


def overlapping(t, dense):
    """Sprites whose blocks overlap another's: their pixels can't be judged alone."""
    boxes = [position(i, t, dense) for i in range(NSPR)]
    bad = set()
    for i in range(NSPR):
        for j in range(i + 1, NSPR):
            (xi, yi), (xj, yj) = boxes[i], boxes[j]
            if abs(xi - xj) < 24 and abs(yi - yj) < 21:
                bad |= {i, j}
    return bad
