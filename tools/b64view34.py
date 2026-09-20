#!/usr/bin/env python3
"""Three-quarter building studies, rendered as the VIC-II would show them.

A design exploration, asked for 2026-09-19: what different kinds of building
look like at three quarters, drawn under the engine's own rules -- a 4x4-cell
multicolour metatile, three shared colours (dark grey, light grey, white) and
one colour a cell, taken from the same palette the tilesets use.  Nothing
here is a tileset yet; each study is a stack of metatiles: roof, upper
storeys, ground floor.

The renderer is the same arithmetic the chip does: a multicolour pixel is two
screen pixels wide, bit pairs 00/01/10 take the shared colours and 11 the
cell's own, so what this writes is what the machine draws.

With --scene it renders a street instead: a crossing drawn the way the
engine would draw it, to judge how close the look can get to a top-down
crime game's city (asked 2026-09-19, against a GTA 1 screenshot).  The
perspective of that game splays each building's sides by where it sits on
screen, which a tile grid cannot do; everything else here is art.

usage: b64view34.py <out.png> [--zoom 3] [--scene]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from b64art import (  # noqa: E402
    BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW,
    ORANGE, BROWN, PINK, DGRAY, MGRAY, LGREEN, LBLUE, LGRAY, Canvas, FONT,
    car_frames_mc, ped_frames_mc,
)
from b64palette import RGB  # noqa: E402
from b64png import write_png  # noqa: E402

BG = (DGRAY, LGRAY, WHITE)          # the shared colours, as the city tilesets use them


def mc():
    return Canvas(True, 4, 4)


# ---------------------------------------------------------------------------
# ground
# ---------------------------------------------------------------------------
def pavement():
    c = mc(); c.cdots(0, 0, 4, 4, 1, 0, BLUE, 8, 8)
    return c


def pavement_shadow():
    c = mc(); c.cdither(0, 0, 4, 4, 0, 1, BLUE)
    return c


def road():
    c = mc(); c.cfill(0, 0, 4, 4, 0, WHITE)
    c.hline(0, 0, 16, 1); c.dashes(0, 15, 16, 4, 4, 2)
    return c


# ---------------------------------------------------------------------------
# the street, as a top-down crime game paints it: lanes with dashes, a
# centre line, crossings, arrows and words on the asphalt
# ---------------------------------------------------------------------------
def road_lanes(vertical=False, centre=YELLOW):
    """Four lanes: a painted centre pair, dashed lane divisions, kerbs."""
    c = mc(); c.cfill(0, 0, 4, 4, 0, centre)
    if vertical:
        c.vline(0, 0, 32, 1); c.vline(15, 0, 32, 1)          # the kerbs
        c.vline(7, 0, 32, 3); c.vline(8, 0, 32, 3)           # the centre pair
        c.vdashes(3, 0, 32, 6, 6, 2); c.vdashes(12, 0, 32, 6, 6, 2)
    else:
        c.hline(0, 0, 16, 1); c.hline(0, 31, 16, 1)
        c.hline(0, 15, 16, 3); c.hline(0, 16, 16, 3)
        c.dashes(0, 7, 16, 3, 3, 2); c.dashes(0, 24, 16, 3, 3, 2)
    return c


def road_crossing(vertical=False):
    """A pedestrian crossing: white bars across the asphalt."""
    c = mc(); c.cfill(0, 0, 4, 4, 0, WHITE)
    if vertical:
        for y in range(1, 30, 4):
            c.hline(1, y, 14, 2); c.hline(1, y + 1, 14, 2)
    else:
        for x in range(1, 16, 3):
            c.vline(x, 1, 30, 2)
    return c


def road_arrow(colour=WHITE):
    """A lane arrow painted on the asphalt, pointing up the screen."""
    c = mc(); c.cfill(0, 0, 4, 4, 0, colour)
    c.hline(0, 0, 16, 1)
    for i in range(5):                                        # the head
        c.hline(7 - i, 10 + i, 2 + 2 * i, 2)
    c.fill(6, 15, 4, 12, 2)                                   # the shaft
    return c


def road_text(colour=WHITE):
    """A word painted on the asphalt, as SLOW is in the street below."""
    c = mc(); c.cfill(0, 0, 4, 4, 0, colour)
    c.hline(0, 0, 16, 1)
    for x, rows in ((1, (0, 1, 2)), (5, (0, 2)), (9, (0, 1, 2)), (13, (0, 1))):
        for r in rows:
            c.fill(x, 8 + 6 * r, 2, 4, 2)
    return c


def kerb_corner():
    """A pavement corner with a crossing's dropped kerb."""
    c = mc(); c.cdots(0, 0, 4, 4, 1, 0, BLUE, 8, 8)
    c.hline(0, 30, 16, 2); c.hline(0, 31, 16, 0)
    c.vline(0, 0, 32, 2)
    return c


# ---------------------------------------------------------------------------
# roofs: seen from above and a little in front, so the far edge catches the
# light and the near edge carries a parapet with its shadow under it
# ---------------------------------------------------------------------------
def roof(colour, near=True, far=True, unit=False):
    c = mc(); c.cfill(0, 0, 4, 4, 3, colour)
    if far:
        c.hline(0, 0, 16, 2)
    if unit:
        c.rect(4, 6, 8, 8, 0); c.hline(4, 14, 8, 0)
    if near:
        c.hline(0, 29, 16, 0); c.hline(0, 30, 16, 2); c.hline(0, 31, 16, 2)
    return c


def roof_pitched(colour):
    """A house's roof at three quarters: the ridge across the top, the near
    slope facing the camera in tiles, the eaves overhanging the wall."""
    c = mc(); c.cfill(0, 0, 4, 4, 3, colour)
    c.hline(2, 1, 12, 2); c.hline(2, 2, 12, 2)  # the ridge, lit, set back
    for y in range(3, 27):                      # the near slope, courses of tile
        if y % 5 == 0:
            c.hline(0, y, 16, 0)
    c.hline(0, 27, 16, 2); c.hline(0, 28, 16, 2)  # the eaves, overhanging
    c.hline(0, 29, 16, 0)                       # their shadow on the wall
    c.fill(0, 30, 16, 2, 1)                     # the wall's top, in light grey
    c.crect(0, 3, 4, 1, colour)
    return c


# ---------------------------------------------------------------------------
# faces.  Each is one metatile, 32 pixels of building.  The window pattern
# repeats every cell (four multicolour pixels), so a face of any width costs
# the same handful of characters.
# ---------------------------------------------------------------------------
def face_shops(colour=BLUE):
    """A shop row's upper storey: a cornice, tall windows, sills."""
    c = mc(); c.cfill(0, 0, 4, 4, 1, colour)
    c.hline(0, 0, 16, 2); c.hline(0, 1, 16, 2)
    c.hline(0, 2, 16, 0)
    for top in (5, 19):
        for wx in range(1, 16, 4):
            c.fill(wx, top, 2, 8, 3)
            c.vline(wx - 1, top, 8, 0)
            c.hline(wx - 1, top + 8, 4, 2)
    c.hline(0, 16, 16, 0)
    c.hline(0, 30, 16, 0); c.hline(0, 31, 16, 0)
    return c


def ground_shops(colour=CYAN, door=False):
    """Shopfronts: an awning over lit glass, a stallriser, a doorway."""
    c = mc(); c.cfill(0, 0, 4, 4, 1, colour)
    c.hline(0, 0, 16, 0)
    c.hline(0, 2, 16, 3); c.hline(0, 3, 16, 3)
    c.hline(0, 4, 16, 0)
    for wx in range(1, 16, 4):
        c.fill(wx, 7, 3, 18, 2)
        c.vline(wx - 1, 7, 18, 0)
    c.hline(0, 25, 16, 0)
    c.hline(0, 30, 16, 0); c.hline(0, 31, 16, 0)
    if door:
        c.fill(6, 7, 4, 18, 0)
        c.fill(7, 9, 2, 8, 3)
    return c


def face_office(colour=LBLUE):
    """An office tower: a glass grid, every pane the same, dark spandrels."""
    c = mc(); c.cfill(0, 0, 4, 4, 0, colour)
    for top in range(1, 32, 8):
        for wx in range(0, 16, 4):
            c.fill(wx, top, 3, 6, 3)             # the pane
            c.vline(wx + 3, top, 6, 1)           # the mullion, lit
        c.hline(0, top + 6, 16, 1)               # the spandrel
    return c


def ground_office(colour=LBLUE):
    """Its ground floor: a glazed lobby between piers, the entrance in shade."""
    c = mc(); c.cfill(0, 0, 4, 4, 0, colour)
    c.hline(0, 0, 16, 1)
    c.fill(1, 4, 14, 20, 3)
    for px in (0, 5, 10, 15):
        c.vline(px, 2, 26, 1)
    c.fill(6, 10, 4, 18, 0)                      # the doors, recessed
    c.hline(0, 28, 16, 1)
    c.hline(0, 30, 16, 0); c.hline(0, 31, 16, 0)
    return c


def face_flats(colour=BROWN):
    """An apartment block: windows in pairs with balconies between them."""
    c = mc(); c.cfill(0, 0, 4, 4, 1, colour)
    c.hline(0, 0, 16, 2)
    for top in (3, 19):
        for wx in range(1, 16, 4):
            c.fill(wx, top, 2, 7, 3)             # the window
        c.hline(0, top + 8, 16, 0)               # the balcony's floor
        for bx in range(0, 16, 2):               # its railing
            c.vline(bx, top + 9, 3, 2)
        c.hline(0, top + 12, 16, 2)
    c.hline(0, 30, 16, 0); c.hline(0, 31, 16, 0)
    return c


def face_warehouse(colour=MGRAY):
    """A warehouse: corrugated sheet, a band of high windows, a roller door."""
    c = mc(); c.cfill(0, 0, 4, 4, 1, colour)
    c.hline(0, 0, 16, 2); c.hline(0, 1, 16, 0)
    for wx in range(1, 16, 4):                   # the high windows
        c.fill(wx, 4, 2, 5, 3)
    c.hline(0, 11, 16, 0)
    for px in range(0, 16, 2):                   # the corrugation
        c.vline(px, 12, 18, 0)
    c.fill(4, 16, 8, 14, 3)                      # the roller door
    for y in range(17, 30, 3):
        c.hline(4, y, 8, 0)
    c.hline(0, 30, 16, 0); c.hline(0, 31, 16, 0)
    return c


def face_club(colour=PURPLE):
    """A club: a dark front under a lit fascia, a sign down one side, a
    canopy over a doorway that shows the light inside."""
    c = mc(); c.cfill(0, 0, 4, 4, 0, colour)
    c.hline(0, 0, 16, 2)
    c.fill(0, 1, 16, 5, 3)                       # the fascia, lit in the club's colour
    c.hline(0, 6, 16, 2)
    c.fill(1, 8, 3, 18, 3)                       # the sign, down the near corner
    for y in range(9, 26, 3):
        c.hline(1, y, 3, 1)                      # its letters, unreadable at this size
    c.fill(6, 10, 7, 6, 1)                       # a window, the room glowing
    c.fill(5, 21, 8, 2, 2)                       # the canopy
    c.fill(7, 23, 4, 7, 1)                       # the doorway, light spilling out
    c.hline(0, 30, 16, 2); c.hline(0, 31, 16, 0)
    return c


def face_house(colour=YELLOW):
    """A house: a porch between two windows, under the eaves."""
    c = mc(); c.cfill(0, 0, 4, 4, 1, colour)
    c.hline(0, 0, 16, 0)
    for wx in (2, 11):
        c.fill(wx, 4, 3, 7, 3)
        c.hline(wx - 1, 11, 5, 2)
    c.fill(6, 14, 4, 16, 0)                      # the door, in the porch's shade
    c.hline(5, 13, 6, 2)                         # the porch's roof
    c.put(5, 14, 2); c.put(10, 14, 2)            # its posts
    c.hline(0, 30, 16, 0); c.hline(0, 31, 16, 0)
    return c


def face_motel(colour=PINK):
    """A motel: rooms off an open walkway, its rail along the front, a
    lamp between each pair of doors.  The shape Coquina is full of."""
    c = mc(); c.cfill(0, 0, 4, 4, 1, colour)
    c.hline(0, 0, 16, 2)
    c.fill(0, 1, 16, 9, 0)                       # the walkway, in shade
    for dx in range(1, 16, 4):
        c.fill(dx, 2, 2, 7, 3)                   # a room door
        c.put(dx + 3, 4, 2)                      # the lamp beside it
    c.hline(0, 10, 16, 2)                        # the rail
    c.hline(0, 11, 16, 1)
    for bx in range(0, 16, 2):
        c.vline(bx, 12, 3, 2)                    # its balusters
    c.hline(0, 15, 16, 2)
    c.fill(0, 16, 16, 14, 3)                     # the wall below, in the motel's colour
    for wx in range(2, 16, 4):
        c.fill(wx, 19, 2, 6, 1)                  # windows into the lower rooms
    c.hline(0, 30, 16, 0); c.hline(0, 31, 16, 0)
    return c


def face_strip(colour=ORANGE):
    """A strip mall: one long sign band over glass, units divided by piers,
    the parking apron in front of it."""
    c = mc(); c.cfill(0, 0, 4, 4, 1, colour)
    c.hline(0, 0, 16, 2)
    c.fill(0, 1, 16, 6, 3)                       # the sign band
    for sx in range(1, 15, 3):
        c.fill(sx, 3, 2, 2, 0)                   # lettering, in shadow
    c.hline(0, 7, 16, 0)
    c.fill(0, 9, 16, 16, 2)                      # the shopfront glass, lit
    for px in range(0, 16, 5):
        c.vline(px, 8, 17, 1)                    # the piers between units
        c.vline(px + 1, 8, 17, 0)
    c.hline(0, 25, 16, 0)
    c.hline(0, 30, 16, 0); c.hline(0, 31, 16, 0)
    return c


def face_gas(colour=RED):
    """A gas station: a canopy on posts over the pumps, the kiosk behind."""
    c = mc(); c.cfill(0, 0, 4, 4, 1, colour)
    c.fill(0, 0, 16, 3, 3)                       # the canopy, in the brand's colour
    c.hline(0, 3, 16, 2)
    c.hline(0, 4, 16, 0)                         # its underside
    c.vline(2, 5, 20, 2); c.vline(13, 5, 20, 2)  # the posts
    c.fill(5, 6, 6, 10, 1)                       # the kiosk behind them
    c.fill(6, 8, 4, 5, 2)                        # its window
    for px in (4, 11):                           # the pumps
        c.fill(px, 18, 2, 7, 0)
        c.put(px, 19, 3); c.put(px + 1, 19, 3)
    c.hline(0, 25, 16, 0)
    c.hline(0, 30, 16, 0); c.hline(0, 31, 16, 0)
    return c


def face_garage(colour=MGRAY):
    """A parking deck: open floors behind a band, cars showing as shapes."""
    c = mc(); c.cfill(0, 0, 4, 4, 1, colour)
    c.hline(0, 0, 16, 2)
    for top in (2, 17):
        c.fill(0, top, 16, 9, 0)                 # the open deck, in shade
        for cx in range(1, 15, 5):               # the cars parked in it
            c.fill(cx, top + 4, 3, 3, 3)
        c.hline(0, top + 9, 16, 1)               # the spandrel band
        c.hline(0, top + 10, 16, 2)
    c.hline(0, 30, 16, 0); c.hline(0, 31, 16, 0)
    return c


# each study: its name, then the metatiles from the roof down to the ground
# floor.  The roof is one metatile at most: at this angle a building is its
# face, with only the parapet and a little of the top showing.
STUDIES = [
    ("SHOPS", [roof(CYAN, unit=True), face_shops(BLUE), ground_shops(CYAN, door=True)]),
    ("OFFICE", [roof(WHITE, unit=True), face_office(LBLUE), face_office(LBLUE),
                face_office(LBLUE), ground_office(LBLUE)]),
    ("FLATS", [roof(RED), face_flats(BROWN), face_flats(BROWN), ground_shops(BROWN)]),
    ("WAREHOUSE", [roof(MGRAY, unit=True), face_warehouse(MGRAY)]),
    ("CLUB", [roof(PURPLE), face_club(PURPLE)]),
    ("HOUSE", [roof_pitched(RED), face_house(YELLOW)]),
    ("GARAGE", [roof(MGRAY), face_garage(MGRAY), face_garage(MGRAY)]),
    ("MOTEL", [roof(PINK), face_motel(PINK)]),
    ("STRIP MALL", [roof(ORANGE), face_strip(ORANGE)]),
    ("GAS", [roof(RED), face_gas(RED)]),
]


# ---------------------------------------------------------------------------
# the renderer: a canvas grid to RGB rows, as the chip reads it
# ---------------------------------------------------------------------------
def render(grid, zoom, bands=None):
    """grid: rows of Canvas or None (background).  -> (w, h, rows).

    bands, if given, is a list of (first screen row, (bg0, bg1, bg2)): the
    three shared colours as a raster interrupt would rewrite them partway
    down the screen, so the same characters read as a different place above
    and below the line."""
    gh, gw = len(grid), max(len(r) for r in grid)
    w, h = gw * 32 * zoom, gh * 32 * zoom

    def shared(y):
        out = BG
        for start, cols in (bands or ()):
            if y >= start:
                out = cols
        return out

    rows = [bytearray(RGB[shared(y // zoom)[0]] * w) for y in range(h)]
    for gy, line in enumerate(grid):
        for gx, c in enumerate(line):
            if c is None:
                continue
            for y in range(32):
                sh = shared(gy * 32 + y)
                for x in range(16):
                    v = c.px[y][x] & 3
                    col = sh[v] if v < 3 else c.col[y // 8][x // 4]
                    r, g, b = RGB[col]
                    for zy in range(zoom):
                        row = rows[(gy * 32 + y) * zoom + zy]
                        for zx in range(2 * zoom):
                            px = (gx * 32 + 2 * x) * zoom + zx
                            row[3 * px:3 * px + 3] = bytes((r, g, b))
    return w, h, rows


def caption(text, width_cells):
    """A caption metatile row: the text in white on the background."""
    c = Canvas(True, width_cells, 4)
    c.cfill(0, 0, width_cells, 4, 0, WHITE)
    c.ctext(0, 1, text[:width_cells * 2], WHITE, 2) if hasattr(c, "ctext") else None
    return c


def scene(zoom):
    """A crossing with the city around it: lanes, crossings, painted arrows
    and a word, pavements, and blocks whose faces stand toward the camera."""
    W_, H_ = 12, 9
    grid = [[None] * W_ for _ in range(H_)]
    for y in range(H_):
        for x in range(W_):
            grid[y][x] = pavement()
    for x in range(W_):                               # the street across
        grid[5][x] = road_lanes(False)
        grid[6][x] = road_lanes(False)
    for y in range(H_):                               # and the one down it
        grid[y][6] = road_lanes(True)
        grid[y][7] = road_lanes(True)
    for y in (5, 6):                                  # the crossing at the corner
        grid[y][6] = grid[y][7] = road()
    grid[4][6] = road_crossing(False); grid[4][7] = road_crossing(False)
    grid[7][6] = road_crossing(False); grid[7][7] = road_crossing(False)
    grid[5][5] = road_crossing(True); grid[6][5] = road_crossing(True)
    grid[5][8] = road_crossing(True); grid[6][8] = road_crossing(True)
    grid[5][2] = road_text(); grid[6][10] = road_arrow()
    grid[4][5] = kerb_corner(); grid[7][5] = kerb_corner()
    grid[4][8] = kerb_corner(); grid[7][8] = kerb_corner()
    # two blocks north of the street, their faces toward the camera
    for x, (rf, up, lo, col) in ((0, (roof(CYAN, unit=True), face_shops(BLUE),
                                     ground_shops(CYAN, door=True), CYAN)),
                                 (2, (roof(RED), face_flats(BROWN),
                                      ground_shops(BROWN), RED)),
                                 (8, (roof(WHITE, unit=True), face_office(LBLUE),
                                      ground_office(LBLUE), WHITE)),
                                 (10, (roof(ORANGE), face_strip(ORANGE),
                                       ground_shops(ORANGE), ORANGE))):
        for dx in (0, 1):
            grid[1][x + dx] = rf
            grid[2][x + dx] = up
            grid[3][x + dx] = lo
    # and one south of it, so the street sits between two frontages
    for x in (0, 2, 9, 11):
        grid[8][x] = ground_shops(PINK if x < 4 else YELLOW)
    return render(grid, zoom)


# ---------------------------------------------------------------------------
# top-down, where height is told by the edges, the shadow and what stands on
# the roof.  The light comes from the north-west throughout, so every
# building's shadow falls the same way and the eye reads the city as one
# scene (asked 2026-09-19: how to show really tall buildings from above).
# ---------------------------------------------------------------------------
def roof_td(colour, storeys, edge_n=True, edge_w=True, edge_s=True, edge_e=True, top=None):
    """A roof from above.  The lit rim on the north and west edges, and a
    band of wall inside the south and east ones whose width is the height:
    2 pixels a storey, to 12.  `top` draws what stands on it."""
    band = min(12, max(2, storeys))
    c = mc(); c.cfill(0, 0, 4, 4, 3, colour)
    if edge_n:
        c.hline(0, 0, 16, 2)                        # the parapet, lit from the north-west
    if edge_w:
        c.vline(0, 0, 32, 2)
    if edge_s:
        c.fill(0, 32 - band, 16, band, 0)           # the wall showing below the parapet
        c.hline(0, 31 - band, 16, 1)
    if edge_e:
        c.fill(16 - band // 2, 0, band // 2, 32, 0)
        c.vline(15 - band // 2, 0, 32, 1)
    if top == "plant":                              # air handling units, lit north-west
        for ux, uy, uw, uh in ((2, 5, 5, 7), (9, 14, 5, 9)):
            c.fill(ux, uy, uw, uh, 0)               # the unit's shaded body
            c.hline(ux, uy, uw, 2); c.vline(ux, uy, uh, 2)
            c.fill(ux + 2, uy + 2, 2, 2, 1)
    elif top == "helipad":                          # a circle and its H
        c.rect(3, 6, 10, 18, 2)
        c.rect(4, 8, 8, 14, 0)
        c.fill(6, 11, 2, 8, 2); c.fill(9, 11, 2, 8, 2); c.fill(7, 14, 3, 2, 2)
    elif top == "tank":                             # a water tank on its legs
        c.fill(5, 8, 7, 9, 0)
        c.hline(5, 8, 7, 2); c.vline(5, 8, 9, 2)
        c.vline(6, 17, 3, 0); c.vline(10, 17, 3, 0)
    elif top == "mast":                             # a mast, its lamp a sprite
        c.vline(7, 5, 20, 2); c.vline(8, 5, 20, 2)
        c.hline(5, 11, 6, 0); c.hline(4, 18, 8, 0)
    return c


def shadow_ground(under, storeys, part):
    """The shadow a building throws south, `part` tiles from its wall: a
    dither over whatever the ground is, so the markings still read through
    it, and a half tile at its end."""
    c = under()
    reach = max(1, storeys // 5)                    # a tile of shadow every five storeys
    if part > reach:
        return c
    if part == reach:
        c.dither(0, 0, 16, 16, 0, None) if False else c.cdither(0, 0, 4, 2, 0, 1)
    else:
        c.cdither(0, 0, 4, 4, 0, 1)
    return c


def tall_scene(zoom, cues="full"):
    """One screenful of top-down city: four buildings of 2, 6, 10 and 16
    storeys on the same street.  cues = "flat" draws them as the day set
    does now, with a parapet and nothing else; "edges" adds the wall band
    and the cast shadow; "full" adds what stands on the roof."""
    W_, H_ = 10, 6
    grid = [[pavement() for _ in range(W_)] for _ in range(H_)]
    for x in range(W_):
        grid[4][x] = road_lanes(False)
        grid[5][x] = road_lanes(False)
    grid[4][6] = road_text()
    blocks = ((0, 2, CYAN, 2, None), (3, 2, PINK, 6, "tank"),
              (5, 2, LGRAY, 10, "plant"), (8, 2, WHITE, 16, "helipad"))
    for x0, w, col, storeys, top in blocks:
        band = storeys if cues != "flat" else 2
        for j in range(2):                          # two metatiles of roof, north to south
            for i in range(w):
                grid[1 + j][x0 + i] = roof_td(
                    col, band,
                    edge_n=(j == 0), edge_w=(i == 0), edge_s=(j == 1),
                    edge_e=(i == w - 1),
                    top=(top if cues == "full" and i == w - 1 and j == 0 else None))
        if cues == "flat":
            continue
        for i in range(w):                          # its shadow on the pavement below
            grid[3][x0 + i] = shadow_ground(pavement, storeys, 1)
        if storeys >= 10:                           # a tall one darkens the road too
            for i in range(w):
                grid[4][x0 + i] = shadow_ground(lambda: road_lanes(False), storeys, 2)
    w, h, px = render(grid, zoom)
    cars = car_frames_mc()
    sprite(px, cars[1], 60, 4 * 32 + 8, RED, zoom)
    sprite(px, cars[3], 220, 4 * 32 + 42, LBLUE, zoom)
    sprite(px, ped_frames_mc()[0], 120, 3 * 32 + 10, YELLOW, zoom)

    return w, h, px


def sprite(rows_rgb, frame, x, y, colour, zoom, mc0=BLACK, mc1=WHITE):
    """Composite a multicolour sprite frame (rows of '.', '1', '2', '3') at
    screen pixel (x, y): '2' is the sprite's own colour, '1' and '3' the two
    shared sprite colours, '.' shows what is behind."""
    for j, line in enumerate(frame):
        for i, ch in enumerate(line):
            if ch == ".":
                continue
            col = {"1": mc0, "2": colour, "3": mc1}[ch]
            r, g, b = RGB[col]
            for zy in range(zoom):
                row = rows_rgb[(y + j) * zoom + zy]
                for zx in range(2 * zoom):
                    px = (x + 2 * i) * zoom + zx
                    if 0 <= 3 * px < len(row):
                        row[3 * px:3 * px + 3] = bytes((r, g, b))


def band_scene(zoom):
    """One screenful, one set of characters, and a raster split: above the
    line the shared colours are the city's (asphalt, concrete, markings);
    below it they are the shore's (wet sand, dry sand, foam).  Nothing in
    the tiles changes -- only the three registers."""
    W_, H_ = 10, 6
    grid = [[pavement() for _ in range(W_)] for _ in range(H_)]
    for x in range(W_):
        grid[2][x] = road_lanes(False)
        grid[3][x] = road_lanes(False)
    grid[2][2] = road_text(); grid[3][7] = road_arrow()
    for x in range(W_):                               # a frontage along the top
        grid[0][x] = roof_td(CYAN if x < 5 else PINK, 6, edge_s=False)
        grid[1][x] = roof_td(CYAN if x < 5 else PINK, 6, edge_n=False)
    for x in range(W_):                               # and a boardwalk below
        grid[5][x] = road_lanes(False)
    w, h, px = render(grid, zoom, bands=[(4 * 32, (BROWN, YELLOW, WHITE))])
    cars = car_frames_mc()
    sprite(px, cars[1], 60, 2 * 32 + 10, RED, zoom)
    sprite(px, cars[3], 210, 3 * 32 + 12, LBLUE, zoom)
    sprite(px, ped_frames_mc()[0], 130, 4 * 32 + 20, WHITE, zoom)
    return w, h, px


def street(deep, zoom):
    """One screenful of city, 10 by 6 metatiles (320 x 192, the playfield's
    184 rows and a little over): a street with a block on each side, whose
    faces are one metatile tall (shallow) or three (deep).  Two cars on the
    road for scale."""
    W_, H_ = 10, 6
    grid = [[pavement() for _ in range(W_)] for _ in range(H_)]
    road_row = 3 if deep else 3
    for x in range(W_):                                  # the street across the middle
        grid[road_row][x] = road_lanes(False)
        grid[road_row + 1][x] = road_lanes(False)
    grid[road_row][2] = road_text()
    grid[road_row + 1][7] = road_arrow()
    # the block north of the street: its roof, then its face down to the kerb
    if deep:
        stack = [roof(CYAN, unit=True), face_shops(BLUE), face_shops(BLUE),
                 ground_shops(CYAN, door=True)]
    else:
        stack = [roof(CYAN, unit=True), ground_shops(CYAN, door=True)]
    for j, tile in enumerate(reversed(stack)):
        row = road_row - 1 - j
        if row < 0:
            break
        for x in range(W_):
            grid[row][x] = tile if x % 5 else (face_office(LBLUE) if deep and j else roof(WHITE))
    for x in range(W_):                                  # the kerb shadow under it
        if road_row - 1 >= 0:
            pass
    # the block south of the street, seen only as its roof and parapet
    for x in range(W_):
        grid[H_ - 1][x] = roof(RED) if not deep else ground_shops(BROWN)
    w, h, px = render(grid, zoom)
    cars = car_frames_mc()
    sprite(px, cars[1], 40, road_row * 32 + 6, RED, zoom)        # eastbound
    sprite(px, cars[3], 210, road_row * 32 + 40, LBLUE, zoom)    # westbound
    sprite(px, ped_frames_mc()[0], 150, road_row * 32 - 14, PINK, zoom)
    return w, h, px


def main():
    out = sys.argv[1]
    zoom = int(sys.argv[sys.argv.index("--zoom") + 1]) if "--zoom" in sys.argv else 2
    if "--bands" in sys.argv:
        w, h, px = band_scene(zoom)
        write_png(out, w, h, px)
        print(f"{out}: one screen, two palettes across a raster split, {w}x{h} at {zoom}x")
        return
    if "--styles" in sys.argv:
        w, h, px = styles_sheet(zoom)
        write_png(out, w, h, px)
        print(f"{out}: five height styles, {w}x{h} at {zoom}x")
        return
    if "--tall" in sys.argv:
        cues = sys.argv[sys.argv.index("--cues") + 1] if "--cues" in sys.argv else "full"
        w, h, px = tall_scene(zoom, cues)
        write_png(out, w, h, px)
        print(f"{out}: top-down heights ({cues}), {w}x{h} at {zoom}x")
        return
    if "--street" in sys.argv:
        deep = "--deep" in sys.argv
        w, h, px = street(deep, zoom)
        write_png(out, w, h, px)
        print(f"{out}: one screenful, {'deep' if deep else 'shallow'} faces, {w}x{h} at {zoom}x")
        return
    if "--scene" in sys.argv:
        w, h, px = scene(zoom)
        write_png(out, w, h, px)
        print(f"{out}: a crossing, {w}x{h} at {zoom}x")
        return
    tallest = max(len(s[1]) for s in STUDIES)
    cols = 3 * len(STUDIES) + 1                 # two metatiles each, a gap between
    rows = tallest + 3                          # sky, the buildings, pavement, road
    grid = [[None] * cols for _ in range(rows)]
    base = rows - 3                             # every building stands on the same line
    for i, (_, stack) in enumerate(STUDIES):
        x = 3 * i + 1
        for j, tile in enumerate(reversed(stack)):
            for dx in (0, 1):
                grid[base - j][x + dx] = tile
    for x in range(cols):                       # the pavement and the street in front
        grid[base + 1][x] = pavement_shadow()
        grid[base + 2][x] = pavement() if x % 3 else road()
    w, h, px = render(grid, zoom)
    write_png(out, w, h, px)
    print(f"{out}: {len(STUDIES)} studies, {w}x{h} at {zoom}x "
          f"({', '.join(n for n, _ in STUDIES)})")




# ---------------------------------------------------------------------------
# Five ways to show height from directly above, after a reference sheet the
# user brought on 2026-09-19: flat roof and shadow, a wall reveal, tiered
# setbacks, edge bands of floor lines, and a cutaway slice.  Drawn here on
# one canvas to compare the looks; a tileset would cut them into 32-pixel
# metatiles, which costs the characters counted in the page.
# ---------------------------------------------------------------------------
def sheet_ground(c, w, h):
    """Grass, a pavement grid and a road down the right of each column."""
    c.cfill(0, 0, w, h, 3, GREEN)
    for cy in range(h):
        for cx in range(w):
            c.dots(cx * 4, cy * 8, 4, 8, 3, 0, 4, 4)


def sheet_pavement(c, cx, cy, cw, ch):
    c.cfill(cx, cy, cw, ch, 1, BLUE)
    c.dots(cx * 4, cy * 8, cw * 4, ch * 8, 1, 0, 8, 8)


def sheet_road(c, cx, cy, cw, ch):
    c.cfill(cx, cy, cw, ch, 0, WHITE)
    c.vdashes(cx * 4 + cw * 2, cy * 8, ch * 8, 6, 6, 2)


def win_grid(c, x, y, w, h, step=4):
    """Windows in a wall: two-pixel panes, lit, in rows."""
    for wy in range(y + 1, y + h - 1, 5):
        for wx in range(x + 1, x + w - 1, step):
            c.fill(wx, wy, 2, 3, 2)


def study(c, x, y, w, h, storeys, style, colour):
    """One building, in multicolour pixels: (x, y) its top-left, (w, h) its
    roof, `storeys` its height.  The light is from the north-west."""
    shade = max(2, min(14, storeys))
    # the shadow it throws south-east, its reach the height
    reach = max(2, min(16, storeys))
    c.dots(x + reach // 2, y + h, w, reach, 0, 1, 2, 2)         # softer than a full dither
    c.dots(x + w, y + reach // 2, reach, h, 0, 1, 2, 2)
    if style == "tiers":
        step = max(1, w // 6)
        tiers = 1 if storeys <= 3 else (2 if storeys <= 9 else 3)
        for t in range(tiers):
            tx, ty = x + t * step, y + t * step
            tw, th = w - 2 * t * step, h - 2 * t * step
            c.fill(tx, ty, tw, th, 3)
            c.crect(tx // 4, ty // 8, max(1, tw // 4), max(1, th // 8), colour)
            c.hline(tx, ty, tw, 2); c.vline(tx, ty, th, 2)      # the lit rim
            c.fill(tx, ty + th - 2, tw, 2, 0)                   # the step down
            c.fill(tx + tw - 2, ty, 2, th, 0)
        return
    c.fill(x, y, w, h, 3)                                       # the roof
    c.crect(x // 4, y // 8, max(1, w // 4), max(1, h // 8), colour)
    c.hline(x, y, w, 2); c.vline(x, y, h, 2)                    # the lit rim
    if style == "flat":
        c.hline(x, y + h - 1, w, 0); c.vline(x + w - 1, y, h, 0)
    elif style == "reveal":                                     # a wall face, south and east
        c.fill(x, y + h - shade, w, shade, 1)
        c.fill(x + w - shade // 2, y, shade // 2, h, 1)
        win_grid(c, x, y + h - shade, w, shade)
        c.hline(x, y + h - shade - 1, w, 0)
    elif style == "bands":                                      # floor lines round the edge
        band = max(3, min(12, storeys))
        c.fill(x, y + h - band, w, band, 1)
        c.fill(x + w - band // 2, y, band // 2, h, 1)
        for i in range(0, band, 2):
            c.hline(x, y + h - band + i, w, 0)
        for i in range(0, band // 2, 2):
            c.vline(x + w - band // 2 + i, y, h, 0)
    elif style == "cutaway":                                    # one side sliced open
        cut = max(4, min(18, storeys + 2))
        c.fill(x, y + h - cut, w // 2, cut, 1)
        c.hline(x, y + h - cut, w // 2, 2)
        win_grid(c, x, y + h - cut, w // 2, cut, 3)
        c.hline(x, y + h - 1, w, 0); c.vline(x + w - 1, y, h, 0)
    # a rooftop unit, so the roof is never empty
    if storeys >= 6 and style != "tiers":
        c.fill(x + 3, y + 3, 5, 5, 0); c.hline(x + 3, y + 3, 5, 2)


def styles_sheet(zoom):
    """Five columns, three buildings each: 3, 8 and 16 storeys."""
    COLW, ROWH = 15, 11
    styles = (("flat", "FLAT ROOF AND SHADOW"), ("reveal", "WALL REVEAL"),
              ("tiers", "TIERED SETBACKS"), ("bands", "EDGE BANDS"),
              ("cutaway", "CUTAWAY SLICE"))
    W_, H_ = COLW * len(styles), ROWH * 3
    c = Canvas(True, W_, H_)
    sheet_ground(c, W_, H_)
    cars = car_frames_mc()
    for i, (style, _) in enumerate(styles):
        cx = i * COLW
        sheet_road(c, cx + COLW - 3, 0, 3, H_)
        for j, (storeys, colour) in enumerate(((3, CYAN), (8, PINK), (16, LGRAY))):
            cy = j * ROWH
            sheet_pavement(c, cx + 1, cy + 1, COLW - 5, ROWH - 3)
            study(c, (cx + 2) * 4, (cy + 2) * 8, (COLW - 7) * 4, (ROWH - 5) * 8,
                  storeys, style, colour)
    w, h, px = render([[None]], zoom)                           # a blank of the right size
    w, h = c.pw * 2 * zoom, c.ph * zoom
    rows = [bytearray(RGB[BG[0]] * w) for _ in range(h)]
    for yy in range(c.ph):
        for xx in range(c.pw):
            v = c.px[yy][xx] & 3
            col = BG[v] if v < 3 else c.col[yy // 8][xx // 4]
            r, g, b = RGB[col]
            for zy in range(zoom):
                row = rows[yy * zoom + zy]
                for zx in range(2 * zoom):
                    p = xx * 2 * zoom + zx
                    row[3 * p:3 * p + 3] = bytes((r, g, b))
    for i in range(len(styles)):                                # a car on each street, for scale
        road_x = (i * COLW + COLW - 2) * 8                      # cells to screen pixels
        for j, col in enumerate((RED, YELLOW, LBLUE)):
            sprite(rows, cars[0], road_x, 40 + j * ROWH * 8, col, zoom)
    return w, h, rows


if __name__ == "__main__":
    main()
