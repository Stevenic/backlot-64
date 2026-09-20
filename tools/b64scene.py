#!/usr/bin/env python3
"""A whole screen of the city, in the chosen building style.

Design 2 of the supplied sheets (a roof over a south-facing facade) was
chosen on 2026-09-19.  This builds its characters from the matrix in
art/buildings.txt, adds the ground the city needs in the same palette, and
draws one screenful -- 40 by 25 characters, which is what the VIC-II shows
-- with cars and people as sprites over it.

The palette is the matrix's: grey, brown and green shared across the
screen, white as each cell's own colour.  Sprites have their own colours
and transparency, which is why the cars and the people can sit anywhere.

usage: b64scene.py <out.png> [--zoom 3] [--screen] [--no-sprites]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from b64art import (  # noqa: E402
    Char, BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW,
    ORANGE, BROWN, MGRAY, LGRAY, LGREEN, car_frames_mc, ped_frames_mc,
)
from b64palette import RGB  # noqa: E402
from b64png import write_png  # noqa: E402
from b64matrix import read_designs  # noqa: E402

SHARED = (MGRAY, BROWN, GREEN)          # $D021, $D022, $D023 (the matrices' own)
SHARED_DARK = (BLACK, BROWN, LGRAY)     # black to outline with, brown walls, grey concrete
VALUE = {"R": 0, "B": 1, "G": 2, "W": 3}


def design_chars(path="art/buildings.txt", want="2"):
    """The nine characters of one design, as Char objects."""
    d = [x for x in read_designs(path) if x["name"].split()[0] == want][0]
    out = {}
    for cy in range(3):
        for cx in range(3):
            ch = Char(True, WHITE)
            for y in range(8):
                row = d["rows"][cy * 8 + y]
                for i in range(4):
                    ch.px[y][i] = VALUE[row[cx * 8 + 2 * i]]
            out[(cx, cy)] = ch
    return out


def ground_chars():
    """The ground, in the same three shared colours: grass with dirt, a
    pavement of grey slabs, asphalt with white markings, and a tree."""
    c = {}
    for n, tufts in enumerate((((1, 2), (3, 5)), ((0, 6), (2, 1)), ((3, 3), (1, 7)), ((2, 4), (0, 0)))):
        g = Char(True, WHITE).all(2)                 # green
        for x, y in tufts:
            g.put(x, y, 1)                           # a patch of dirt
        c[f"grass{n}"] = g
    walk = Char(True, WHITE).all(0)                  # grey slabs, their joints in brown
    walk.hline(0, 0, 4, 1); walk.vline(0, 0, 8, 1)
    c["walk"] = walk
    c["walk_plain"] = Char(True, WHITE).all(0)
    c["road"] = Char(True, WHITE).all(0)             # asphalt: plain grey
    dash = Char(True, WHITE).all(0)
    dash.hline(0, 3, 2, 3); dash.hline(0, 4, 2, 3)   # a lane dash, across
    c["dash_h"] = dash
    vdash = Char(True, WHITE).all(0)
    vdash.fill(1, 1, 1, 5, 3)                        # and down
    c["dash_v"] = vdash
    kerb_n = Char(True, WHITE).all(0); kerb_n.hline(0, 0, 4, 1)
    kerb_s = Char(True, WHITE).all(0); kerb_s.hline(0, 7, 4, 1)
    kerb_w = Char(True, WHITE).all(0); kerb_w.vline(0, 0, 8, 1)
    kerb_e = Char(True, WHITE).all(0); kerb_e.vline(3, 0, 8, 1)
    c.update(kerb_n=kerb_n, kerb_s=kerb_s, kerb_w=kerb_w, kerb_e=kerb_e)
    for tag, (cx, cy) in (("tree_nw", (0, 0)), ("tree_ne", (1, 0)),
                          ("tree_sw", (0, 1)), ("tree_se", (1, 1))):
        t = Char(True, WHITE).all(2)                 # a crown of green over the grass,
        for y in range(8):                           # its shaded side in brown
            for x in range(4):
                gx, gy = cx * 4 + x, cy * 8 + y
                dx, dy = gx - 3.5, (gy - 7.5) * 0.5
                d = dx * dx + dy * dy
                if d <= 5:
                    t.put(x, y, 3)                   # the crown's lit top, the cell's colour
                elif d <= 9:
                    t.put(x, y, 2)                   # its green body
                elif d <= 14:
                    t.put(x, y, 0)                   # the shadow it casts on the grass
        if tag in ("tree_sw", "tree_se"):
            t.vline(3 if tag == "tree_sw" else 0, 5, 3, 1)   # the trunk, in brown
        t.colour = LGREEN if False else GREEN
        c[tag] = t
    return c


def place_building(grid, b, x, y, w, storeys, colour=WHITE):
    """A building w characters wide with `storeys` floors of facade: the
    design's top row, its middle, then its facade row repeated.  The cell
    colour is the building's own -- its windows and lit edges take it."""
    rows = [0] + [1] + [2] * storeys
    for j, src in enumerate(rows):
        for i in range(w):
            col = 0 if i == 0 else (2 if i == w - 1 else 1)
            if 0 <= y + j < len(grid) and 0 <= x + i < len(grid[0]):
                ch = b[(col, src)].copy()
                ch.colour = colour
                grid[y + j][x + i] = ch


def scene(b, c, sprites=True):
    """One screenful: two streets, pavements, plots with buildings and
    trees.  Returns the character grid and where the sprites go."""
    W_, H_ = 40, 25
    g = [[c[f"grass{((x * 11) ^ (y * 5)) % 4}"] for x in range(W_)] for y in range(H_)]

    def road_h(row):                                 # four characters tall
        for x in range(W_):
            g[row][x] = c["kerb_n"]
            g[row + 1][x] = c["dash_h"] if (x % 4) < 2 else c["road"]
            g[row + 2][x] = c["road"]
            g[row + 3][x] = c["kerb_s"]

    def road_v(col):
        for y in range(H_):
            g[y][col] = c["kerb_w"]
            g[y][col + 1] = c["dash_v"] if (y % 4) < 2 else c["road"]
            g[y][col + 2] = c["road"]
            g[y][col + 3] = c["kerb_e"]

    road_h(10)
    road_v(26)
    for x in range(W_):                              # pavements along the streets
        for row in (9, 14):
            g[row][x] = c["walk"]
    for y in range(H_):
        for col in (25, 30):
            g[y][col] = c["walk"]

    place_building(g, b, 2, 2, 6, 2, WHITE)          # a wide block, two floors
    place_building(g, b, 11, 1, 5, 3, CYAN)          # taller, its windows lit blue
    place_building(g, b, 18, 3, 4, 1, YELLOW)        # a low one
    place_building(g, b, 32, 1, 6, 4, WHITE)         # a tower across the junction
    place_building(g, b, 3, 16, 5, 2, YELLOW)        # south of the street
    place_building(g, b, 12, 17, 7, 1, WHITE)
    place_building(g, b, 32, 16, 5, 3, CYAN)

    for tx, ty in ((9, 6), (17, 1), (23, 4), (9, 21), (21, 20), (24, 15), (38, 12)):
        for (dx, dy), tag in (((0, 0), "tree_nw"), ((1, 0), "tree_ne"),
                              ((0, 1), "tree_sw"), ((1, 1), "tree_se")):
            if 0 <= ty + dy < H_ and 0 <= tx + dx < W_:
                ch = c[tag].copy()
                ch.colour = YELLOW if (tx + ty) % 3 == 0 else GREEN   # a lit crown
                g[ty + dy][tx + dx] = ch

    spr = []
    if sprites:
        cars = car_frames_mc()
        spr += [(cars[1], 40, 90, RED), (cars[3], 150, 100, CYAN), (cars[1], 250, 90, YELLOW),
                (cars[0], 212, 30, LGREEN), (cars[2], 212, 150, PURPLE)]
        peds = ped_frames_mc()
        spr += [(peds[0], 80, 76, WHITE), (peds[1], 120, 120, ORANGE),
                (peds[0], 206, 60, CYAN), (peds[1], 300, 128, WHITE)]
    return g, spr


def render(grid, spr, zoom):
    gh, gw = len(grid), len(grid[0])
    w, h = gw * 8 * zoom, gh * 8 * zoom
    rows = [bytearray(RGB[SHARED[0]] * w) for _ in range(h)]
    for gy, line in enumerate(grid):
        for gx, ch in enumerate(line):
            for y in range(8):
                for x in range(4):
                    v = ch.px[y][x]
                    col = SHARED[v] if v < 3 else ch.colour
                    r, g, b = RGB[col]
                    for zy in range(zoom):
                        row = rows[(gy * 8 + y) * zoom + zy]
                        for zx in range(2 * zoom):
                            p = (gx * 8 + x * 2) * zoom + zx
                            row[3 * p:3 * p + 3] = bytes((r, g, b))
    for item in spr:                                 # the sprites, over everything
        frame, sx, sy, colour = item[:4]
        big = item[4] if len(item) > 4 else False    # the VIC can double a sprite's size
        step = 2 if big else 1
        for j, line in enumerate(frame):
            for i, ch in enumerate(line):
                if ch == ".":
                    continue
                col = {"1": BLACK, "2": colour, "3": WHITE}[ch]
                r, g, b = RGB[col]
                for ry in range(step):
                    for zy in range(zoom):
                        yy = (sy + j * step + ry) * zoom + zy
                        if not 0 <= yy < h:
                            continue
                        row = rows[yy]
                        for zx in range(2 * zoom * step):
                            p = (sx + 2 * i * step) * zoom + zx
                            if 0 <= 3 * p < len(row) - 3:
                                row[3 * p:3 * p + 3] = bytes((r, g, b))
    return w, h, rows


# ---------------------------------------------------------------------------
# Zoomed in one factor: the same characters, twice the size for everything,
# so a building spans six by seven cells instead of three by three.  Each of
# those cells carries its own colour, which is where the extra colour comes
# from -- the hardware rules do not change at all.
# ---------------------------------------------------------------------------
def dark_chars():
    """The same street under a palette with black in it: black outlines and
    asphalt, brown masonry, light grey concrete, and every cell free to
    spend its own colour on grass, glass, signs or paint."""
    c = {}

    def mc(fill=0):
        return Char(True, GREEN).all(fill)

    for n, tufts in enumerate((((1, 2), (3, 5)), ((0, 6), (2, 1)), ((3, 3), (1, 7)), ((2, 4), (0, 0)))):
        g = mc(3)                                    # grass: the cell's green, earth showing
        for x, y in tufts:
            g.put(x, y, 1)
        c[f"grass{n}"] = g
    walk = mc(2)                                     # concrete slabs, one joint a slab
    walk.hline(0, 0, 4, 0)
    walk.colour = WHITE
    c["walk"] = walk
    walk2 = mc(2); walk2.hline(0, 0, 4, 0); walk2.vline(0, 0, 8, 0)
    walk2.colour = WHITE
    c["walk_plain"] = walk2
    road = mc(0); road.colour = WHITE                # asphalt, black
    c["road"] = road
    dash = mc(0); dash.hline(0, 3, 2, 3); dash.hline(0, 4, 2, 3)
    dash.colour = WHITE                              # the markings are white, not the grass
    c["dash_h"] = dash
    vdash = mc(0); vdash.fill(1, 1, 1, 5, 3); vdash.colour = WHITE
    c["dash_v"] = vdash
    kerb_n = mc(0); kerb_n.hline(0, 0, 4, 2); kerb_n.hline(0, 1, 4, 2); kerb_n.colour = WHITE
    kerb_s = mc(0); kerb_s.hline(0, 7, 4, 2); kerb_s.hline(0, 6, 4, 2); kerb_s.colour = WHITE
    kerb_w = mc(0); kerb_w.vline(0, 0, 8, 2); kerb_w.colour = WHITE
    kerb_e = mc(0); kerb_e.vline(3, 0, 8, 2); kerb_e.colour = WHITE
    c.update(kerb_n=kerb_n, kerb_s=kerb_s, kerb_w=kerb_w, kerb_e=kerb_e)
    cross = mc(0)                                    # a pedestrian crossing
    cross.fill(0, 1, 1, 6, 3); cross.fill(2, 1, 1, 6, 3)
    cross.colour = WHITE
    c["crossing"] = cross
    bay = mc(0); bay.vline(0, 1, 6, 3); bay.colour = WHITE    # a painted parking bay
    c["bay"] = bay
    stop = mc(0); stop.hline(0, 0, 4, 3); stop.hline(0, 1, 4, 3); stop.colour = WHITE
    c["stopline"] = stop
    alley = mc(0); alley.put(1, 3, 2); alley.put(3, 6, 2); alley.colour = WHITE
    c["alley"] = alley
    for tag, (cx, cy) in (("tree_nw", (0, 0)), ("tree_ne", (1, 0)),
                          ("tree_sw", (0, 1)), ("tree_se", (1, 1))):
        t = mc(3)                                    # a crown in the cell's green,
        for y in range(8):                           # outlined black, over the grass
            for x in range(4):
                gx, gy = cx * 4 + x, cy * 8 + y
                dx, dy = gx - 3.5, (gy - 7.5) * 0.5
                d = dx * dx + dy * dy
                if d <= 6:
                    t.put(x, y, 2)                   # the lit top of the crown
                elif d <= 11:
                    t.put(x, y, 0)                   # its shaded edge and shadow
        if tag in ("tree_sw", "tree_se"):
            t.vline(3 if tag == "tree_sw" else 0, 5, 3, 1)
        c[tag] = t

    roof = mc(2)                                     # roof: grey gravel, black grit
    roof.put(1, 2, 0); roof.put(3, 5, 0)
    c["d_roof"] = roof
    cap_n = mc(2); cap_n.hline(0, 0, 4, 0); cap_n.hline(0, 1, 4, 3); cap_n.hline(0, 2, 4, 0)
    c["d_cap_n"] = cap_n
    cap_s = mc(2); cap_s.hline(0, 7, 4, 0); cap_s.hline(0, 6, 4, 3); cap_s.hline(0, 5, 4, 0)
    c["d_cap_s"] = cap_s
    cap_w = mc(2); cap_w.vline(0, 0, 8, 0); cap_w.vline(1, 0, 8, 3)
    c["d_cap_w"] = cap_w
    cap_e = mc(2); cap_e.vline(3, 0, 8, 0); cap_e.vline(2, 0, 8, 3)
    c["d_cap_e"] = cap_e
    ac = mc(2); ac.rect(0, 1, 4, 6, 0); ac.fill(1, 2, 2, 4, 3); ac.hline(1, 4, 2, 0)
    c["d_ac"] = ac
    tank = mc(2); tank.fill(1, 1, 2, 4, 3); tank.hline(1, 1, 2, 0)
    tank.vline(1, 5, 2, 0); tank.vline(2, 5, 2, 0)
    c["d_tank"] = tank

    wall = mc(1)                                     # brown masonry
    c["d_wall"] = wall
    cornice = mc(1); cornice.hline(0, 0, 4, 2); cornice.hline(0, 1, 4, 0)
    c["d_cornice"] = cornice
    win = mc(1)                                      # a window: glass in the cell's colour,
    win.fill(1, 1, 2, 5, 3); win.hline(1, 6, 2, 0); win.hline(1, 0, 2, 0)
    c["d_win"] = win
    win2 = mc(1)
    win2.fill(0, 2, 1, 4, 3); win2.fill(2, 2, 1, 4, 3)
    win2.hline(0, 6, 4, 0); win2.hline(0, 1, 4, 0)
    c["d_win2"] = win2
    band = mc(1); band.hline(0, 0, 4, 0); band.hline(0, 7, 4, 2)
    c["d_band"] = band
    sign = mc(1); sign.fill(0, 1, 4, 5, 3); sign.fill(1, 2, 1, 3, 0); sign.fill(3, 3, 1, 2, 0)
    c["d_sign"] = sign
    awning = mc(1); awning.fill(0, 0, 4, 3, 3); awning.hline(0, 3, 4, 0)
    c["d_awning"] = awning
    shop = mc(1); shop.fill(0, 0, 4, 5, 3); shop.hline(0, 5, 4, 0); shop.fill(0, 6, 4, 2, 2)
    c["d_shop"] = shop
    door = mc(1); door.fill(1, 0, 2, 7, 0); door.hline(0, 7, 4, 2)
    c["d_door"] = door
    return c


def detail_chars():
    """A building's parts at the closer scale, and the ground with it."""
    c = ground_chars()
    def mc(fill=0):
        return Char(True, WHITE).all(fill)

    roof = mc(0)                                     # gravel roof, grey
    roof.put(1, 2, 1); roof.put(3, 5, 1)
    c["d_roof"] = roof
    cap_n = mc(0); cap_n.hline(0, 0, 4, 1); cap_n.hline(0, 1, 4, 3); cap_n.hline(0, 2, 4, 1)
    c["d_cap_n"] = cap_n
    cap_s = mc(0); cap_s.hline(0, 7, 4, 1); cap_s.hline(0, 6, 4, 3); cap_s.hline(0, 5, 4, 1)
    c["d_cap_s"] = cap_s
    cap_w = mc(0); cap_w.vline(0, 0, 8, 1); cap_w.vline(1, 0, 8, 3)
    c["d_cap_w"] = cap_w
    cap_e = mc(0); cap_e.vline(3, 0, 8, 1); cap_e.vline(2, 0, 8, 3)
    c["d_cap_e"] = cap_e
    ac = mc(0)                                       # plant on the roof
    ac.rect(0, 1, 4, 6, 1); ac.fill(1, 2, 2, 4, 3); ac.hline(1, 4, 2, 1)
    c["d_ac"] = ac
    tank = mc(0)
    tank.fill(1, 1, 2, 4, 3); tank.hline(1, 1, 2, 1); tank.vline(1, 5, 2, 1); tank.vline(2, 5, 2, 1)
    c["d_tank"] = tank

    wall = mc(1)                                     # brown wall
    c["d_wall"] = wall
    cornice = mc(1); cornice.hline(0, 0, 4, 3); cornice.hline(0, 1, 4, 0)
    c["d_cornice"] = cornice
    win = mc(1)                                      # a tall window, its sill lit
    win.fill(1, 1, 2, 5, 3); win.hline(1, 6, 2, 0)
    c["d_win"] = win
    win_pair = mc(1)                                 # two narrow windows
    win_pair.fill(0, 2, 1, 4, 3); win_pair.fill(2, 2, 1, 4, 3); win_pair.hline(0, 6, 4, 0)
    c["d_win2"] = win_pair
    band = mc(1); band.hline(0, 0, 4, 0); band.hline(0, 7, 4, 0)
    c["d_band"] = band
    sign = mc(1)                                     # a sign band, the cell's own colour
    sign.fill(0, 1, 4, 5, 3); sign.fill(1, 2, 1, 3, 1); sign.fill(3, 3, 1, 2, 1)
    c["d_sign"] = sign
    awning = mc(1)                                   # an awning over the shopfront
    awning.fill(0, 0, 4, 3, 3); awning.hline(0, 3, 4, 0)
    c["d_awning"] = awning
    shop = mc(1)                                     # shop glass, lit
    shop.fill(0, 0, 4, 5, 3); shop.hline(0, 5, 4, 0); shop.fill(0, 6, 4, 2, 1)
    c["d_shop"] = shop
    door = mc(1)                                     # a doorway, dark, with a step
    door.fill(1, 0, 2, 7, 0); door.hline(0, 7, 4, 3)
    c["d_door"] = door
    return c


def place_detail(g, c, x, y, w, floors, wall_col, win_col, sign_col):
    """A building at the closer scale: capped roof, a sign band, floors of
    windows, a shopfront with an awning and a door."""
    def put(i, j, ch, colour):
        if 0 <= y + j < len(g) and 0 <= x + i < len(g[0]):
            k = ch.copy(); k.colour = colour
            g[y + j][x + i] = k

    for i in range(w):                               # two rows of roof, capped
        put(i, 0, c["d_cap_n"], WHITE)
        put(i, 1, c["d_roof"], WHITE)
    put(0, 1, c["d_cap_w"], WHITE); put(w - 1, 1, c["d_cap_e"], WHITE)
    put(0, 0, c["d_cap_w"], WHITE); put(w - 1, 0, c["d_cap_e"], WHITE)
    if w > 3:
        put(w - 2, 1, c["d_ac"], WHITE); put(1, 1, c["d_tank"], WHITE)
    row = 2
    for i in range(w):                               # the cornice, then the sign
        put(i, row, c["d_cornice"], WHITE)
    row += 1
    for i in range(w):
        put(i, row, c["d_sign"] if 0 < i < w - 1 else c["d_wall"], sign_col)
    row += 1
    for f in range(floors):                          # floors of windows
        for i in range(w):
            ch = c["d_win"] if (i + f) % 2 else c["d_win2"]
            put(i, row, ch if 0 < i < w - 1 else c["d_wall"], win_col if 0 < i < w - 1 else wall_col)
        row += 1
        for i in range(w):
            put(i, row, c["d_band"], wall_col)
        row += 1
    for i in range(w):                               # the awning and the shopfront
        put(i, row, c["d_awning"], sign_col if 0 < i < w - 1 else wall_col)
    row += 1
    for i in range(w):
        mid = w // 2
        ch = c["d_door"] if i == mid else (c["d_shop"] if 0 < i < w - 1 else c["d_wall"])
        put(i, row, ch, WHITE if i == mid else (win_col if 0 < i < w - 1 else wall_col))
    return row + 1


def scene_detail(c, sprites=True):
    """One screenful of a real street: two continuous frontages facing each
    other across the road, their buildings sharing walls, an alley through
    one of them, a service yard behind, parking bays at the kerb and the
    traffic that goes with them."""
    W_, H_ = 40, 25
    g = [[c[f"grass{((x * 11) ^ (y * 5)) % 4}"] for x in range(W_)] for y in range(H_)]

    for y in range(12, 18):                          # the road
        for x in range(W_):
            g[y][x] = c["road"]
    for x in range(W_):
        g[12][x] = c["kerb_n"]; g[17][x] = c["kerb_s"]
        if (x % 4) < 2:
            g[14][x] = c["dash_h"]
    for x in range(W_):                              # pavement either side
        g[11][x] = c["walk"]; g[18][x] = c["walk"]
    for x in range(0, W_, 3):                        # parking bays against the north kerb
        g[13][x] = c["bay"]

    # the north frontage: shops sharing walls, an alley between two of them
    fronts = ((0, 6, CYAN, RED), (6, 5, YELLOW, PURPLE), (11, 7, WHITE, CYAN),
              (19, 6, CYAN, YELLOW), (25, 5, YELLOW, RED), (30, 4, WHITE, PURPLE),
              (34, 6, CYAN, CYAN))
    for x, w, win, sign in fronts:
        place_detail(g, c, x, 3, w, 1, BROWN, win, sign)
    for y in range(3, 11):                           # the alley, a gap in the frontage
        g[y][18] = c["alley"]
    for x in range(W_):                              # the service yard behind the shops
        for y in (0, 1, 2):
            g[y][x] = c["road"] if x % 7 else c["alley"]

    # the south frontage, set back, with its own pavement
    for x, w, win, sign in ((1, 7, WHITE, CYAN), (9, 6, CYAN, RED), (16, 8, YELLOW, PURPLE),
                            (25, 6, WHITE, YELLOW), (32, 7, CYAN, RED)):
        place_detail(g, c, x, 19, w, 1, BROWN, win, sign)

    for x in (8, 9, 24, 25):                         # crossings where people cross
        for y in range(12, 18):
            g[y][x] = c["crossing"]
    for x in (7, 10, 23, 26):
        g[13][x] = c["stopline"]

    spr = []
    if sprites:
        cars, peds = car_frames_mc(), ped_frames_mc()
        spr += [(cars[1], 48, 106, RED, False), (cars[3], 190, 128, CYAN, False),
                (cars[1], 262, 106, YELLOW, False)]       # moving, one lane each way
        spr += [(cars[0], 16, 100, PURPLE, False), (cars[0], 112, 100, WHITE, False),
                (cars[0], 232, 100, LGREEN, False), (cars[0], 308, 100, CYAN, False)]
        spr += [(peds[0], 60, 86, WHITE, False), (peds[1], 130, 88, ORANGE, False),
                (peds[0], 215, 148, CYAN, False), (peds[1], 300, 150, WHITE, False)]
    return g, spr


def main():
    out = sys.argv[1]
    zoom = int(sys.argv[sys.argv.index("--zoom") + 1]) if "--zoom" in sys.argv else 3
    global SHARED
    if "--dark" in sys.argv:
        SHARED = SHARED_DARK
        c = dark_chars()
        grid, spr = scene_detail(c, sprites="--no-sprites" not in sys.argv)
    elif "--detail" in sys.argv:
        c = detail_chars()
        grid, spr = scene_detail(c, sprites="--no-sprites" not in sys.argv)
    else:
        b = design_chars()
        c = ground_chars()
        grid, spr = scene(b, c, sprites="--no-sprites" not in sys.argv)
    w, h, rows = render(grid, spr, zoom)
    write_png(out, w, h, rows)
    chars = {tuple(ch.bits()) for line in grid for ch in line}
    print(f"{out}: 40x25 characters ({w}x{h} at {zoom}x), {len(chars)} different characters, "
          f"{len(spr)} sprites")


if __name__ == "__main__":
    main()
