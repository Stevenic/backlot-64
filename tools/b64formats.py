#!/usr/bin/env python3
"""Vehicle portrait formats: the same police cruiser as (A) an expanded
hardware sprite, (B) a character block, (C) part of a multicolour bitmap
still.  Each is quantised under that mode's real colour rules and rendered
to PNG at C64 pixel scale, so the page shows what the chip would show.

usage: b64formats.py <out-dir> <out.html>
"""
import base64
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "..", "GTA-64", "tools"))
from b64palette import RGB, write_png  # noqa: E402
from mkdemo import CAR_M_UP, FONT  # noqa: E402

BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW = range(8)
ORANGE, BROWN, PINK, DGRAY, MGRAY, LGREEN, LBLUE, LGRAY = range(8, 16)
NAMES = ["black", "white", "red", "cyan", "purple", "green", "blue", "yellow",
         "orange", "brown", "pink", "dgray", "mgray", "lgreen", "lblue", "lgray"]


def dist(a, b):
    return sum((RGB[a][i] - RGB[b][i]) ** 2 for i in range(3))


# ---------------------------------------------------------------------------
# A palette-index canvas in multicolour pixels (each 2 real pixels wide)
# ---------------------------------------------------------------------------
class Pix:
    def __init__(self, w, h, fill=BLACK):
        self.w, self.h = w, h
        self.p = [[fill] * w for _ in range(h)]

    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.p[y][x] = c

    def fill(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.put(xx, yy, c)

    def hline(self, x, y, w, c):
        self.fill(x, y, w, 1, c)

    def vline(self, x, y, h, c):
        self.fill(x, y, 1, h, c)

    def dither(self, x, y, w, h, a, b):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.put(xx, yy, a if ((xx + yy) & 1) == 0 else b)

    def disc(self, cx, cy, r, c):
        for yy in range(-r, r + 1):
            span = int((r * r - yy * yy) ** 0.5 + 0.5)
            self.hline(cx - span, cy + yy, 2 * span + 1, c)

    def poly(self, pts, c):
        ys = [p[1] for p in pts]
        for yy in range(min(ys), max(ys) + 1):
            xs = []
            n = len(pts)
            for i in range(n):
                (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
                if y0 == y1:
                    continue
                lo, hi = (y0, y1) if y0 < y1 else (y1, y0)
                if lo <= yy < hi:
                    xs.append(x0 + (yy - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                self.hline(int(round(xs[i])), yy, int(round(xs[i + 1])) - int(round(xs[i])) + 1, c)

    def line(self, x0, y0, x1, y1, c):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(n + 1):
            self.put(round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n), c)

    def text(self, x, y, s, c):
        for ch in s:
            g = FONT.get(ch.upper(), FONT[' '])
            for r, row in enumerate(g):
                for k, bit in enumerate(row):
                    if bit == '1':
                        self.put(x + k, y + r, c)
            x += 4

    # quantise every 4x8 cell to `allowed_fixed` + up to `extra` other colours
    def quantise(self, fixed, extra):
        fixed_cells = 0
        for cy in range(0, self.h, 8):
            for cx in range(0, self.w, 4):
                counts = {}
                for yy in range(cy, cy + 8):
                    for xx in range(cx, cx + 4):
                        c = self.p[yy][xx]
                        if c not in fixed:
                            counts[c] = counts.get(c, 0) + 1
                if len(counts) <= extra:
                    continue
                fixed_cells += 1
                keep = sorted(counts, key=lambda c: -counts[c])[:extra]
                allowed = list(fixed) + keep
                for yy in range(cy, cy + 8):
                    for xx in range(cx, cx + 4):
                        c = self.p[yy][xx]
                        if c not in allowed:
                            self.p[yy][xx] = min(allowed, key=lambda a: dist(a, c))
        return fixed_cells

    def render(self, scale=2, bg=None):
        rows = []
        for y in range(self.h):
            row = []
            for x in range(self.w):
                c = self.p[y][x]
                rgb = RGB[c] if c is not None else bg
                row += [rgb] * (2 * scale)
            for _ in range(scale):
                rows.append(row)
        return rows


# ---------------------------------------------------------------------------
# The cruiser, side view, facing right.  Drawn in palette indices on a Pix
# at (ox, oy); 56 px wide, 44 tall, in multicolour pixels.
# ---------------------------------------------------------------------------
def draw_cruiser(p, ox, oy, lamp_left=RED, lamp_right=BLUE, body=WHITE):
    X = lambda x: ox + x
    Y = lambda y: oy + y
    # shadow
    p.fill(X(4), Y(41), 52, 2, DGRAY)
    # lower body
    p.fill(X(3), Y(20), 54, 18, body)
    p.hline(X(3), Y(20), 54, BLACK)
    p.hline(X(3), Y(37), 54, BLACK)
    p.vline(X(3), Y(20), 18, BLACK)
    p.vline(X(56), Y(20), 18, BLACK)
    p.put(X(3), Y(20), BLACK); p.put(X(56), Y(20), BLACK)
    # cabin
    p.poly([(X(12), Y(20)), (X(18), Y(8)), (X(44), Y(8)), (X(52), Y(20))], body)
    p.poly([(X(12), Y(20)), (X(18), Y(8)), (X(44), Y(8)), (X(52), Y(20))], body)
    for (x0, y0, x1, y1) in ((12, 20, 18, 8), (44, 8, 52, 20)):
        # outline the slanted pillars
        n = max(abs(x1 - x0), abs(y1 - y0))
        for i in range(n + 1):
            p.put(X(round(x0 + (x1 - x0) * i / n)), Y(round(y0 + (y1 - y0) * i / n)), BLACK)
    p.hline(X(18), Y(8), 27, BLACK)
    # windows: rear and front, cyan with a white pillar between
    p.poly([(X(15), Y(19)), (X(20), Y(10)), (X(29), Y(10)), (X(29), Y(19))], CYAN)
    p.poly([(X(33), Y(19)), (X(33), Y(10)), (X(42), Y(10)), (X(49), Y(19))], CYAN)
    p.hline(X(30), Y(10), 3, body)
    # light bar on the roof
    p.fill(X(22), Y(4), 18, 4, BLACK)
    p.fill(X(24), Y(5), 4, 2, lamp_left)
    p.fill(X(34), Y(5), 4, 2, lamp_right)
    # door line, handle
    p.vline(X(31), Y(21), 16, BLACK)
    p.hline(X(33), Y(26), 3, BLACK)
    # blue stripe and lettering
    p.hline(X(8), Y(22), 44, BLUE)
    p.text(X(10), Y(29), "POLICE", BLUE)
    # lights
    p.fill(X(54), Y(24), 2, 3, YELLOW)
    p.fill(X(4), Y(24), 2, 3, RED)
    # bumper
    p.hline(X(3), Y(35), 54, DGRAY)
    # wheel arches and wheels
    for wx in (16, 44):
        p.disc(X(wx), Y(37), 7, BLACK)
        p.disc(X(wx), Y(37), 6, DGRAY)
        p.disc(X(wx), Y(37), 3, BLACK)
        p.disc(X(wx), Y(37), 1, body)


# ---------------------------------------------------------------------------
# The cruiser from the front three-quarter, nose to the lower left.  60 wide,
# 50 tall in multicolour pixels.  Oblique: the length axis runs (+30, -10).
# ---------------------------------------------------------------------------
def draw_cruiser_34(p, ox, oy, lamp_left=RED, lamp_right=BLUE, body=WHITE, glass=CYAN):
    X = lambda x: ox + x
    Y = lambda y: oy + y
    P = lambda pts: [(X(a), Y(b)) for (a, b) in pts]
    # shadow, then the far rear wheel under the body
    p.poly(P([(2, 46), (30, 46), (60, 36), (34, 36)]), DGRAY)
    p.disc(X(50), Y(38), 5, BLACK)
    p.disc(X(50), Y(38), 4, DGRAY)
    p.disc(X(50), Y(38), 2, BLACK)
    # side face and front face
    p.poly(P([(26, 26), (56, 16), (56, 34), (26, 44)]), body)
    p.poly(P([(4, 26), (26, 26), (26, 44), (4, 44)]), body)
    # hood, windshield, roof, cabin side
    p.poly(P([(4, 26), (26, 26), (38, 22), (16, 22)]), body)
    p.poly(P([(16, 22), (38, 22), (42, 12), (22, 12)]), glass)
    p.poly(P([(22, 12), (42, 12), (52, 9), (32, 9)]), body)
    p.poly(P([(38, 22), (56, 16), (56, 14), (52, 9), (42, 12)]), body)
    p.poly(P([(40, 21), (50, 18), (50, 12), (43, 14)]), glass)
    p.poly(P([(51, 17), (55, 16), (55, 12), (51, 12)]), glass)
    # outlines
    for (a, b) in (((4, 26), (26, 26)), ((26, 26), (56, 16)), ((56, 16), (56, 34)), ((56, 34), (26, 44)),
                   ((26, 44), (4, 44)), ((4, 44), (4, 26)), ((26, 26), (26, 44)), ((4, 26), (16, 22)),
                   ((26, 26), (38, 22)), ((16, 22), (38, 22)), ((16, 22), (22, 12)), ((38, 22), (42, 12)),
                   ((22, 12), (42, 12)), ((42, 12), (52, 9)), ((22, 12), (32, 9)), ((32, 9), (52, 9)),
                   ((52, 9), (56, 14)), ((38, 22), (56, 16))):
        p.line(X(a[0]), Y(a[1]), X(b[0]), Y(b[1]), BLACK)
    p.line(X(50), Y(18), X(50), Y(12), body)
    # light bar on the roof
    p.poly(P([(24, 10), (44, 10), (46, 7), (26, 7)]), BLACK)
    p.fill(X(27), Y(8), 4, 2, lamp_left)
    p.fill(X(38), Y(8), 4, 2, lamp_right)
    # front: grille, headlights, bumper, plate
    p.fill(X(9), Y(30), 12, 5, BLACK)
    p.hline(X(10), Y(32), 10, DGRAY)
    p.fill(X(5), Y(28), 3, 3, YELLOW)
    p.fill(X(22), Y(28), 3, 3, YELLOW)
    p.fill(X(4), Y(41), 22, 2, DGRAY)
    p.fill(X(12), Y(37), 6, 3, body)
    p.hline(X(13), Y(38), 4, BLACK)
    # side: stripe, door line, lettering
    p.line(X(28), Y(33), X(54), Y(24), BLUE)
    p.line(X(28), Y(34), X(54), Y(25), BLUE)
    p.line(X(40), Y(21), X(40), Y(39), BLACK)
    p.text(X(28), Y(35), "POLICE", BLUE)
    p.fill(X(54), Y(27), 2, 3, RED)
    # near front wheel, over everything
    p.disc(X(12), Y(44), 7, BLACK)
    p.disc(X(12), Y(44), 6, DGRAY)
    p.disc(X(12), Y(44), 3, BLACK)
    p.disc(X(12), Y(44), 1, body)


# ---------------------------------------------------------------------------
# A: expanded hardware sprite (12x21 multicolour, x/y expand = 48x42 real)
# ---------------------------------------------------------------------------
def render_sprite(scale):
    # sprite pixel values: 1 = MC0 black, 2 = sprite colour white, 3 = MC1 white
    rows = []
    art = [r.ljust(12, '.') for r in CAR_M_UP]
    while len(art) < 21:
        art.append('.' * 12)
    # centre the 6-wide car in 12
    off = (12 - 6) // 2
    grid = [['.'] * 12 for _ in range(21)]
    for y, r in enumerate(art):
        for x, ch in enumerate(r[:6] if len(r.strip('.')) <= 6 else r):
            if ch != '.':
                grid[y][x + off] = ch
    # beacon overlay: lamps on the roof at rows 7-8
    lamps = {(off + 1, 7): RED, (off + 4, 7): BLUE}
    asphalt = RGB[DGRAY]
    for y in range(21):
        row = []
        for x in range(12):
            ch = grid[y][x]
            rgb = asphalt
            if ch == '1':
                rgb = RGB[BLACK]
            elif ch == '2':
                rgb = RGB[WHITE]
            elif ch == '3':
                rgb = RGB[LGRAY]
            if (x, y) in lamps:
                rgb = RGB[lamps[(x, y)]]
            # expanded multicolour pixel: 4 real px wide, 2 tall
            row += [rgb] * (4 * scale)
        for _ in range(2 * scale):
            rows.append(row)
    return rows


# ---------------------------------------------------------------------------
# B: character block, 16x12 cells = 64x96 multicolour px = 128x96 real
# ---------------------------------------------------------------------------
def render_block(scale):
    p = Pix(64, 96, BLACK)
    # showroom floor
    p.fill(0, 72, 64, 24, DGRAY)
    p.dither(0, 70, 64, 2, DGRAY, BLACK)
    draw_cruiser(p, 4, 26)
    fixed = p.quantise({BLACK, DGRAY, WHITE}, 1)
    return p.render(scale), fixed


def render_block34(scale):
    p = Pix(64, 96, BLACK)
    p.fill(0, 72, 64, 24, DGRAY)
    p.dither(0, 70, 64, 2, DGRAY, BLACK)
    draw_cruiser_34(p, 2, 24)
    fixed = p.quantise({BLACK, DGRAY, WHITE}, 1)
    return p.render(scale), fixed


def render_still_night(scale):
    p = Pix(160, 200, BLACK)
    # night sky: black to blue to purple at the horizon
    p.fill(0, 60, 160, 20, BLUE)
    p.dither(0, 52, 160, 8, BLACK, BLUE)
    p.fill(0, 80, 160, 12, PURPLE)
    p.dither(0, 78, 160, 4, BLUE, PURPLE)
    for (x, y) in ((12, 10), (40, 22), (70, 6), (95, 30), (120, 14), (150, 26), (28, 40), (140, 44)):
        p.put(x, y, WHITE)
    p.disc(128, 22, 9, LGRAY)
    p.disc(124, 20, 8, BLACK)
    # skyline with lit windows
    for (x, w, h) in ((4, 10, 30), (16, 8, 44), (26, 14, 36), (42, 10, 52), (54, 12, 40), (68, 8, 48), (78, 16, 34),
                      (130, 10, 42), (142, 14, 30)):
        p.fill(x, 96 - h, w, h, DGRAY)
        for wy in range(96 - h + 3, 94, 4):
            for wx in range(x + 1, x + w - 1, 3):
                if (wx * 7 + wy) % 3:
                    p.put(wx, wy, YELLOW)
    # neon sign over the club
    p.fill(84, 60, 44, 36, DGRAY)
    p.fill(88, 66, 36, 10, BLACK)
    p.text(92, 68, "VICE", PINK)
    p.text(112, 68, "CLUB", CYAN)
    p.hline(88, 78, 36, PINK)
    for wy in range(84, 94, 4):
        for wx in range(90, 124, 4):
            p.fill(wx, wy, 2, 2, CYAN)
    # wet road with a neon reflection and the beacon's colour on the ground
    p.fill(0, 96, 160, 104, DGRAY)
    p.hline(0, 96, 160, LGRAY)
    p.dither(88, 98, 36, 10, DGRAY, PINK)
    for x in range(0, 160, 16):
        p.hline(x, 150, 8, WHITE)
    # street lamp pools
    for lx in (24, 140):
        p.vline(lx, 70, 30, BLACK)
        p.fill(lx - 2, 68, 5, 2, YELLOW)
        p.dither(lx - 10, 100, 21, 6, DGRAY, YELLOW)
    # the cruiser, three-quarter, doubled, with red and blue light on the road
    p.dither(0, 178, 22, 10, DGRAY, RED)
    p.dither(146, 160, 14, 10, DGRAY, BLUE)
    p.dither(60, 190, 60, 6, DGRAY, PURPLE)
    tmp = Pix(64, 52, None)
    draw_cruiser_34(tmp, 2, 2)
    for y in range(52):
        for x in range(64):
            c = tmp.p[y][x]
            if c is None:
                continue
            for dy in range(2):
                for dx in range(2):
                    p.put(20 + x * 2 + dx, 92 + y * 2 + dy, c)
    fixed = p.quantise({BLACK}, 3)
    return p.render(scale), fixed


# ---------------------------------------------------------------------------
# C: multicolour bitmap still, 160x200 multicolour px = 320x200 real
# ---------------------------------------------------------------------------
def render_still(scale):
    p = Pix(160, 200, BLACK)
    # sunset sky in dithered bands
    bands = [(YELLOW, 0, 14), (ORANGE, 14, 34), (PINK, 34, 54), (PURPLE, 54, 74), (BLUE, 74, 96)]
    for i, (c, y0, y1) in enumerate(bands):
        p.fill(0, y0, 160, y1 - y0, c)
        if i > 0:
            pc = bands[i - 1][0]
            p.dither(0, y0 - 3, 160, 6, pc, c)
    p.disc(112, 40, 16, YELLOW)
    p.dither(96, 24, 32, 6, YELLOW, ORANGE)
    # skyline
    for (x, w, h) in ((4, 10, 30), (16, 8, 44), (26, 14, 36), (42, 10, 52), (54, 12, 40), (68, 8, 48), (78, 16, 34),
                      (130, 10, 42), (142, 14, 30)):
        p.fill(x, 96 - h, w, h, DGRAY)
        for wy in range(96 - h + 3, 94, 4):
            for wx in range(x + 1, x + w - 1, 3):
                if (wx * 7 + wy) % 5:
                    p.put(wx, wy, YELLOW)
    # ocean and beach
    p.fill(0, 96, 160, 24, LBLUE)
    for row in range(98, 120, 4):
        off = (row // 4) % 2 * 3
        for x in range(off, 160, 8):
            p.hline(x, row, 3, WHITE)
    p.fill(0, 120, 160, 16, YELLOW)
    p.dither(0, 118, 160, 4, LBLUE, YELLOW)
    # palms
    for px_ in (20, 132):
        p.vline(px_, 100, 36, BLACK)
        p.vline(px_ + 1, 101, 35, BLACK)
        for (dx, dy, ln) in ((-9, 98, 10), (2, 97, 10), (-6, 95, 7), (4, 95, 6)):
            p.hline(px_ + dx, dy, ln, BLACK)
    # road
    p.fill(0, 136, 160, 64, DGRAY)
    p.hline(0, 136, 160, LGRAY)
    for x in range(0, 160, 16):
        p.hline(x, 168, 8, WHITE)
    # the cruiser, drawn twice the size by doubling pixels of a 56x44 drawing
    tmp = Pix(64, 48, None)
    draw_cruiser(tmp, 4, 2)
    for y in range(48):
        for x in range(64):
            c = tmp.p[y][x]
            if c is None:
                continue
            for dy in range(2):
                for dx in range(2):
                    p.put(20 + x * 2 + dx, 100 + y * 2 + dy, c)
    p.fill(28, 196, 116, 2, BLACK)     # shadow under the car
    fixed = p.quantise({BLACK}, 3)
    return p.render(scale), fixed


def data_uri(rows, path):
    write_png(path, rows)
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def main():
    outdir, out_html = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    a = data_uri(render_sprite(2), os.path.join(outdir, "a-sprite.png"))
    # three-quarter views: generated with gpt-image-2 and quantised by b64quant.py
    # when those files exist, otherwise the procedural drawings
    import json
    def ai_or(name, fallback_fn, fallback_name):
        path = os.path.join(outdir, name)
        meta = os.path.splitext(path)[0] + ".json"
        if os.path.isfile(path) and os.path.isfile(meta):
            m = json.load(open(meta))
            with open(path, "rb") as f:
                uri = "data:image/png;base64," + base64.b64encode(f.read()).decode()
            return uri, f"gpt-image-2 art, quantised · {m['cells_fixed']} of {m['cells_total']} cells fixed"
        rows, fixed = fallback_fn(2)
        return data_uri(rows, os.path.join(outdir, fallback_name)), f"procedural · {fixed} cells quantised"
    b, bcap = ai_or("ai-block-side.png", render_block, "b-block.png")
    c, ccap = ai_or("ai-still-day.png", render_still, "c-still.png")
    b2, b2cap = ai_or("ai-block-34.png", render_block34, "b-block-34.png")
    c2, c2cap = ai_or("ai-still-night.png", render_still_night, "c-still-night.png")
    print(f"side block: {bcap}; day still: {ccap}; 3/4 block: {b2cap}; night still: {c2cap}")
    html = HTML.replace("__A__", a).replace("__B__", b).replace("__C__", c).replace("__B2__", b2).replace("__C2__", c2)
    html = (html.replace("__BCAP__", bcap).replace("__CCAP__", ccap)
                .replace("__B2CAP__", b2cap).replace("__C2CAP__", c2cap))
    with open(out_html, "w") as f:
        f.write(html)


HTML = r'''<title>Vehicle Portrait Formats</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Silkscreen:wght@400;700&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
  :root { --paper:#eceef5; --paper-2:#e1e3ee; --card:#f6f7fb; --ink:#1b1a3a; --muted:#5c5b7a; --line:#c6c8da; --accent:#40318d; --accent-2:#7869c4; --pick:#2f7b52; --pick-ink:#ffffff; }
  @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --paper:#14132b; --paper-2:#1d1c38; --card:#1a1934; --ink:#e8e7f2; --muted:#9d9cc0; --line:#2e2d4c; --accent:#8f82d6; --accent-2:#7869c4; --pick:#6fcf97; --pick-ink:#14132b; } }
  :root[data-theme="dark"] { --paper:#14132b; --paper-2:#1d1c38; --card:#1a1934; --ink:#e8e7f2; --muted:#9d9cc0; --line:#2e2d4c; --accent:#8f82d6; --accent-2:#7869c4; --pick:#6fcf97; --pick-ink:#14132b; }
  * { box-sizing: border-box; }
  body { background: var(--paper); color: var(--ink); font-family: "IBM Plex Sans", "Helvetica Neue", Arial, sans-serif; font-size: 16px; line-height: 1.55; padding-inline: clamp(16px, 4vw, 48px); padding-block: 36px 72px; }
  .wrap { max-width: 1080px; margin: 0 auto; display: grid; gap: 36px; }
  header { display: grid; gap: 10px; border-bottom: 2px solid var(--accent); padding-bottom: 18px; }
  .eyebrow { font-family: "Silkscreen", monospace; font-size: 11px; letter-spacing: .12em; text-transform: uppercase; color: var(--accent); }
  h1 { font-family: "Silkscreen", monospace; font-weight: 700; font-size: clamp(20px, 3.5vw, 30px); margin: 0; line-height: 1.15; text-wrap: balance; }
  header p { margin: 0; color: var(--muted); max-width: 66ch; }
  .opt { display: grid; grid-template-columns: minmax(0, 1fr) minmax(280px, 380px); gap: 24px; align-items: start; }
  .stage { background: #101018; border: 1px solid var(--line); padding: 18px; display: grid; place-items: center; min-height: 240px; }
  .stage img { image-rendering: pixelated; max-width: 100%; height: auto; }
  .stage.two { grid-template-columns: 1fr 1fr; gap: 14px; }
  .stage.two figure { display: grid; justify-items: center; }
  @media (max-width: 560px) { .stage.two { grid-template-columns: 1fr; } }
  .stage figcaption { font-family: "IBM Plex Mono", monospace; font-size: 12px; color: #9d9cc0; margin-top: 10px; text-align: center; }
  figure { margin: 0; }
  .meta { display: grid; gap: 12px; }
  .meta .num { font-family: "Silkscreen", monospace; font-size: 12px; color: var(--accent); letter-spacing: .1em; }
  .meta h2 { font-family: "Silkscreen", monospace; font-weight: 700; font-size: 18px; margin: 0; line-height: 1.2; }
  .meta h2 .pick { display: inline-block; margin-left: 10px; padding: 2px 8px; font-size: 10px; letter-spacing: .1em; color: var(--pick-ink); background: var(--pick); vertical-align: middle; }
  dl { display: grid; grid-template-columns: max-content 1fr; gap: 4px 14px; margin: 0; font-family: "IBM Plex Mono", monospace; font-size: 13px; font-variant-numeric: tabular-nums; }
  dt { color: var(--muted); } dd { margin: 0; }
  .meta p { margin: 0; font-size: 15px; } .meta p b { font-weight: 600; }
  table { border-collapse: collapse; width: 100%; font-size: 14px; }
  th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }
  th { font-family: "Silkscreen", monospace; font-size: 10px; letter-spacing: .1em; color: var(--accent); text-transform: uppercase; }
  .tablewrap { overflow-x: auto; }
  .verdict { padding: 18px 22px; border: 1px solid var(--line); background: var(--paper-2); display: grid; gap: 8px; }
  .verdict h2 { font-family: "Silkscreen", monospace; font-size: 15px; margin: 0; color: var(--pick); }
  .verdict p { margin: 0; max-width: 72ch; }
  footer { color: var(--muted); font-size: 13px; }
  @media (max-width: 760px) { .opt { grid-template-columns: 1fr; } }
</style>
<div class="wrap">
  <header>
    <div class="eyebrow">backlot-64 · the same police cruiser three ways</div>
    <h1>How big can a vehicle be on a C64?</h1>
    <p>Three formats for showing a vehicle larger than its playfield sprite: in about screens, the garage, and cutscenes. Every image below went through a converter that enforces that mode's real colour rules and was rendered at C64 pixel scale, so this is what the chip would display. The block and still art was generated with gpt-image-2 under the engine's art-style contract and quantised by the block and still packers, which is the intended pipeline for the 150 portraits and the cutscene frames. The expanded sprite is the engine's own top-down drawing.</p>
  </header>

  <section class="opt">
    <figure class="stage"><img src="__A__" alt="The cruiser as an expanded hardware sprite, 48 by 42 pixels with four-wide pixels" width="192" height="168"><figcaption>48 × 42 real pixels, shown at 4×</figcaption></figure>
    <div class="meta">
      <div class="num">OPTION A</div>
      <h2>Expanded sprite</h2>
      <dl>
        <dt>Size</dt><dd>48 × 42 px from one sprite; 192 × 84 from eight stacked</dd>
        <dt>Pixel</dt><dd>4 wide × 2 tall</dd>
        <dt>Colours</dt><dd>3 per sprite + transparent, plus overlays</dd>
        <dt>Data</dt><dd>0 extra: the playfield drawing, zoomed by hardware</dd>
        <dt>To show</dt><dd>2 register writes</dd>
        <dt>Works with playfield</dt><dd>Yes</dd>
      </dl>
      <p><b>Buys</b> a bigger car for nothing. The VIC-II doubles the sprite in both axes and the beacon overlay expands with it.</p>
      <p><b>Costs</b> the look. It is the top-down drawing with pixels the size of bricks. Fine as a garage thumbnail or a pickup marker, not as a portrait.</p>
    </div>
  </section>

  <section class="opt">
    <div class="stage two">
      <figure><img src="__B__" alt="The cruiser as a 20 by 8 character block, side view"><figcaption>Side view, 20 × 8 cells (160 × 64 px) · __BCAP__</figcaption></figure>
      <figure><img src="__B2__" alt="The cruiser as a 16 by 12 character block, front three-quarter view"><figcaption>Three-quarter, 16 × 12 cells (128 × 96 px) · __B2CAP__</figcaption></figure>
    </div>
    <div class="meta">
      <div class="num">OPTION B</div>
      <h2>Character block <span class="pick">RECOMMENDED</span></h2>
      <dl>
        <dt>Size</dt><dd>Any shape up to 192 cells: 16 × 12 for a three-quarter portrait, 20 × 8 for a profile</dd>
        <dt>Pixel</dt><dd>2 wide × 1 tall</dd>
        <dt>Colours</dt><dd>4 per cell: 3 shared + 1 per cell</dd>
        <dt>Data</dt><dd>~1.5 KB charset + 200 B map per portrait; 150 portraits ≈ 300 KB</dd>
        <dt>To show</dt><dd>One 1.5 KB DMA plus 200 cell writes, ~3,000 cycles</dd>
        <dt>Works with playfield</dt><dd>No: it uses the scene's charset. Yes with text and sprites.</dd>
      </dl>
      <p><b>Buys</b> a real portrait: a new drawing from the side or three-quarter view. Both here were generated by gpt-image-2 against the engine's art-style contract and then quantised by the block packer, so they are at full multicolour detail, with lettering, a light bar that flashes through the same beacon overlay as in play, wheels that turn through charset animation, and text beside it from the font in the other 64 cells.</p>
      <p><b>Costs</b> the scene charset, so it lives on screens that are not the playfield: about, garage, cutscene inserts. And it costs a drawing per vehicle.</p>
    </div>
  </section>

  <section class="opt">
    <div class="stage two">
      <figure><img src="__C__" alt="A full-screen multicolour bitmap still: sunset over Vice City with the cruiser on the beach road" width="320" height="200"><figcaption>Day, side view · __CCAP__</figcaption></figure>
      <figure><img src="__C2__" alt="A night bitmap still: neon club, street lamps, and the cruiser from the front three-quarter with its beacon lighting the road" width="320" height="200"><figcaption>Night, three-quarter · __C2CAP__</figcaption></figure>
    </div>
    <div class="meta">
      <div class="num">OPTION C</div>
      <h2>Bitmap still</h2>
      <dl>
        <dt>Size</dt><dd>320 × 200 px, the whole screen</dd>
        <dt>Pixel</dt><dd>2 wide × 1 tall</dd>
        <dt>Colours</dt><dd>4 per cell: 1 shared + 3 per cell, any of the 16</dd>
        <dt>Data</dt><dd>10 KB per still; 800 stills per 8 MB</dd>
        <dt>To show</dt><dd>One 10 KB DMA behind a fade, ~10,000 cycles</dd>
        <dt>Works with playfield</dt><dd>No. Sprites yes, text only as part of the picture.</dd>
      </dl>
      <p><b>Buys</b> the most colour the chip can put on screen: three free colours per cell from all 16, so gradients, skylines, and lighting are possible. This is for painted cutscene frames where the whole screen is the picture.</p>
      <p><b>Costs</b> flexibility. The car is baked into this scene at this position; another angle or another street is another 10 KB. The playfield engine is not running while a still is up.</p>
    </div>
  </section>

  <section class="tablewrap">
    <table>
      <thead><tr><th>Use</th><th>Format</th><th>Why</th></tr></thead>
      <tbody>
        <tr><td>Garage list, shop, pickup markers</td><td>A: expanded sprite</td><td>Free, instant, and it sits on top of the playfield</td></tr>
        <tr><td>About screens, garage detail, vehicle stats</td><td>B: character block</td><td>Portrait quality, composes with text and sprites, 2 KB each</td></tr>
        <tr><td>Cutscene inserts: a car pulls up, a hand-off at the dock</td><td>B on a C background</td><td>The still is the set, the block is the prop, sprites are the cast, the beacon flashes</td></tr>
        <tr><td>Establishing shots, title cards, endings</td><td>C: bitmap still</td><td>The whole screen is the picture</td></tr>
      </tbody>
    </table>
  </section>

  <section class="verdict">
    <h2>RECOMMENDATION</h2>
    <p>Character blocks as the vehicle portrait format, one per type, drawn from the side or three-quarter view at 128 × 96. Bitmap stills for full painted frames. A cutscene is a still background with blocks placed on it, sprites over that, and text from the font, all referenced by slot from a script. The engine work is one block packer and one placement routine; the art work is 150 drawings, which is the same conclusion the sprite roster reached.</p>
  </section>

  <footer>Generated by tools/b64formats.py in the backlot-64 repository. Portraits and stills are gpt-image-2 output from art-style.md, converted by tools/b64quant.py. The generated originals are kept in images/ with their candidate sets archived alongside.</footer>
</div>
'''

if __name__ == "__main__":
    main()
