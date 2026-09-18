#!/usr/bin/env python3
"""backlot-64 tileset packer.

A tileset is:
    charset      2048 bytes   192 scene cells + 64 font cells (192-255)
    mtchars      4096 bytes   256 metatiles x 16 screen codes (4x4, row-major)
    mtcolumns    4096 bytes   the same codes column-major, so a column fill
                              reads each metatile's four cells in a run
    props         256 bytes   per-metatile properties
    (padded to 12 KB)

A scene cell's colour is the low four bits of its screen code (bit 3 set =
multicolour), so there is no colour table: the scroller writes colour RAM
from the screen itself.  The packer assigns the codes.  Codes 0-191 give
twelve per colour value, so a tileset may use at most twelve characters
that show a given cell colour; a character that never shows the cell
colour (no '11' pixel pairs in multicolour) fits any bucket of its mode.
After Lasse Öörni (Cadaver), c64gameframework (macros.s), colour packed
into the screen code.  As is.

Metatiles are drawn on a 4x4-cell multicolour canvas with the same drawing
primitives as the Priors-64 demos (tools/b64art.py), then deduped into the charset.

usage: b64tileset.py <tileset-name> <out.bin> [--sprites out.spr]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from b64art import (  # noqa: E402
    BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW,
    ORANGE, BROWN, PINK, DGRAY, MGRAY, LGREEN, LBLUE, LGRAY,
    Canvas, FONT, encode_sprite, car_frames_mc, ped_frames_mc,
)

# properties byte
P_SOLID = 0x80
P_WATER = 0x40
P_SIDEWALK = 0x20
P_DOOR = 0x10
P_ROAD_E = 0x01
P_ROAD_W = 0x02
P_ROAD_S = 0x04
P_ROAD_N = 0x08
P_ROAD_HV = P_ROAD_E | P_ROAD_W
P_ROAD_VV = P_ROAD_N | P_ROAD_S
P_ROAD_ALL = 0x0F

FONT_BASE = 192

# The nine luma levels of every VIC-II after the 6569R1, 0..8, indexed by
# palette entry: black, then seven pairs of equal luma, then white.
# After Philip "Pepto" Timmermann, "Commodore VIC-II Color Analysis" (the
# late-revision luma order 0 / 6,9 / 2,B / 4,8 / C,E / 5,A / 3,F / 7,D / 1).  As is.
# The levels are not evenly spaced (0, 8, 10, 12, 15, 16, 20, 24, 32 of 32),
# so an index step is a rank, not a distance.  See docs/ART.md section 2.
LUMA = [0, 8, 2, 6, 3, 5, 1, 7, 3, 1, 5, 2, 4, 7, 4, 6]
COLOUR_NAMES = ["black", "white", "red", "cyan", "purple", "green", "blue", "yellow",
                "orange", "brown", "pink", "dgray", "mgray", "lgreen", "lblue", "lgray"]
DITHER_MAX_STEP = 2


def check_dither(name, canvas, bg):
    """Warn about checkerboard dithers between colours too far apart in
    luminance to blend.  A cell is a dither if most of its 2x2 windows
    alternate two values."""
    warnings = []
    for cy in range(canvas.h):
        for cx in range(canvas.w):
            pairs = {}
            windows = 0
            for y in range(cy * 8, cy * 8 + 7):
                for x in range(cx * 4, cx * 4 + 3):
                    a, b = canvas.px[y][x], canvas.px[y][x + 1]
                    c, d = canvas.px[y + 1][x], canvas.px[y + 1][x + 1]
                    windows += 1
                    if a == d and b == c and a != b:
                        pairs[(min(a, b), max(a, b))] = pairs.get((min(a, b), max(a, b)), 0) + 1
            for (va, vb), n in pairs.items():
                if n < windows // 2:
                    continue
                col = canvas.col[cy][cx]
                ca = bg[va] if va < 3 else col
                cb = bg[vb] if vb < 3 else col
                if abs(LUMA[ca] - LUMA[cb]) > DITHER_MAX_STEP:
                    w = (f"  {name}: dither {COLOUR_NAMES[ca]}+{COLOUR_NAMES[cb]} "
                         f"spans {abs(LUMA[ca] - LUMA[cb])} luminance steps, reads as texture not shade")
                    if w not in warnings:
                        warnings.append(w)
    return warnings


class Tileset:
    def __init__(self, name, bg):
        self.name = name
        self.bg = bg                      # (bg0, bg1, bg2) documented, not stored
        self.chars = {}
        self.order = []
        self.metatiles = []               # list of (cells[16], cols[16], props)
        self.names = {}
        # reserve the font first so its indices are fixed
        self._reserve_font()

    def _reserve_font(self):
        # chars 0..191 are scene cells; reserve 192..255 for the font by
        # filling the dict with placeholders that dedupe never hits.
        for i in range(FONT_BASE):
            pass
        self.font = bytearray()
        for code in range(32, 96):
            ch = chr(code)
            g = FONT.get(ch, FONT[' '])
            rows = []
            for r in range(8):
                b = 0
                if 1 <= r <= 5:
                    for c, bit in enumerate(g[r - 1]):
                        if bit == '1':
                            b |= 0b11 << (6 - 2 * c)
                rows.append(b)
            self.font += bytes(rows)

    def add(self, name, canvas, props=0):
        for w in check_dither(name, canvas, self.bg):
            print("warning:" + w)
        cs, screen, color, n = canvas.export(self.chars, self.order)
        if len(self.order) > FONT_BASE:
            raise SystemExit(f"tileset {self.name}: more than {FONT_BASE} scene cells at metatile {name}")
        idx = len(self.metatiles)
        self.metatiles.append((bytes(screen), bytes(color), props))
        self.names[name] = idx
        return idx

    def pack(self):
        """Re-code the scene characters so every code's low four bits are
        the colour its cells show, and build charset, metatiles and props."""
        per_bucket = FONT_BASE // 16                # codes v, v+16, ... below the font: 12

        def shows_cell_colour(ch, colour):
            key = self.order[ch]
            if colour >= 8:                         # multicolour: '11' pairs take the cell colour
                return any(((b >> sh) & 3) == 3 for b in key for sh in (0, 2, 4, 6))
            return any(key)                         # hires: every set pixel is the cell colour

        pairs = sorted({(ch, col & 15) for cells, cols, _ in self.metatiles for ch, col in zip(cells, cols)})
        fixed = [(ch, col) for ch, col in pairs if shows_cell_colour(ch, col)]
        need = {}
        for _, col in fixed:
            need[col] = need.get(col, 0) + 1
        over = {v: n for v, n in need.items() if n > per_bucket}
        if over:
            raise SystemExit(f"tileset {self.name}: colour values {over} each need more than {per_bucket} characters; "
                             f"the colour is packed in the screen code (docs/PREPARE.md, tilesets)")
        buckets = {v: [] for v in range(16)}        # colour value -> characters, in code order
        placement = {}                              # (character, colour value) -> code

        def place(ch, v):
            if (ch, v) not in placement:
                if len(buckets[v]) >= per_bucket:
                    raise SystemExit(f"tileset {self.name}: colour value {v} is full ({per_bucket} characters)")
                placement[(ch, v)] = v + 16 * len(buckets[v])
                buckets[v].append(ch)
            return placement[(ch, v)]

        code_of = {}
        for ch, col in fixed:                       # characters that show their colour have no choice
            code_of[(ch, col)] = place(ch, col)
        for ch, col in pairs:                       # the rest go wherever their mode has room
            if (ch, col) in code_of:
                continue
            modes = range(8, 16) if col >= 8 else range(0, 8)
            home = [v for v in modes if (ch, v) in placement]
            v = home[0] if home else min(modes, key=lambda b: len(buckets[b]))
            code_of[(ch, col)] = place(ch, v)
        charset = bytearray(FONT_BASE * 8)
        for (ch, v), code in placement.items():
            charset[code * 8:code * 8 + 8] = bytes(self.order[ch])
        charset += self.font
        assert len(charset) == 2048
        mtchars = bytearray(4096)
        mtcolumns = bytearray(4096)
        props = bytearray(256)
        for i, (cells, cols, p) in enumerate(self.metatiles):
            codes = [code_of[(ch, col & 15)] for ch, col in zip(cells, cols)]
            mtchars[i * 16:(i + 1) * 16] = bytes(codes)
            mtcolumns[i * 16:(i + 1) * 16] = bytes(codes[r * 4 + c] for c in range(4) for r in range(4))
            props[i] = p
        self.used = {v: len(b) for v, b in buckets.items() if b}
        blob = charset + mtchars + mtcolumns + props
        blob += bytes(12 * 1024 - len(blob))
        return bytes(blob)

    def write_inc(self, path):
        with open(path, "w") as f:
            f.write(f"; metatile ids for tileset {self.name}\n")
            for name, idx in self.names.items():
                f.write(f"MT_{name.upper():<16} = {idx}\n")


def mc():
    return Canvas(True, 4, 4)


# ---------------------------------------------------------------------------
# Bellamar, day.  bg0 dark grey (asphalt), bg1 light grey (sidewalk, walls),
# bg2 white (edges, dashes, foam).  v3 = per-cell colour.
# ---------------------------------------------------------------------------
def bellamar_day():
    ts = Tileset("bellamar_day", (DGRAY, LGRAY, WHITE))

    c = mc(); c.cdots(0, 0, 4, 4, 3, 0, GREEN, 4, 4); ts.add("grass", c)
    c = mc(); c.cfill(0, 0, 4, 4, 3, CYAN)
    for row in range(2, 32, 8):
        off = (row // 8) % 2 * 3
        c.dashes(off, row, 16 - off, 3, 5, 2)
    ts.add("water", c, P_WATER)
    c = mc(); c.cdots(0, 0, 4, 4, 3, 0, YELLOW, 4, 4); ts.add("sand", c)
    c = mc(); c.cdots(0, 0, 4, 4, 1, 0, BLUE, 8, 8); ts.add("sidewalk", c, P_SIDEWALK)

    # roads: asphalt v0, curbs v1, dashes v2
    c = mc(); c.cfill(0, 0, 4, 4, 0, WHITE)
    c.hline(0, 0, 16, 1); c.hline(0, 31, 16, 1); c.dashes(0, 15, 16, 4, 4, 2)
    ts.add("road_h", c, P_ROAD_HV)
    c = mc(); c.cfill(0, 0, 4, 4, 0, WHITE)
    c.vline(0, 0, 32, 1); c.vline(15, 0, 32, 1); c.vdashes(7, 0, 32, 8, 8, 2)
    ts.add("road_v", c, P_ROAD_VV)
    c = mc(); c.cfill(0, 0, 4, 4, 0, WHITE); ts.add("cross", c, P_ROAD_ALL)

    # roofs: v3 body, v2 lit top/left edge, v0 rooftop unit
    for name, col in (("roof_cyan", CYAN), ("roof_purple", PURPLE), ("roof_yellow", YELLOW),
                      ("roof_white", WHITE), ("roof_red", RED), ("roof_green", GREEN)):
        c = mc(); c.cfill(0, 0, 4, 4, 3, col)
        c.hline(0, 0, 16, 2); c.vline(0, 0, 32, 2); c.rect(3, 3, 3, 3, 0)
        ts.add(name, c, P_SOLID)
    # roof interior (no edges) so bigger buildings tile
    for name, col in (("roofi_cyan", CYAN), ("roofi_purple", PURPLE), ("roofi_yellow", YELLOW),
                      ("roofi_white", WHITE), ("roofi_red", RED), ("roofi_green", GREEN)):
        c = mc(); c.cfill(0, 0, 4, 4, 3, col)
        ts.add(name, c, P_SOLID)

    # wall: v1 with blue windows, ground line
    c = mc(); c.cfill(0, 0, 4, 4, 1, BLUE)
    for r in range(1, 32, 4):
        for wx in range(1, 15, 3):
            c.fill(wx, r, 2, 2, 3)
    c.hline(0, 31, 16, 0)
    ts.add("wall", c, P_SOLID)
    # sidewalk in a building's shadow
    c = mc(); c.cdither(0, 0, 4, 4, 0, 1, BLUE); ts.add("sidewalk_shadow", c, P_SIDEWALK)
    # door in a wall
    c = mc(); c.cfill(0, 0, 4, 4, 1, BLUE)
    for r in range(1, 32, 4):
        for wx in range(1, 15, 3):
            c.fill(wx, r, 2, 2, 3)
    c.fill(6, 20, 4, 12, 0); c.hline(0, 31, 16, 0)
    ts.add("door", c, P_SOLID | P_DOOR)

    # palm on sidewalk, palm on sand
    for name, base_v, base_col, bv in (("palm_walk", 1, BLUE, 0), ("palm_sand", 3, YELLOW, 0)):
        c = mc()
        if base_v == 1:
            c.cdots(0, 0, 4, 4, 1, 0, BLUE, 8, 8)
        else:
            c.cdots(0, 0, 4, 4, 3, 0, YELLOW, 4, 4)
        c.crect(1, 0, 2, 2, GREEN); c.crect(1, 2, 2, 2, GREEN if base_v == 1 else YELLOW)
        c.hline(5, 2, 6, 3); c.hline(4, 3, 8, 3); c.hline(6, 4, 4, 3); c.put(4, 5, 3); c.put(11, 5, 3)
        c.vline(7, 5, 22, bv); c.vline(8, 6, 21, bv)
        ts.add(name, c, P_SOLID)

    # beach edge: sand over water
    c = mc(); c.cdots(0, 0, 4, 2, 3, 0, YELLOW, 4, 4); c.cfill(0, 2, 4, 2, 3, CYAN)
    c.dashes(0, 20, 16, 3, 5, 2); c.dashes(3, 28, 13, 3, 5, 2)
    ts.add("shore_s", c, P_WATER)
    return ts


TILESETS = {"bellamar_day": bellamar_day}


def main():
    name, out = sys.argv[1], sys.argv[2]
    ts = TILESETS[name]()
    blob = ts.pack()
    with open(out, "wb") as f:
        f.write(blob)
    ts.write_inc(os.path.splitext(out)[0] + ".inc")
    if "--sprites" in sys.argv:
        sp = sys.argv[sys.argv.index("--sprites") + 1]
        frames = car_frames_mc() + ped_frames_mc()
        data = b"".join(encode_sprite(fr, True) for fr in frames)
        data += bytes(4096 - len(data))
        with open(sp, "wb") as f:
            f.write(data)
    print(f"tileset {name}: {len(ts.order)} scene cells, {len(ts.metatiles)} metatiles; "
          f"characters per colour value (at most {FONT_BASE // 16}): {ts.used}")


if __name__ == "__main__":
    main()
