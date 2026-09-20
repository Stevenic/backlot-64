#!/usr/bin/env python3
"""backlot-64 world generator.

Writes a 2048x2048 metatile map (4 MB, row-major, address = (y << 11) | x)
and a 64x64 region table (one tileset slot per 32x32-metatile sector).

This is the first-cut procedural layout: one city on the east coast, an
ocean, beach, highways, and grassland.  It exists so the scroller has
something big to drive around.  The real Coquina layout replaces it in
Priors-64's own world tool.

usage: b64world.py <world-name> <out.map> <out.reg>
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from b64tileset import TILESETS  # noqa: E402

W = H = 2048


def bellamar_test(mt):
    """mt: name -> metatile id."""
    grass, water, sand, walk = mt["grass"], mt["water"], mt["sand"], mt["sidewalk"]
    road_h, road_v, cross = mt["road_h"], mt["road_v"], mt["cross"]
    roofs = [mt["roof_cyan"], mt["roof_purple"], mt["roof_yellow"], mt["roof_white"], mt["roof_red"], mt["roof_green"]]
    roofi = [mt["roofi_cyan"], mt["roofi_purple"], mt["roofi_yellow"], mt["roofi_white"], mt["roofi_red"], mt["roofi_green"]]
    wall, shadow, door = mt["wall"], mt["sidewalk_shadow"], mt["door"]
    palm_walk, palm_sand, shore = mt["palm_walk"], mt["palm_sand"], mt["shore_s"]
    marsh = mt["marsh"]

    CITY_X0, CITY_X1 = 1200, 1696      # city grid, multiples of 8
    CITY_Y0, CITY_Y1 = 608, 1408
    BEACH_X0, BEACH_X1 = 1696, 1704
    OCEAN_X0 = 1704
    MARSH_Y0, MARSH_Y1, MARSH_X1 = 1040, 1088, 1712    # the sand and the first of the ocean, south of the beach
    HWY_X, HWY_Y = 1024, 1024

    rows = []
    for y in range(H):
        row = bytearray([grass]) * W
        # ocean and beach on the east
        row[BEACH_X0:BEACH_X1] = bytes([sand]) * (BEACH_X1 - BEACH_X0)
        row[OCEAN_X0:W] = bytes([water]) * (W - OCEAN_X0)
        if MARSH_Y0 <= y < MARSH_Y1:
            row[BEACH_X0:MARSH_X1] = bytes([marsh]) * (MARSH_X1 - BEACH_X0)
        elif y % 6 == 0:
            for x in range(BEACH_X0 + 2, BEACH_X1, 4):
                row[x] = palm_sand
        # highways across the grassland
        if y == HWY_Y:
            row[0:BEACH_X0] = bytes([road_h]) * BEACH_X0
        # city grid
        if CITY_Y0 <= y < CITY_Y1:
            ry = (y - CITY_Y0) % 8
            for x in range(CITY_X0, CITY_X1):
                rx = (x - CITY_X0) % 8
                bx, by = (x - CITY_X0) // 8, (y - CITY_Y0) // 8
                colour = (bx * 7 + by * 3) % 6
                if ry == 0 and rx == 0:
                    v = cross
                elif ry == 0:
                    v = road_h
                elif rx == 0:
                    v = road_v
                elif ry in (1, 7) or rx in (1, 7):
                    v = walk
                    if ry == 1 and rx == 4 and (bx + by) % 3 == 0:
                        v = palm_walk
                    if ry == 5 and rx == 7:
                        v = shadow
                elif 2 <= ry <= 4 and 2 <= rx <= 6:
                    v = roofs[colour] if (ry == 2 or rx == 2) else roofi[colour]
                elif ry == 5 and 2 <= rx <= 6:
                    v = door if rx == 4 else wall
                else:
                    v = walk
                row[x] = v
        # north-south highway through everything except the city
        if not (CITY_Y0 <= y < CITY_Y1):
            row[HWY_X] = cross if y == HWY_Y else road_v
        rows.append(bytes(row))
    # the flat-roof district, in its own tileset's metatiles (docs/VIEWS.md)
    rows = district_flat(rows, TILESETS["bellamar_flat"]().names)
    # the band district, in bellamar_band's (docs/VIEWS.md, the band city)
    rows = district_band(rows, TILESETS["bellamar_band"]().names)
    # the encoded district: the reference image itself, as tools/b64band.py
    # fitted it into a charset (docs/VIEWS.md, the band city)
    rows = district_image(rows, os.path.join(HERE, "..", "build", "cityenc.strip"))
    return b"".join(rows)


def district_flat(rows, mt):
    """The flat-roof district (docs/VIEWS.md): pure top-down roofs whose
    shadow, thrown south-east, is as long as the building is tall -- one
    metatile of shadow for every few storeys.  Streets on the same
    8-metatile grid as the city, pavement round each block, buildings of
    three heights on grass plots.

    Drawn with bellamar_flat's own metatiles; only this district uses it.
    """
    walk, grass, shadow = mt["sidewalk"], mt["grass"], mt["shadow"]
    road_h, road_v, cross = mt["road_h"], mt["road_v"], mt["cross"]
    X0, X1, Y0, Y1 = 800, 1056, 900, 1060           # multiples of 8

    def at(x, y, v):
        if X0 <= x < X1 and Y0 <= y < Y1:
            row = bytearray(rows[y])
            row[x] = v
            rows[y] = bytes(row)

    def get(x, y):
        return rows[y][x] if X0 <= x < X1 and Y0 <= y < Y1 else 0

    for y in range(Y0, Y1):                         # the streets and the plots
        row = bytearray(rows[y])
        ry = (y - Y0) % 8
        for x in range(X0, X1):
            rx = (x - X0) % 8
            if ry == 0 and rx == 0:
                v = cross
            elif ry == 0:
                v = road_h
            elif rx == 0:
                v = road_v
            elif ry == 1 or rx == 1 or ry == 7 or rx == 7:
                v = walk
            else:
                v = grass
            row[x] = v
        rows[y] = bytes(row)

    for by in range((Y1 - Y0) // 8):                # one building a block
        for bx in range((X1 - X0) // 8):
            x, y = X0 + bx * 8 + 2, Y0 + by * 8 + 2
            storeys = (3, 8, 16, 6, 12)[(bx * 3 + by * 5) % 5]
            reach = 1 if storeys <= 4 else (2 if storeys <= 9 else 3)
            w, h = (4, 3) if storeys <= 8 else (3, 3)
            for k in range(1, reach + 1):           # the shadow, offset south-east
                for j in range(h):
                    for i in range(w):
                        at(x + i + k, y + j + k, shadow)
            for j in range(h):                      # the roof, edged where it ends
                north = j == 0
                south = j == h - 1
                for i in range(w):
                    west, east = i == 0, i == w - 1
                    name = ("roof_" + ("n" if north else ("s" if south else "")) +
                            ("w" if west else ("e" if east else "")))
                    at(x + i, y + j, mt[name if name != "roof_" else "roof_mid"])
            if storeys >= 6:
                at(x + w - 1, y, mt["roof_ac"])
            if storeys >= 12:
                at(x, y + 1, mt["roof_vent"])
    return rows


def district_band(rows, mt):
    """The band district: the street as the reference image draws it.

    A period is ten metatile rows -- the far roofs, three rows of facade,
    the far pavement, two rows of road, the near pavement, and the near
    roofs -- repeated down the district, with the blocks broken by alleys
    every eight metatiles and a crossing every twenty-four.  The camera
    sits on the road, so the screen holds shopfronts above and roofs below,
    which is what the reference shows (images/city-mono.png).

    Drawn with bellamar_band's own metatiles; only this district uses it.
    """
    X0, X1, Y0, Y1 = 1200, 1456, 1200, 1440         # multiples of 8
    PERIOD = 7                                      # 224 pixels: a screen holds the lot

    for y in range(Y0, Y1):
        row = bytearray(rows[y])
        ry = (y - Y0) % PERIOD
        for x in range(X0, X1):
            rx = (x - X0) % 8
            alley = rx == 7                         # the break between blocks
            zebra = (x - X0) % 24 == 12
            if ry == 0:                             # the far roofs and the cornice
                v = mt["fac_gap"] if alley else mt["fac_roof"]
            elif ry == 1:                           # two storeys, the awning, the shopfront
                v = mt["fac_gap"] if alley else mt["fac_shop"]
            elif ry == 2:
                v = mt["walk_s"]
            elif ry == 3:
                v = mt["cross_n"] if zebra else mt["road_n"]
            elif ry == 4:
                v = mt["cross_s"] if zebra else mt["road_s"]
            elif ry == 5:                           # the near pavement and the parapet
                v = mt["walk_n"] if alley else mt["walk_roof"]
            else:                                   # the roofs, with their plant
                if alley:
                    v = mt["alley"]
                elif rx == 0:
                    v = mt["roof_w"]
                elif rx == 6:
                    v = mt["roof_e"]
                else:
                    v = (mt["roof_ac"], mt["roof_mid"], mt["roof_tank"],
                         mt["roof_mid"], mt["roof_stair"], mt["roof_mid"]
                         )[((x - X0) // 2 + (y - Y0) // PERIOD) % 6]
            row[x] = v
        rows[y] = bytes(row)
    return rows


def district_image(rows, strip_path, X0=1500, Y0=1200, X1=1756, Y1=1440):
    """The encoded district: an image that tools/b64band.py turned into a
    tileset, laid down repeatedly.  The strip is the picture's own metatile
    ids, so the district is the picture -- seams included, since nothing
    made the picture tile."""
    if not os.path.exists(strip_path):
        return rows                                 # built on the next pass
    blob = open(strip_path, "rb").read()
    sw, sh, ids = blob[0], blob[1], blob[2:]
    for y in range(Y0, Y1):
        row = bytearray(rows[y])
        for x in range(X0, X1):
            row[x] = ids[((y - Y0) % sh) * sw + ((x - X0) % sw)]
        rows[y] = bytes(row)
    return rows


WORLDS = {"bellamar_test": ("bellamar_day", bellamar_test)}


def main():
    name, out_map, out_reg = sys.argv[1], sys.argv[2], sys.argv[3]
    tileset_name, gen = WORLDS[name]
    ts = TILESETS[tileset_name]()
    data = gen(ts.names)
    assert len(data) == W * H
    with open(out_map, "wb") as f:
        f.write(data)
    with open(out_reg, "wb") as f:
        f.write(bytes(64 * 64))          # every sector uses tileset slot 0
    print(f"world {name}: {W}x{H} metatiles, tileset {tileset_name}")


if __name__ == "__main__":
    main()
