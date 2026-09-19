#!/usr/bin/env python3
"""A top-down vehicle at N headings, as multicolour sprites.

The shape is drawn once in the vehicle's own coordinates (u forward, v to
its right, in screen pixels) and sampled at every heading: each multicolour
pixel (2 x 1 screen pixels) takes the colour most of its four samples show,
so the car keeps its proportions at every angle instead of the 90-degree
turns of a hand-drawn frame.  Heading k of N points (cos, sin) of k/N of a
turn, 0 = east, a quarter = south (screen y runs down), which is the angle
the physics module keeps (docs/PHYSICS.md).

Colours: '2' the sprite's own colour (the body), '1' multicolour 0
(windows, tyres: black in the examples), '3' multicolour 1 (lamps: white).

usage: b64rot.py car|boat <out.spr> [--headings 16] [--show]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from b64art import encode_sprite                 # noqa: E402

W, H = 12, 21                                    # multicolour pixels
CX, CY = 12.0, 10.5                              # the sprite's centre in screen pixels


def car(u, v):
    """The colour at (u, v): a sedan 19 pixels long and 10 wide."""
    au, av = abs(u), abs(v)
    if au > 9.5 or av > 5.0:
        return "."
    if au > 8.3 and av > 3.6:                    # rounded corners
        return "."
    if u > 8.0 and 1.8 <= av <= 4.2:
        return "3"                               # headlamps
    if 1.5 <= u <= 4.6 and av <= 3.8:
        return "1"                               # windscreen
    if -7.2 <= u <= -5.4 and av <= 3.8:
        return "1"                               # rear window
    if av >= 4.3 and (2.5 <= au <= 6.5):
        return "1"                               # tyres showing at the sides
    return "2"


def boat(u, v):
    """The colour at (u, v): a speedboat 20 pixels long and 9 wide, a pointed
    bow, a flat stern with the motor behind it."""
    au, av = abs(u), abs(v)
    if u < -10.5 or u > 10.0:
        return "."
    if u < -9.0:                                 # the outboard motor
        return "1" if av <= 1.2 else "."
    half = 4.5 if u <= 3.0 else 4.5 * (10.0 - u) / 7.0
    if av > half:
        return "."
    if 1.8 <= u <= 4.2 and av <= 3.4:
        return "3"                               # the windscreen
    if -5.0 <= u < 1.8 and av <= 2.6:
        return "1"                               # the cockpit
    return "2"


SHAPES = {"car": car, "boat": boat}


def frames(shape, headings):
    out = []
    for k in range(headings):
        a = 2 * math.pi * k / headings
        c, s = math.cos(a), math.sin(a)
        rows = []
        for j in range(H):
            row = ""
            for i in range(W):
                votes = {}
                for ox in (0.5, 1.5):
                    for oy in (0.25, 0.75):
                        x = 2 * i + ox - CX
                        y = j + oy - CY
                        u = x * c + y * s                # into the vehicle's frame
                        v = -x * s + y * c
                        col = shape(u, v)
                        votes[col] = votes.get(col, 0) + 1
                empty = votes.pop(".", 0)
                if empty >= 3 or not votes:
                    row += "."
                else:
                    row += max(sorted(votes), key=lambda col: votes[col])
            rows.append(row)
        out.append(rows)
    return out


def main():
    name, out = sys.argv[1], sys.argv[2]
    n = int(sys.argv[sys.argv.index("--headings") + 1]) if "--headings" in sys.argv else 16
    data = b"".join(encode_sprite(f, True) for f in frames(SHAPES[name], n))
    with open(out, "wb") as f:
        f.write(data)
    if "--show" in sys.argv:
        for k, f in enumerate(frames(SHAPES[name], n)):
            print(k)
            print("\n".join(f))


if __name__ == "__main__":
    main()
