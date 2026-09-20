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
    Char,
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
P_SHALLOW = 0x01                 # on a water metatile (no roads on water): shallow, a marsh
P_ROAD_HV = P_ROAD_E | P_ROAD_W
P_ROAD_VV = P_ROAD_N | P_ROAD_S
P_ROAD_ALL = 0x0F

FONT_BASE = 192

# heights, in storeys of 8 pixels (docs/PHYSICS.md: aircraft clear them).
# Roofs and facades are shared by every building, so Bellamar's buildings
# all stand six storeys for now
BUILDING = 6
PALM = 3

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
        self.heights = []                 # storeys of 8 pixels, by metatile
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

    def add_chars(self, name, chars, props=0, height=0):
        """A metatile built from sixteen characters, row-major, each in its
        own mode (b64art.Char): the way a reference sheet's character set is
        composed into a city.  Characters dedupe across the whole tileset,
        so a metatile that reuses them costs nothing but a table entry."""
        screen, color = bytearray(), bytearray()
        for ch in chars:
            key = ch.bits()
            if key not in self.chars:
                self.chars[key] = len(self.order)
                self.order.append(key)
            screen.append(self.chars[key])
            c = ch.colour & 7
            color.append(c | 8 if ch.mc else c)
        if len(self.order) > FONT_BASE:
            raise SystemExit(f"tileset {self.name}: more than {FONT_BASE} characters")
        idx = len(self.metatiles)
        self.metatiles.append((bytes(screen), bytes(color), props))
        self.names[name] = idx
        self.heights.append(height)
        if bool(height) != bool(props & P_SOLID):
            raise SystemExit(f"tileset {self.name}: {name} must have a height if it is solid, and none otherwise")
        return idx

    def add(self, name, canvas, props=0, height=0):
        """A metatile.  A solid one (P_SOLID) stands height storeys of 8
        pixels, 1 to 15, which aircraft must clear (docs/PHYSICS.md); anything
        else stands none."""
        if bool(props & P_SOLID) != bool(height) or not 0 <= height <= 15:
            raise SystemExit(f"tileset {self.name}: metatile {name}: a solid metatile needs a height of 1-15 "
                             f"storeys and nothing else may have one (got {height})")
        for w in check_dither(name, canvas, self.bg):
            print("warning:" + w)
        cs, screen, color, n = canvas.export(self.chars, self.order)
        if len(self.order) > FONT_BASE:
            raise SystemExit(f"tileset {self.name}: more than {FONT_BASE} scene cells at metatile {name}")
        idx = len(self.metatiles)
        self.metatiles.append((bytes(screen), bytes(color), props))
        self.heights.append(height)
        self.names[name] = idx
        return idx

    def pack(self):
        """Re-code the scene characters so every code's low four bits are
        the colour its cells show, and build charset, metatiles, props and
        heights."""
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
        heights = bytes(self.heights) + bytes(256 - len(self.heights))
        blob = charset + mtchars + mtcolumns + props + heights
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
    # marsh: shallow water in reeds, which boats cannot cross and airboats can.
    # One tuft, the same in every cell: cyan had room for one more character
    c = mc(); c.cfill(0, 0, 4, 4, 3, CYAN)
    for cy in range(4):
        for cx in range(4):
            c.vline(cx * 4 + 1, cy * 8 + 2, 4, 0); c.vline(cx * 4 + 2, cy * 8 + 4, 2, 0)
    ts.add("marsh", c, P_WATER | P_SHALLOW)

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
        ts.add(name, c, P_SOLID, BUILDING)
    # roof interior (no edges) so bigger buildings tile
    for name, col in (("roofi_cyan", CYAN), ("roofi_purple", PURPLE), ("roofi_yellow", YELLOW),
                      ("roofi_white", WHITE), ("roofi_red", RED), ("roofi_green", GREEN)):
        c = mc(); c.cfill(0, 0, 4, 4, 3, col)
        ts.add(name, c, P_SOLID, BUILDING)

    # wall: v1 with blue windows, ground line
    c = mc(); c.cfill(0, 0, 4, 4, 1, BLUE)
    for r in range(1, 32, 4):
        for wx in range(1, 15, 3):
            c.fill(wx, r, 2, 2, 3)
    c.hline(0, 31, 16, 0)
    wall_c = c
    ts.add("wall", c, P_SOLID, BUILDING)
    # sidewalk in a building's shadow
    c = mc(); c.cdither(0, 0, 4, 4, 0, 1, BLUE); ts.add("sidewalk_shadow", c, P_SIDEWALK)
    # door in a wall
    c = mc(); c.cfill(0, 0, 4, 4, 1, BLUE)
    for r in range(1, 32, 4):
        for wx in range(1, 15, 3):
            c.fill(wx, r, 2, 2, 3)
    c.fill(6, 20, 4, 12, 0); c.hline(0, 31, 16, 0)
    door_c = c
    ts.add("door", c, P_SOLID | P_DOOR, BUILDING)

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
        ts.add(name, c, P_SOLID, PALM)

    # beach edge: sand over water
    c = mc(); c.cdots(0, 0, 4, 2, 3, 0, YELLOW, 4, 4); c.cfill(0, 2, 4, 2, 3, CYAN)
    c.dashes(0, 20, 16, 3, 5, 2); c.dashes(3, 28, 13, 3, 5, 2)
    ts.add("shore_s", c, P_WATER)

    # the three-quarter district's own pieces, past the ids the day set has:
    # a building's face is two metatiles tall, an upper storey over a ground
    # floor, under two rows of roof (tools/b64world.py, the 34 district).
    # The day set only needs the ids to line up with bellamar_34's, so it
    # spends nothing on them: drawing the faces here costs characters in
    # colour values that are already full (cyan and blue are 11 and 14 in
    # multicolour, where the cell colour carries bit 3), and the district is
    # meant to be seen with the three-quarter set anyway.
    ts.add("face_top", wall_c, P_SOLID, BUILDING)
    ts.add("face_low", wall_c, P_SOLID, BUILDING)
    ts.add("face_door", door_c, P_SOLID | P_DOOR, BUILDING)
    return ts


# ---------------------------------------------------------------------------
# Bellamar, three-quarter view.  The same metatiles in the same order as
# bellamar_day, so the same world map reads with either: only the art
# differs.  A block's roof rows are seen from above and slightly in front
# (a lit top edge and a parapet along the front), and the row where the day
# set has a flat wall carries the building's face: a cornice, two storeys of
# tall windows with sills, and a dark base standing on the pavement.
# ---------------------------------------------------------------------------
def facade(colour, door=False):
    """The face of a building, 32 pixels high: a cornice, two storeys of tall
    windows with sills, and a base standing on the pavement.  The window
    pattern repeats every cell (4 multicolour pixels), so the whole face
    costs six characters however wide the building is."""
    c = mc(); c.cfill(0, 0, 4, 4, 1, colour)
    c.hline(0, 0, 16, 2); c.hline(0, 1, 16, 2)       # cornice, lit
    c.hline(0, 2, 16, 0)                             # its shadow
    for top in (5, 19):                              # two storeys
        for wx in range(1, 16, 4):
            c.fill(wx, top, 2, 8, 3)                 # the glass
            c.vline(wx - 1, top, 8, 0)               # the reveal on the left
            c.hline(wx - 1, top + 8, 4, 2)           # the sill
    c.hline(0, 16, 16, 0)                            # the floor band between storeys
    c.hline(0, 30, 16, 0); c.hline(0, 31, 16, 0)     # the base
    if door:
        c.fill(6, 21, 4, 11, 0)                      # a doorway cut into the lower storey
        c.hline(5, 20, 6, 2)
    return c


def ground_floor(colour, door=False):
    """A building's ground floor, 32 pixels: an awning over shop windows,
    the glass lit, and the pavement's shadow at its foot.  The pattern
    repeats every cell, as the storeys above do."""
    c = mc(); c.cfill(0, 0, 4, 4, 1, colour)
    c.hline(0, 0, 16, 0)                             # the floor band above
    c.hline(0, 2, 16, 3); c.hline(0, 3, 16, 3)       # the awning, in the shop's colour
    c.hline(0, 4, 16, 0)                             # its shadow
    for wx in range(1, 16, 4):
        c.fill(wx, 7, 3, 18, 2)                      # the glass, lit
        c.vline(wx - 1, 7, 18, 0)                    # the mullion between shops
    c.hline(0, 25, 16, 0)                            # the stallriser
    c.hline(0, 30, 16, 0); c.hline(0, 31, 16, 0)     # the pavement's shadow at its foot
    if door:
        c.fill(6, 7, 4, 18, 0)                       # a doorway in the middle
        c.fill(7, 9, 2, 8, 3)                        # its glass
    return c


def bellamar_34():
    """The three-quarter district (tools/b64world.py): the ground as the day
    set draws it, and buildings that stand up from it -- two rows of roof
    seen from above and slightly in front, then an upper storey and a ground
    floor, 64 pixels of face.  Its own metatiles, not the day set's: only
    this district is drawn with it."""
    ts = Tileset("bellamar_34", (DGRAY, LGRAY, WHITE))

    c = mc(); c.cdots(0, 0, 4, 4, 3, 0, GREEN, 4, 4); ts.add("grass", c)
    c = mc(); c.cdots(0, 0, 4, 4, 1, 0, BLUE, 8, 8); ts.add("sidewalk", c, P_SIDEWALK)
    c = mc(); c.cdither(0, 0, 4, 4, 0, 1, BLUE); ts.add("sidewalk_shadow", c, P_SIDEWALK)
    c = mc(); c.cfill(0, 0, 4, 4, 0, WHITE)
    c.hline(0, 0, 16, 1); c.hline(0, 31, 16, 1); c.dashes(0, 15, 16, 4, 4, 2)
    ts.add("road_h", c, P_ROAD_HV)
    c = mc(); c.cfill(0, 0, 4, 4, 0, WHITE)
    c.vline(0, 0, 32, 1); c.vline(15, 0, 32, 1); c.vdashes(7, 0, 32, 8, 8, 2)
    ts.add("road_v", c, P_ROAD_VV)
    c = mc(); c.cfill(0, 0, 4, 4, 0, WHITE); ts.add("cross", c, P_ROAD_ALL)

    # roofs: the far edge lit, a parapet along the near one, and the flat
    # interior for the rows between
    for name, col in (("roof_cyan", CYAN), ("roof_yellow", YELLOW), ("roof_red", RED)):
        c = mc(); c.cfill(0, 0, 4, 4, 3, col)
        c.hline(0, 0, 16, 2)
        c.hline(0, 30, 16, 0); c.hline(0, 31, 16, 2)
        ts.add(name, c, P_SOLID, BUILDING)
    for name, col in (("roofi_cyan", CYAN), ("roofi_yellow", YELLOW), ("roofi_red", RED)):
        c = mc(); c.cfill(0, 0, 4, 4, 3, col)
        ts.add(name, c, P_SOLID, BUILDING)

    # the face: an upper storey of windows over a ground floor of shops
    ts.add("face_top", facade(BLUE), P_SOLID, BUILDING)
    ts.add("face_low", ground_floor(CYAN), P_SOLID, BUILDING)
    ts.add("face_door", ground_floor(CYAN, door=True), P_SOLID | P_DOOR, BUILDING)

    c = mc(); c.cdots(0, 0, 4, 4, 1, 0, BLUE, 8, 8)
    c.crect(1, 0, 2, 2, GREEN); c.crect(1, 2, 2, 2, GREEN)
    c.hline(5, 1, 6, 3); c.hline(4, 2, 8, 3); c.hline(6, 3, 4, 3); c.put(4, 4, 3); c.put(11, 4, 3)
    c.vline(7, 4, 24, 0); c.vline(8, 5, 23, 0); c.hline(6, 30, 4, 0)
    ts.add("palm_walk", c, P_SOLID, PALM)
    return ts


# ---------------------------------------------------------------------------
# Bellamar, flat roofs and shadows.  After the reference the user brought on
# 2026-09-19: pure top-down roofs, height told by the length of the shadow
# thrown south-east, built from a small set of characters.  Shared colours
# are black (asphalt, outlines, the dark side of every dither), mid grey
# (pavement, roof) and white (markings, lit edges), so the road, the
# pavement and a grey roof cost nothing against any colour's budget: only
# grass, shadow and a coloured roof spend one.
# ---------------------------------------------------------------------------
def flat_roof(colour=None, edge_n=False, edge_s=False, edge_w=False, edge_e=False, detail=None):
    """A roof metatile: gravel, a lit white edge where the building ends to
    the north or west, a dark one south or east, and room for a unit."""
    c = mc()
    if colour is None:
        c.cfill(0, 0, 4, 4, 1, WHITE)                # a grey roof: shared colours only
    else:
        c.cfill(0, 0, 4, 4, 3, colour)
    for y in range(1, 32, 6):                        # the gravel, sparse so it does not fizz
        for x in range((y // 6) % 3, 16, 5):
            c.put(x, y, 0)
    if edge_n:
        c.hline(0, 0, 16, 2); c.hline(0, 1, 16, 2)
    if edge_w:
        c.vline(0, 0, 32, 2); c.vline(1, 0, 32, 2)
    if edge_s:
        c.hline(0, 30, 16, 2); c.hline(0, 31, 16, 2)
    if edge_e:
        c.vline(14, 0, 32, 2); c.vline(15, 0, 32, 2)
    if detail == "ac":                               # an air handling unit
        c.fill(5, 12, 6, 8, 1)
        c.hline(5, 12, 6, 2); c.vline(5, 12, 8, 2)
        c.hline(5, 19, 6, 0); c.vline(10, 12, 8, 0)
        for y in range(14, 19, 2):
            c.hline(6, y, 4, 0)
    elif detail == "vent":
        c.fill(6, 14, 4, 4, 1); c.hline(6, 14, 4, 2); c.hline(6, 17, 4, 0)
    return c


def shadow_tile():
    """The shadow a building throws: one chequer of blue against black,
    the same over grass, pavement or road.  Two characters for the whole
    city, because the ground under it does not show through."""
    c = mc(); c.cfill(0, 0, 4, 4, 0, BLUE)
    for y in range(32):
        for x in range(16):
            if (x + y) & 1:
                c.put(x, y, 3)
    return c


# ---------------------------------------------------------------------------
# The city, drawn as a character set and composed into metatiles, the way a
# reference sheet does it (2026-09-19).  Two-colour cells are hires, eight
# pixels across, so a lane stripe or a tuft of grass is one pixel wide; the
# grey cells stay multicolour, because hires can only take colours 0-7 and
# every grey is above that.  A multicolour cell that uses no colour of its
# own is free against every bucket, which is what the pavement and the roof
# are.  Metatiles are cheap -- 256 of them, a table already allocated -- so
# the building edges get variants at character granularity.
# ---------------------------------------------------------------------------
def city_chars():
    """The character set: ground, road, roof and shadow."""
    c = {}
    # grass: green, with a tuft of shade; four of them, scattered, so the
    # field does not repeat on an eight-pixel lattice
    TUFTS = (((2, 1), (3, 1), (6, 6)), ((5, 2), (1, 4), (0, 7)),
             ((7, 3), (4, 6), (2, 5)), ((1, 0), (6, 1), (3, 7)))
    for n, tufts in enumerate(TUFTS):
        g = Char(False, GREEN).all(1)
        for x, y in tufts:
            g.put(x, y, 0)
        c[f"grass{n}" if n else "grass"] = g
    c["grass2"] = c["grass1"]

    w = Char(True, WHITE).all(2)                     # pavement: light grey slabs, mid grey seams
    w.hline(0, 0, 4, 1)
    c["walk"] = w
    c["walk_seam"] = Char(True, WHITE).all(2).hline(0, 0, 4, 1).vline(0, 0, 8, 1)
    c["walk_plain"] = Char(True, WHITE).all(2)

    c["road"] = Char(False, WHITE)                   # asphalt: nothing lit at all
    c["dash"] = Char(False, WHITE).fill(1, 3, 5, 1, 1)       # a lane stripe, one pixel thick
    c["kerb_n"] = Char(False, WHITE).hline(0, 0, 8, 1)
    c["kerb_s"] = Char(False, WHITE).hline(0, 7, 8, 1)
    c["kerb_w"] = Char(False, WHITE).vline(0, 0, 8, 1)
    c["kerb_e"] = Char(False, WHITE).vline(7, 0, 8, 1)
    c["stripe_v"] = Char(False, WHITE).fill(3, 1, 1, 5, 1)

    c["shadow"] = Char(False, BLUE).chequer(1)       # the shadow: a fine blue chequer
    c["shadow_w"] = Char(False, BLUE).fill(0, 0, 4, 8, 0)
    for y in range(8):                               # its western edge, half a cell
        for x in range(4, 8):
            if (x + y) & 1:
                c["shadow_w"].put(x, y, 1)
    c["shadow_n"] = Char(False, BLUE)
    for y in range(4, 8):
        for x in range(8):
            if (x + y) & 1:
                c["shadow_n"].put(x, y, 1)

    roof = Char(True, WHITE).all(1)                  # roof: mid grey gravel, a little grit
    roof.put(1, 2, 0); roof.put(3, 6, 0)
    c["roof"] = roof
    # the parapet: white, as the cell's own colour, so the roof stays grey
    edge = Char(True, WHITE).all(1)
    edge.put(1, 3, 0); edge.put(3, 6, 0)
    c["roof_n"] = edge.copy().hline(0, 0, 4, 3)
    c["roof_s"] = edge.copy().hline(0, 7, 4, 3)
    c["roof_w"] = edge.copy().vline(0, 0, 8, 3)
    c["roof_e"] = edge.copy().vline(3, 0, 8, 3)
    c["roof_nw"] = c["roof_n"].copy().vline(0, 0, 8, 3)
    c["roof_ne"] = c["roof_n"].copy().vline(3, 0, 8, 3)
    c["roof_sw"] = c["roof_s"].copy().vline(0, 0, 8, 3)
    c["roof_se"] = c["roof_s"].copy().vline(3, 0, 8, 3)
    # the roof and its edge set, ten characters: a light grey field with
    # sparse gravel, a black keyline where the building ends, and a white
    # rim inside it.  A multicolour pixel is two screen pixels, so the rim
    # is two where a hires reference sheet's is one.
    def roof_edge(north=False, south=False, west=False, east=False):
        e = Char(True, WHITE).all(2)                 # light grey roof, its gravel added later
        # the parapet seen edge-on: the keyline outside it, the cap lit
        # white, the shadow it throws on the roof, then the gravel
        if north:
            e.hline(0, 0, 4, 0); e.hline(0, 1, 4, 3); e.hline(0, 2, 4, 0)
        if south:
            e.hline(0, 7, 4, 0); e.hline(0, 6, 4, 3); e.hline(0, 5, 4, 0)
        if west:
            e.vline(0, 0, 8, 0); e.vline(1, 0, 8, 3)
        if east:
            e.vline(3, 0, 8, 0); e.vline(2, 0, 8, 3)
        return e

    # four fills, their grit scattered differently, so a roof of any size
    # never shows the lattice a single repeating character makes
    GRIT = (((2, 1),), ((0, 6),), ((3, 4),), ((1, 3),))    # one each, a different quarter
    for n, grit in enumerate(GRIT):
        f = roof_edge()
        for x, y in grit:
            f.put(x, y, 1)
        c[f"fill{n}" if n else "fill"] = f
    c["fill2"] = c["fill2"]                          # (named in the character sheet)
    for tag, kw in (("corner_nw", dict(north=True, west=True)), ("edge_n", dict(north=True)),
                    ("corner_ne", dict(north=True, east=True)), ("edge_w", dict(west=True)),
                    ("fill", dict()), ("edge_e", dict(east=True)),
                    ("corner_sw", dict(south=True, west=True)), ("edge_s", dict(south=True)),
                    ("corner_se", dict(south=True, east=True))):
        c[tag] = roof_edge(**kw)
    c["roof_corner"] = c["corner_nw"]

    ac = Char(True, WHITE).all(2)                    # an air handling unit, lit north-west
    ac.rect(0, 1, 4, 6, 0); ac.fill(1, 2, 2, 4, 1); ac.hline(1, 2, 2, 3)
    c["ac"] = ac
    vent = Char(True, WHITE).all(1)
    vent.fill(1, 3, 2, 3, 0); vent.hline(1, 3, 2, 2)
    c["vent"] = vent

    # a tree: a solid crown outlined in black, standing on the speckled
    # grass, with its trunk showing at the foot
    for tag, (cx, cy) in (("tree_nw", (0, 0)), ("tree_ne", (1, 0)),
                          ("tree_sw", (0, 1)), ("tree_se", (1, 1))):
        t = Char(True, GREEN).all(3)
        for y in range(8):
            for x in range(4):
                gx, gy = cx * 4 + x, cy * 8 + y            # the crown, 8 by 16 over two cells
                dx, dy = gx - 3.5, (gy - 7.5) * 0.5
                d = dx * dx + dy * dy
                if d <= 9:
                    t.put(x, y, 3)                         # the crown itself
                elif d <= 15:
                    t.put(x, y, 0)                         # its outline, and the shade under it
                elif (gx * 3 + gy * 5) % 11 == 0:
                    t.put(x, y, 0)                         # the grass around it
        if tag in ("tree_sw", "tree_se"):
            t.vline(3 if tag == "tree_sw" else 0, 4, 4, 0)  # the trunk
        c[tag] = t
    return c


def tile(chars, rows):
    """A metatile from a 4x4 grid of character names."""
    return [chars[n] for row in rows for n in row]


def bellamar_city():
    """The city: flat roofs, height told by the shadow's length, composed
    from city_chars() at character granularity."""
    ts = Tileset("bellamar_city", (BLACK, MGRAY, LGRAY))
    c = city_chars()
    G, G2, W, R, S = "grass", "grass2", "walk", "road", "shadow"

    def rows4(n):
        return [[n] * 4 for _ in range(4)]

    ts.add_chars("grass", tile(c, [[G, G2, G, G2], [G2, G, G2, G], [G, G2, G, G2], [G2, G, G2, G]]))
    ts.add_chars("sidewalk", tile(c, [["walk_seam", W, W, W], [W] * 4,
                                      ["walk_seam", W, W, W], [W] * 4]), P_SIDEWALK)
    ts.add_chars("road_h", tile(c, [["kerb_n"] * 4, [R, R, R, R],
                                    ["dash", "dash", "dash", "dash"], ["kerb_s"] * 4]), P_ROAD_HV)
    ts.add_chars("road_v", tile(c, [["kerb_w", "stripe_v", R, "kerb_e"]] * 4), P_ROAD_VV)
    ts.add_chars("cross", tile(c, rows4(R)), P_ROAD_ALL)
    ts.add_chars("grass_tree", tile(c, [[G, "tree_nw", "tree_ne", G2],
                                        [G2, "tree_sw", "tree_se", G],
                                        [G, G2, G, G2], [G2, G, G2, G]]))
    ts.add_chars("shadow", tile(c, rows4(S)))
    ts.add_chars("shadow_w", tile(c, [["shadow_w", S, S, S]] * 4))
    ts.add_chars("shadow_n", tile(c, [["shadow_n"] * 4] + [[S] * 4] * 3))

    # the roof, edged where the building ends, at character granularity
    def roof_tile(name, north=False, south=False, west=False, east=False, unit=None):
        grid = []
        for j in range(4):
            row = []
            for i in range(4):
                n = "roof"
                if north and j == 0:
                    n = "roof_n"
                if south and j == 3:
                    n = "roof_s"
                if west and i == 0:
                    n = "roof_nw" if (north and j == 0) else ("roof_sw" if (south and j == 3) else "roof_w")
                elif east and i == 3:
                    n = "roof_ne" if (north and j == 0) else ("roof_se" if (south and j == 3) else "roof_e")
                row.append(n)
            grid.append(row)
        if unit:
            grid[1][1] = unit
        ts.add_chars(name, tile(c, grid), P_SOLID, BUILDING)

    for name, kw in (("roof_nw", dict(north=True, west=True)), ("roof_n", dict(north=True)),
                     ("roof_ne", dict(north=True, east=True)), ("roof_w", dict(west=True)),
                     ("roof_mid", dict()), ("roof_e", dict(east=True)),
                     ("roof_sw", dict(south=True, west=True)), ("roof_s", dict(south=True)),
                     ("roof_se", dict(south=True, east=True))):
        roof_tile(name, **kw)
    roof_tile("roof_ac", unit="ac")
    roof_tile("roof_vent", unit="vent")
    return ts


def city_tileset(name, style):
    """The city at one of the five ways of telling a building's height
    (docs/VIEWS.md, after the reference sheets of 2026-09-19).  Every style
    shares the ground and the roof; they differ in what marks the edge:

        flat     nothing but the shadow's length
        reveal   a wall face below the south edge and beside the east one
        tiers    setbacks: a smaller roof stacked on the one below
        bands    floor lines round the south and east edges, one a storey
        cut      a cutaway slice down one side, its floors showing
    """
    ts = Tileset(name, (BLACK, MGRAY, WHITE))

    def grass():
        c = mc(); c.cfill(0, 0, 4, 4, 3, GREEN)
        for y in range(2, 32, 5):
            for x in range((y // 5) % 4, 16, 4):
                c.put(x, y, 0)
        return c

    def walk():
        c = mc(); c.cfill(0, 0, 4, 4, 1)             # mid grey, shared: a free character
        c.hline(0, 0, 16, 0)
        c.vline(0, 0, 32, 0)
        for y in range(4, 32, 8):
            c.put((y // 8) * 5 % 16, y, 2)
        return c

    def road_h():
        c = mc(); c.cfill(0, 0, 4, 4, 0)
        c.hline(0, 0, 16, 1); c.hline(0, 31, 16, 1)
        c.dashes(0, 15, 16, 3, 5, 2)
        return c

    ts.add("grass", grass())
    ts.add("sidewalk", walk(), P_SIDEWALK)
    ts.add("road_h", road_h(), P_ROAD_HV)
    c = mc(); c.cfill(0, 0, 4, 4, 0)
    c.vline(0, 0, 32, 1); c.vline(15, 0, 32, 1); c.vdashes(7, 0, 32, 6, 10, 2)
    ts.add("road_v", c, P_ROAD_VV)
    c = mc(); c.cfill(0, 0, 4, 4, 0); ts.add("cross", c, P_ROAD_ALL)

    for tile, kw in (("roof_nw", dict(edge_n=True, edge_w=True)),
                     ("roof_n", dict(edge_n=True)),
                     ("roof_ne", dict(edge_n=True, edge_e=True)),
                     ("roof_w", dict(edge_w=True)),
                     ("roof_mid", dict()),
                     ("roof_e", dict(edge_e=True)),
                     ("roof_sw", dict(edge_s=True, edge_w=True)),
                     ("roof_s", dict(edge_s=True)),
                     ("roof_se", dict(edge_s=True, edge_e=True))):
        ts.add(tile, flat_roof(**kw), P_SOLID, BUILDING)
    ts.add("roof_ac", flat_roof(detail="ac"), P_SOLID, BUILDING)
    ts.add("roof_vent", flat_roof(detail="vent"), P_SOLID, BUILDING)
    ts.add("shadow", shadow_tile())

    if style == "reveal":
        # the roof is offset, so the south face and the east face show; the
        # deeper the face, the taller the building
        for tag, depth in (("low", 10), ("mid", 18), ("high", 32)):
            c = grass(); c.fill(0, 0, 16, depth, 1)
            c.crect(0, 0, 4, (depth + 7) // 8, PURPLE)
            c.hline(0, 0, 16, 2)
            for wy in range(3, depth - 3, 7):        # windows down the face
                for wx in range(1, 15, 4):
                    c.fill(wx, wy, 2, 3, 0)
            ts.add(f"front_{tag}", c, P_SOLID, BUILDING)
            c = grass(); c.fill(0, 0, min(8, depth // 2), 32, 1)
            c.crect(0, 0, max(1, min(8, depth // 2) // 4), 4, PURPLE)
            c.vline(0, 0, 32, 2)
            for wy in range(2, 30, 7):               # the shaded side face
                c.fill(1, wy, 2, 3, 0)
            ts.add(f"side_{tag}", c, P_SOLID, BUILDING)
            c = grass(); c.fill(0, 0, min(8, depth // 2), depth, 1)
            c.crect(0, 0, max(1, min(8, depth // 2) // 4), (depth + 7) // 8, PURPLE)
            ts.add(f"corner_{tag}", c, P_SOLID, BUILDING)
    elif style == "tiers":
        # a setback: the tier above starts here, so its edge steps up
        for tile, kw in (("step_nw", dict(edge_n=True, edge_w=True)),
                         ("step_n", dict(edge_n=True)),
                         ("step_w", dict(edge_w=True))):
            c = flat_roof(**kw)
            c.fill(0, 0, 16, 3, 1) if kw.get("edge_n") else None
            c.fill(0, 0, 3, 32, 1) if kw.get("edge_w") else None
            if kw.get("edge_n"):
                c.hline(0, 3, 16, 0); c.hline(0, 0, 16, 2)
            if kw.get("edge_w"):
                c.vline(3, 0, 32, 0); c.vline(0, 0, 32, 2)
            ts.add(tile, c, P_SOLID, BUILDING)
    elif style == "bands":
        # floor lines: one band a storey, round the south and east edges
        for tag, lines in (("low", 2), ("mid", 4), ("high", 7)):
            c = grass(); c.fill(0, 0, 16, 4 * lines, 1)
            c.crect(0, 0, 4, (4 * lines + 7) // 8, BLUE)
            for i in range(lines):
                c.hline(0, 4 * i, 16, 2); c.hline(0, 4 * i + 1, 16, 0)
            ts.add(f"bands_{tag}", c, P_SOLID, BUILDING)
    elif style == "cut":
        # a cutaway slice: the wall opened, its floors and windows showing
        for tag, depth in (("low", 10), ("mid", 20), ("high", 32)):
            c = grass(); c.fill(0, 0, 16, depth, 3)
            c.crect(0, 0, 4, (depth + 7) // 8, RED)
            c.hline(0, 0, 16, 2)
            for fy in range(4, depth - 2, 6):        # a floor line, then its windows
                c.hline(0, fy, 16, 0)
                for wx in range(1, 15, 4):
                    c.fill(wx, fy + 2, 2, 3, 1)
            ts.add(f"cut_{tag}", c, P_SOLID, BUILDING)
    return ts


def bellamar_flat():
    return city_tileset("bellamar_flat", "flat")


def bellamar_reveal():
    return city_tileset("bellamar_reveal", "reveal")


def bellamar_tiers():
    return city_tileset("bellamar_tiers", "tiers")


def bellamar_bands():
    return city_tileset("bellamar_bands", "bands")


def bellamar_cut():
    return city_tileset("bellamar_cut", "cut")


def band_chars():
    """The characters of the band city, drawn to the reference image
    (images/city-band.png, chosen 2026-09-19): the far side's facades
    standing along the top of the screen, the road across the middle, the
    near side's roofs below.

    The colour rule decides the art.  In multicolour text mode a cell's own
    colour is the low three bits of its colour nibble -- bit 3 only marks
    the cell multicolour -- so the eight colours a cell may add are the
    first eight, of which only black and white are grey.  The greys have to
    come from the three shared registers: black, dark grey and light grey,
    with white as the one colour a cell adds.  Every highlight therefore
    costs against a single bucket of twelve characters (tools/b64band.py
    measured 179 such cells in the reference itself), so a parapet's shaded
    side, a roof unit and a tank are drawn in light grey instead of white.
    """
    c = {}
    B, D, L, W = 0, 1, 2, 3        # black, dark grey, light grey shared; white, the cell's own

    # -- the facade band: wall, cornice, windows, shopfront ------------------
    c["wall"] = Char(True, WHITE).all(L)
    c["slab"] = Char(True, WHITE).all(D)                          # the roof behind the parapet
    c["slab_s"] = Char(True, WHITE).all(D).hline(0, 7, 4, L)      # its front edge, lit
    cor = Char(True, WHITE).all(L)                                # the cornice over the windows
    cor.hline(0, 0, 4, W); cor.hline(0, 1, 4, W); cor.hline(0, 2, 4, B)
    c["cornice"] = cor
    win_t = Char(True, WHITE).all(L)                              # a window, upper half
    win_t.hline(1, 1, 2, W); win_t.fill(1, 2, 2, 6, B)
    c["win_t"] = win_t
    win_b = Char(True, WHITE).all(L)                              # and lower, with its sill
    win_b.fill(1, 0, 2, 4, B); win_b.hline(0, 4, 4, W); win_b.hline(0, 5, 4, D)
    c["win_b"] = win_b
    c["pier"] = Char(True, WHITE).all(L).vline(0, 0, 8, D)        # the pilaster between windows
    awn = Char(True, WHITE).all(L)                                # a striped awning
    awn.hline(0, 0, 4, B)                                         # the lintel it hangs from
    awn.fill(0, 1, 2, 6, W); awn.fill(2, 1, 2, 6, L)              # four-pixel stripes
    awn.hline(0, 7, 4, B)                                         # its valance, in shadow
    c["awning"] = awn
    fascia = Char(True, WHITE).all(B)                             # the sign board over the glass
    fascia.hline(0, 0, 4, L); fascia.hline(0, 1, 4, D)
    c["fascia"] = fascia
    glass = Char(True, WHITE).all(D)                              # the storefront, recessed
    glass.hline(0, 0, 4, L)                                       # the fascia over the glass
    glass.fill(0, 2, 4, 4, B)                                     # the window itself
    glass.hline(0, 6, 4, D); glass.hline(0, 7, 4, L)              # its stall riser and the kerbside
    c["glass"] = glass
    stall = Char(True, WHITE).all(B)                              # a shop's riser at the pavement
    stall.hline(0, 5, 4, D); stall.hline(0, 6, 4, L); stall.hline(0, 7, 4, L)
    c["stall"] = stall
    pier_s = Char(True, WHITE).all(L)                             # the pier between two shops
    pier_s.hline(0, 7, 4, L); pier_s.vline(3, 1, 6, D)
    c["pier_s"] = pier_s
    door_t = Char(True, WHITE).all(D)                             # a doorway, its head lit
    door_t.hline(0, 0, 4, L)
    door_t.fill(1, 2, 2, 6, B); door_t.hline(1, 2, 2, L)
    c["door_t"] = door_t
    c["gap"] = Char(True, WHITE).all(B)                           # the alley between blocks
    c["gap_w"] = Char(True, WHITE).all(B).vline(3, 0, 8, D)
    c["gap_e"] = Char(True, WHITE).all(B).vline(0, 0, 8, D)

    # -- the pavement: light grey, jointed, kerbed on the road side ---------
    c["walk"] = Char(True, WHITE).all(L)
    c["walk_j"] = Char(True, WHITE).all(L).vline(0, 0, 8, D)      # a joint between slabs
    c["walk_h"] = Char(True, WHITE).all(L).hline(0, 0, 4, D)
    kerb_s = Char(True, WHITE).all(L)                             # pavement above, road below
    kerb_s.hline(0, 6, 4, W); kerb_s.hline(0, 7, 4, B)
    c["kerb_s"] = kerb_s
    kerb_n = Char(True, WHITE).all(L)                             # road above, pavement below
    kerb_n.hline(0, 0, 4, B); kerb_n.hline(0, 1, 4, W)
    c["kerb_n"] = kerb_n

    # -- the road: asphalt, the centre line, the crossing -------------------
    c["road"] = Char(True, WHITE).all(D)
    c["road_n"] = Char(True, WHITE).all(D).hline(0, 0, 4, B)      # under the kerb's shadow
    dash = Char(True, WHITE).all(D)                               # the broken centre line
    dash.hline(0, 3, 2, W); dash.hline(0, 4, 2, W)
    c["dash"] = dash
    c["dash_off"] = Char(True, WHITE).all(D)                      # its gap, so the line breaks
    zeb = Char(True, WHITE).all(D)                                # a crossing, bars across
    zeb.fill(0, 0, 4, 2, W); zeb.fill(0, 4, 4, 2, W)
    c["zebra"] = zeb

    # -- the roofs: dark grey, their parapets lit, their units light --------
    c["roof"] = Char(True, WHITE).all(D)
    grit = Char(True, WHITE).all(D)
    grit.put(1, 2, B); grit.put(3, 5, B)
    c["roof_grit"] = grit
    par_n = Char(True, WHITE).all(D)                              # the parapet along the top
    par_n.hline(0, 0, 4, L); par_n.hline(0, 1, 4, W); par_n.hline(0, 2, 4, B)
    c["par_n"] = par_n
    par_s = Char(True, WHITE).all(D)
    par_s.hline(0, 5, 4, B); par_s.hline(0, 6, 4, W); par_s.hline(0, 7, 4, L)
    c["par_s"] = par_s
    c["par_w"] = Char(True, WHITE).all(D).vline(0, 0, 8, L).vline(1, 0, 8, B)
    c["par_e"] = Char(True, WHITE).all(D).vline(3, 0, 8, B).vline(2, 0, 8, L)
    # the plant on the roofs, two cells each so it reads at this scale, with
    # its shadow thrown south-east as everything else in the set throws it
    ac_w = Char(True, WHITE).all(D)                               # an air handler, lit north
    ac_w.fill(1, 1, 3, 5, L); ac_w.hline(1, 1, 3, L); ac_w.hline(1, 3, 3, D)
    c["ac_w"] = ac_w
    ac_e = Char(True, WHITE).all(D)
    ac_e.fill(0, 1, 2, 5, L); ac_e.hline(0, 1, 2, L); ac_e.hline(0, 3, 2, D)
    ac_e.vline(2, 2, 5, B); ac_e.hline(0, 6, 3, B)
    c["ac_e"] = ac_e
    tank_w = Char(True, WHITE).all(D)                             # a water tank on its legs
    tank_w.fill(2, 0, 2, 6, L); tank_w.hline(2, 0, 2, L); tank_w.hline(2, 2, 2, D)
    tank_w.put(2, 6, B); tank_w.put(3, 6, L)
    c["tank_w"] = tank_w
    tank_e = Char(True, WHITE).all(D)
    tank_e.fill(0, 0, 2, 6, L); tank_e.hline(0, 0, 2, L); tank_e.hline(0, 2, 2, D)
    tank_e.vline(2, 1, 6, B); tank_e.put(0, 6, L); tank_e.hline(0, 7, 3, B)
    c["tank_e"] = tank_e
    stair_w = Char(True, WHITE).all(D)                            # the stairwell bulkhead
    stair_w.fill(1, 2, 3, 5, L); stair_w.hline(1, 2, 3, L)
    c["stair_w"] = stair_w
    stair_e = Char(True, WHITE).all(D)
    stair_e.fill(0, 2, 2, 5, L); stair_e.hline(0, 2, 2, L)
    stair_e.vline(2, 3, 5, B); stair_e.hline(0, 7, 3, B)
    c["stair_e"] = stair_e
    c["shadow"] = Char(True, WHITE).all(B)                        # the alley between roofs
    return c


def bellamar_band():
    """The band city: the street as the reference draws it, in metatiles.

    A period runs ten metatile rows down: the far roofs, three rows of
    facade, the far pavement, two rows of road, the near pavement, and the
    near roofs.  The world repeats it (tools/b64world.py, band_street).
    """
    ts = Tileset("bellamar_band", (BLACK, DGRAY, LGRAY))
    c = band_chars()

    def rows(*names):
        """A metatile from four rows of four character names."""
        return [c[n] for row in names for n in row]

    W4 = ["wall"] * 4
    ts.add_chars("fac_roof", rows(["slab"] * 4, ["slab"] * 4, ["slab_s"] * 4, ["cornice"] * 4),
                 P_SOLID, BUILDING)
    ts.add_chars("fac_win", rows(["pier", "win_t", "win_t", "wall"],
                                 ["pier", "win_b", "win_b", "wall"],
                                 ["pier", "win_t", "win_t", "wall"],
                                 ["pier", "win_b", "win_b", "wall"]), P_SOLID, BUILDING)
    ts.add_chars("fac_wall", rows(W4, W4, W4, W4), P_SOLID, BUILDING)
    ts.add_chars("fac_shop", rows(["pier", "win_t", "win_t", "wall"],
                                  ["pier", "win_b", "win_b", "wall"],
                                  ["awning", "awning", "fascia", "awning"],
                                  ["glass", "glass", "door_t", "pier_s"]), P_SOLID, BUILDING)
    ts.add_chars("fac_street", rows(["awning", "awning", "fascia", "awning"],
                                    ["glass", "glass", "door_t", "pier_s"],
                                    ["glass", "glass", "glass", "pier_s"],
                                    ["stall"] * 4), P_SOLID, BUILDING)
    ts.add_chars("fac_gap", rows(["gap_w", "gap", "gap", "gap_e"],
                                 ["gap_w", "gap", "gap", "gap_e"],
                                 ["gap_w", "gap", "gap", "gap_e"],
                                 ["gap_w", "gap", "gap", "gap_e"]), P_SOLID, BUILDING)

    ts.add_chars("walk_s", rows(["walk_h", "walk", "walk_j", "walk"],
                                ["walk"] * 4,
                                ["walk_h", "walk", "walk_j", "walk"],
                                ["kerb_s"] * 4), P_SIDEWALK)
    ts.add_chars("walk_n", rows(["kerb_n"] * 4,
                                ["walk_h", "walk", "walk_j", "walk"],
                                ["walk"] * 4,
                                ["walk_h", "walk", "walk_j", "walk"]), P_SIDEWALK)
    ts.add_chars("road_n", rows(["road_n"] * 4, ["road"] * 4, ["road"] * 4,
                                ["dash", "dash_off", "dash", "dash_off"]), P_ROAD_HV)
    ts.add_chars("road_s", rows(["road"] * 4, ["road"] * 4, ["road"] * 4, ["road"] * 4),
                 P_ROAD_HV)
    ts.add_chars("cross_n", rows(["road_n"] * 4, ["zebra"] * 4, ["zebra"] * 4, ["zebra"] * 4),
                 P_ROAD_ALL)
    ts.add_chars("cross_s", rows(["zebra"] * 4, ["zebra"] * 4, ["zebra"] * 4, ["zebra"] * 4),
                 P_ROAD_ALL)

    R4 = ["roof"] * 4
    ts.add_chars("roof_n", rows(["par_n"] * 4, ["par_w"] + R4[1:], R4, ["roof_grit"] + R4[1:]),
                 P_SOLID, BUILDING)
    ts.add_chars("roof_mid", rows(R4, ["roof_grit"] + R4[1:], R4, R4), P_SOLID, BUILDING)
    ts.add_chars("roof_s", rows(R4, R4, R4, ["par_s"] * 4), P_SOLID, BUILDING)
    ts.add_chars("roof_ac", rows(R4, ["roof", "ac_w", "ac_e", "roof"], R4, R4), P_SOLID, BUILDING)
    ts.add_chars("roof_tank", rows(R4, ["roof", "tank_w", "tank_e", "roof"], R4, R4),
                 P_SOLID, BUILDING)
    ts.add_chars("roof_stair", rows(R4, ["roof", "stair_w", "stair_e", "roof"], R4, R4),
                 P_SOLID, BUILDING)
    ts.add_chars("roof_w", rows(["par_w"] + R4[1:], ["par_w"] + R4[1:],
                                ["par_w"] + R4[1:], ["par_w"] + R4[1:]), P_SOLID, BUILDING)
    ts.add_chars("roof_e", rows(R4[:3] + ["par_e"], R4[:3] + ["par_e"],
                                R4[:3] + ["par_e"], R4[:3] + ["par_e"]), P_SOLID, BUILDING)
    ts.add_chars("walk_roof", rows(["kerb_n"] * 4,
                                   ["walk_h", "walk", "walk_j", "walk"],
                                   ["par_n"] * 4,
                                   ["roof"] * 4), P_SIDEWALK)
    ts.add_chars("alley", rows(["shadow"] * 4, ["shadow"] * 4, ["shadow"] * 4, ["shadow"] * 4))
    return ts


TILESETS = {"bellamar_day": bellamar_day, "bellamar_34": bellamar_34, "bellamar_city": bellamar_city,
            "bellamar_band": bellamar_band,
            "bellamar_flat": bellamar_flat, "bellamar_reveal": bellamar_reveal,
            "bellamar_tiers": bellamar_tiers, "bellamar_bands": bellamar_bands,
            "bellamar_cut": bellamar_cut}


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
