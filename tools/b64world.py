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
    return b"".join(rows)


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
