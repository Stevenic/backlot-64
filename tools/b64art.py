#!/usr/bin/env python3
"""Drawing primitives and placeholder art for the engine's example assets.

The example tileset (b64tileset.py) and the format sheets (b64formats.py)
draw with these: the palette indices, a 3x5 caption font, a pixel canvas
that converts to a charset with screen and colour RAM, sprite encoding, and
the placeholder car and pedestrian sprites the scroller example drives.
Games bring their own art; nothing here is part of the engine's runtime.

First written for the Priors-64 look-and-feel demos by the same author and
moved here on 2026-09-18 so the engine builds from its own repository.
"""
import sys

# C64 palette indices
BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW = range(8)
ORANGE, BROWN, PINK, DGRAY, MGRAY, LGREEN, LBLUE, LGRAY = range(8, 16)

W, H = 40, 25

# 3x5 pixel font for captions and signs
FONT = {
    'A': ["010", "101", "111", "101", "101"], 'B': ["110", "101", "110", "101", "110"],
    'C': ["011", "100", "100", "100", "011"], 'D': ["110", "101", "101", "101", "110"],
    'E': ["111", "100", "110", "100", "111"], 'F': ["111", "100", "110", "100", "100"],
    'G': ["011", "100", "101", "101", "011"], 'H': ["101", "101", "111", "101", "101"],
    'I': ["111", "010", "010", "010", "111"], 'J': ["001", "001", "001", "101", "010"],
    'K': ["101", "101", "110", "101", "101"], 'L': ["100", "100", "100", "100", "111"],
    'M': ["101", "111", "111", "101", "101"], 'N': ["110", "101", "101", "101", "101"],
    'O': ["010", "101", "101", "101", "010"], 'P': ["110", "101", "110", "100", "100"],
    'Q': ["010", "101", "101", "110", "011"], 'R': ["110", "101", "110", "101", "101"],
    'S': ["011", "100", "010", "001", "110"], 'T': ["111", "010", "010", "010", "010"],
    'U': ["101", "101", "101", "101", "111"], 'V': ["101", "101", "101", "101", "010"],
    'W': ["101", "101", "111", "111", "101"], 'X': ["101", "101", "010", "101", "101"],
    'Y': ["101", "101", "010", "010", "010"], 'Z': ["111", "001", "010", "100", "111"],
    '0': ["111", "101", "101", "101", "111"], '1': ["010", "110", "010", "010", "111"],
    '2': ["111", "001", "111", "100", "111"], '3': ["111", "001", "011", "001", "111"],
    '4': ["101", "101", "111", "001", "001"], '5': ["111", "100", "111", "001", "111"],
    '6': ["111", "100", "111", "101", "111"], '7': ["111", "001", "010", "010", "010"],
    '8': ["111", "101", "111", "101", "111"], '9': ["111", "101", "111", "001", "111"],
    ' ': ["000", "000", "000", "000", "000"], '-': ["000", "000", "111", "000", "000"],
    '.': ["000", "000", "000", "000", "010"], '/': ["001", "001", "010", "100", "100"],
    ',': ["000", "000", "000", "010", "100"], ':': ["000", "010", "000", "010", "000"],
    '!': ["010", "010", "010", "000", "010"], '?': ["110", "001", "010", "000", "010"],
    "'": ["010", "010", "000", "000", "000"], '(': ["001", "010", "010", "010", "001"],
    ')': ["100", "010", "010", "010", "100"],
}


# ---------------------------------------------------------------------------
# Canvas: pixel buffer + per-cell colour, exported to charset/screen/colour
# ---------------------------------------------------------------------------
class Canvas:
    def __init__(self, mc, w=W, h=H):
        self.mc = mc
        self.w, self.h = w, h
        self.cw = 4 if mc else 8            # canvas pixels per cell, horizontally
        self.pw = w * self.cw
        self.ph = h * 8
        self.px = [[0] * self.pw for _ in range(self.ph)]
        self.col = [[1] * w for _ in range(h)]

    # -- pixel primitives ---------------------------------------------------
    def put(self, x, y, v):
        if 0 <= x < self.pw and 0 <= y < self.ph:
            self.px[y][x] = v

    def get(self, x, y):
        if 0 <= x < self.pw and 0 <= y < self.ph:
            return self.px[y][x]
        return 0

    def fill(self, x, y, w, h, v):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.put(xx, yy, v)

    def hline(self, x, y, w, v):
        self.fill(x, y, w, 1, v)

    def vline(self, x, y, h, v):
        self.fill(x, y, 1, h, v)

    def rect(self, x, y, w, h, v):
        self.hline(x, y, w, v)
        self.hline(x, y + h - 1, w, v)
        self.vline(x, y, h, v)
        self.vline(x + w - 1, y, h, v)

    def dither(self, x, y, w, h, a, b):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.put(xx, yy, a if ((xx + yy) & 1) == 0 else b)

    def dots(self, x, y, w, h, a, b, sx=4, sy=4, ox=0, oy=0):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                on = ((xx - ox) % sx == 0) and ((yy - oy) % sy == 0)
                self.put(xx, yy, b if on else a)

    def dashes(self, x, y, w, on, off, v, thick=1):
        xx = x
        while xx < x + w:
            self.fill(xx, y, min(on, x + w - xx), thick, v)
            xx += on + off

    def vdashes(self, x, y, h, on, off, v, thick=1):
        yy = y
        while yy < y + h:
            self.fill(x, yy, thick, min(on, y + h - yy), v)
            yy += on + off

    def text(self, x, y, s, v):
        for ch in s:
            g = FONT.get(ch.upper(), FONT[' '])
            for r, row in enumerate(g):
                for c, bit in enumerate(row):
                    if bit == '1':
                        self.put(x + c, y + r, v)
            x += 4

    # -- cell helpers -------------------------------------------------------
    def crect(self, cx, cy, cw, ch, color):
        for y in range(cy, cy + ch):
            for x in range(cx, cx + cw):
                if 0 <= x < self.w and 0 <= y < self.h:
                    self.col[y][x] = color

    def cfill(self, cx, cy, cw, ch, v, color=None):
        self.fill(cx * self.cw, cy * 8, cw * self.cw, ch * 8, v)
        if color is not None:
            self.crect(cx, cy, cw, ch, color)

    def cdots(self, cx, cy, cw, ch, a, b, color=None, sx=4, sy=4):
        self.dots(cx * self.cw, cy * 8, cw * self.cw, ch * 8, a, b, sx, sy)
        if color is not None:
            self.crect(cx, cy, cw, ch, color)

    def cdither(self, cx, cy, cw, ch, a, b, color=None):
        self.dither(cx * self.cw, cy * 8, cw * self.cw, ch * 8, a, b)
        if color is not None:
            self.crect(cx, cy, cw, ch, color)

    def ctext(self, cx, cy, s, color, v=None):
        if v is None:
            v = 3 if self.mc else 1
        cells = (len(s) * 4 + self.cw - 1) // self.cw
        self.crect(cx, cy, cells, 1, color)
        self.text(cx * self.cw, cy * 8 + 1, s, v)

    def caption(self, s, color=WHITE):
        self.cfill(0, H - 1, W, 1, 0, color)
        self.ctext(1, H - 1, s, color)

    # -- export -------------------------------------------------------------
    def export(self, chars=None, order=None):
        """Convert to (charset, screen, colour, nchars).  Pass a shared
        `chars` dict and `order` list to dedupe across several canvases."""
        if chars is None:
            chars = {}
        if order is None:
            order = []
        screen = bytearray()
        color = bytearray()
        for cy in range(self.h):
            for cx in range(self.w):
                rows = []
                for r in range(8):
                    y = cy * 8 + r
                    b = 0
                    if self.mc:
                        for i in range(4):
                            b |= (self.px[y][cx * 4 + i] & 3) << (6 - 2 * i)
                    else:
                        for i in range(8):
                            b |= (self.px[y][cx * 8 + i] & 1) << (7 - i)
                    rows.append(b)
                key = tuple(rows)
                if key not in chars:
                    chars[key] = len(order)
                    order.append(key)
                screen.append(chars[key])
                c = self.col[cy][cx]
                if self.mc:
                    if c >= 8:
                        raise SystemExit(f"multicolour cell colour must be 0-7 at {cx},{cy}: {c}")
                    c |= 8
                color.append(c)
        if len(order) > 256:
            raise SystemExit(f"too many unique cells: {len(order)}")
        charset = bytearray()
        for key in order:
            charset += bytes(key)
        charset += bytes(2048 - len(charset))
        return bytes(charset), bytes(screen), bytes(color), len(order)


# ---------------------------------------------------------------------------
# Sprites
# ---------------------------------------------------------------------------
def _grid(rows, w, h):
    g = [list(r.ljust(w, '.')[:w]) for r in rows]
    while len(g) < h:
        g.append(['.'] * w)
    return g[:h]


def _recenter(g, w, h):
    """Crop to bounding box of non-'.' and centre in a w x h box."""
    ys = [y for y in range(len(g)) if any(c != '.' for c in g[y])]
    xs = [x for y in range(len(g)) for x in range(len(g[y])) if g[y][x] != '.']
    if not ys:
        return [['.'] * w for _ in range(h)]
    y0, y1, x0, x1 = min(ys), max(ys), min(xs), max(xs)
    bw, bh = x1 - x0 + 1, y1 - y0 + 1
    assert bw <= w and bh <= h, f"sprite {bw}x{bh} does not fit {w}x{h}"
    out = [['.'] * w for _ in range(h)]
    ox, oy = (w - bw) // 2, (h - bh) // 2
    for y in range(bh):
        for x in range(bw):
            out[oy + y][ox + x] = g[y0 + y][x0 + x]
    return out


def rot_cw(rows, w, h):
    g = _grid(rows, w, h)
    r = [[g[h - 1 - y][x] for y in range(h)] for x in range(w)]   # h x w -> w rows of h
    return ["".join(row) for row in _recenter(r, w, h)]


def rot_ccw(rows, w, h):
    return rot_cw(rot_cw(rot_cw(rows, w, h), w, h), w, h)


def flip_h(rows, w, h):
    g = _grid(rows, w, h)
    return ["".join(row[::-1]) for row in _recenter(g, w, h)]


def flip_v(rows, w, h):
    g = _grid(rows, w, h)
    return ["".join(row) for row in _recenter(g[::-1], w, h)]


def center(rows, w, h):
    return ["".join(row) for row in _recenter(_grid(rows, w, h), w, h)]


def encode_sprite(rows, mc):
    out = bytearray()
    for r in range(21):
        row = rows[r] if r < len(rows) else ''
        if mc:
            row = row.ljust(12, '.')
            for i in range(0, 12, 4):
                b = 0
                for j in range(4):
                    ch = row[i + j]
                    v = 0 if ch == '.' else int(ch)
                    b |= v << (6 - 2 * j)
                out.append(b)
        else:
            row = row.ljust(24, '.')
            for i in range(0, 24, 8):
                b = 0
                for j in range(8):
                    if row[i + j] == '#':
                        b |= 1 << (7 - j)
                out.append(b)
    out.append(0)
    return bytes(out)


# Hires car, heading up, 12x20.
CAR_H = [
    "..########..",
    ".##########.",
    "############",
    "############",
    "##........##",
    "##........##",
    "############",
    "############",
    "############",
    "############",
    "############",
    "############",
    "############",
    "##........##",
    "##........##",
    "############",
    "############",
    ".##########.",
    "..########..",
    ".##......##.",
]

# Hires pedestrian, two walk frames, ~8x12.
PED_H = [
    [
        "...##...",
        "...##...",
        "..####..",
        ".######.",
        "#.####.#",
        "#.####.#",
        "..####..",
        "..#..#..",
        "..#..#..",
        ".##..##.",
        "##....##",
    ],
    [
        "...##...",
        "...##...",
        "..####..",
        ".######.",
        ".######.",
        "..####..",
        "..####..",
        "..####..",
        "...##...",
        "...##...",
        "...###..",
    ],
]

# Multicolour car, heading up, 6x14 (1 = MC0 outline, 2 = body, 3 = MC1 lights/glass)
CAR_M_UP = [
    ".2222.",
    "122221",
    "233332",
    "222222",
    "211112",
    "211112",
    "222222",
    "222222",
    "222222",
    "222222",
    "222222",
    "211112",
    "222222",
    "122221",
    ".2222.",
]

# Multicolour car, heading right, 12x6
CAR_M_RIGHT = [
    ".2222222222.",
    "122211122223",
    "222211122223",
    "222211122223",
    "122211122223",
    ".2222222222.",
]

# Multicolour pedestrian, two frames, 4x11
PED_M = [
    [
        ".33.",
        ".33.",
        "2222",
        "2222",
        "2222",
        ".22.",
        ".11.",
        ".11.",
        "1..1",
        "1..1",
    ],
    [
        ".33.",
        ".33.",
        "2222",
        "2222",
        "2222",
        ".22.",
        ".11.",
        ".11.",
        ".11.",
        ".11.",
    ],
]

# Isometric car facing screen-down-right (SE), multicolour 12x9
CAR_ISO_SE = [
    "....2222....",
    "...222222...",
    "..22211222..",
    ".2221111222.",
    "22222111122.",
    "12222222223.",
    ".1222222233.",
    "..12222233..",
    "...111111...",
]

# Isometric car facing screen-up-right (NE)
CAR_ISO_NE = [
    "....2222....",
    "...222222...",
    "..22222222..",
    ".2222222222.",
    ".2211112223.",
    "12211112233.",
    ".1222222233.",
    "..12222233..",
    "...111111...",
]


def car_frames_hires():
    up = center(CAR_H, 24, 21)
    return [up, rot_cw(up, 24, 21), flip_v(up, 24, 21), rot_ccw(up, 24, 21)]   # up, right, down, left


def car_frames_mc():
    up = center(CAR_M_UP, 12, 21)
    right = center(CAR_M_RIGHT, 12, 21)
    return [up, right, flip_v(up, 12, 21), flip_h(right, 12, 21)]


def ped_frames_hires():
    return [center(f, 24, 21) for f in PED_H]


def ped_frames_mc():
    return [center(f, 12, 21) for f in PED_M]


def car_frames_iso():
    se = center(CAR_ISO_SE, 12, 21)
    ne = center(CAR_ISO_NE, 12, 21)
    # order: SE, NW, NE, SW
    return [se, flip_h(flip_v(ne, 12, 21), 12, 21), ne, flip_h(se, 12, 21)]


# ---------------------------------------------------------------------------
# Paths: list of (dx, dy, frame, count) entries, looping
# ---------------------------------------------------------------------------
