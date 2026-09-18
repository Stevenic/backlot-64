#!/usr/bin/env python3
"""Baked lighting for stills: precomputed colour maps the engine streams.

A bitmap still's pixels are colour *codes* per cell; the colours those codes
mean live in screen RAM (two per cell), colour RAM (one per cell) and the
background register.  Relighting a still therefore never touches the 8 KB
bitmap: a lighting state is a new background byte plus 800 screen bytes
and 800 colour bytes for the 20 visible rows, 2 KB with padding, and the
engine applies it with two DMAs in the vertical blank (b64_cut_light,
LIGHT opcode).  This tool writes a file of states from a .still.

modes:
  dusk   --steps N   darken along a curve with a blue cast, state 0 = the
                     still as it is, state N-1 = night
  strobe             three states: as it is, a red wash, a blue wash, the
                     whole scene lit alike (the first, crude version)
  beacon --positions P --row R --radius D
                     1 + 2P states: as it is, then for each lamp position
                     (cell x = 2p+5, cell row R) a red and a blue wash that
                     falls off with distance from the lamp, so only the
                     surfaces near the light change.  The script picks the
                     state from the car's position.

usage: b64light.py <in.still> <out.bin> dusk --steps 32
       b64light.py <in.still> <out.bin> strobe
"""
import sys
sys.path.insert(0, __import__("os").path.dirname(__file__))
from b64palette import RGB  # noqa: E402

STATE = 2048


def nearest(rgb):
    r, g, b = rgb
    best, bd = 0, None
    for i, (pr, pg, pb) in enumerate(RGB):
        d = (pr - r) ** 2 + (pg - g) ** 2 + (pb - b) ** 2
        if bd is None or d < bd:
            best, bd = i, d
    return best


def remap_table(f):
    """A 16-entry table mapping each palette colour through f(rgb) -> nearest."""
    return [nearest(f(RGB[c])) for c in range(16)]


NIGHT = (24, 20, 70)                            # where the dark converges: a deep blue, not black


def dusk_tables(steps):
    """Each colour slides from itself toward NIGHT; the slide is slow at
    first and the last states hold near the end so the palette settles.
    With 16 colours a state changes when a colour crosses a boundary, so
    the ramp is a staircase; the steps come at different times for
    different colours, which reads as dusk."""
    tabs = []
    for k in range(steps):
        t = k / (steps - 1)
        a = 0.86 * (t ** 1.3)                   # amount of night; never all the way, or every colour collapses to one
        def f(rgb, a=a):
            return tuple(rgb[i] * (1 - a) + NIGHT[i] * a for i in range(3))
        tabs.append(remap_table(f))
    tabs[0] = list(range(16))                   # state 0 is exactly the still
    return tabs


def strobe_tables():
    """A police lamp lighting the scene: a red and a blue wash that lift the
    mid tones toward the lamp's colour and leave the darks alone."""
    ident = list(range(16))
    def wash(rgb, lamp):
        r, g, b = rgb
        lum = (r * 0.3 + g * 0.59 + b * 0.11) / 255
        w = 0.3 + 0.55 * lum                    # every surface catches the lamp, brighter ones more
        return tuple(rgb[i] * (1 - w) + lamp[i] * w for i in range(3))
    red = remap_table(lambda c: wash(c, (255, 40, 40)))
    blue = remap_table(lambda c: wash(c, (60, 80, 255)))
    return [ident, red, blue]


def apply_cells(still, tab_for_cell):
    """Per-cell remap: tab_for_cell(cx, cy) -> a 16-entry table.  The
    background colour is one register for the whole screen, so code 00
    pixels cannot be relit per cell; the still's own background stays."""
    bg = still[0]
    screen = still[1 + 8000:1 + 8000 + 1000]
    colour = still[1 + 9000:1 + 9000 + 1000]
    out = bytearray(STATE)
    out[0] = bg
    for i in range(800):
        tab = tab_for_cell(i % 40, i // 40)
        s = screen[i]
        out[1 + i] = (tab[s >> 4] << 4) | tab[s & 15]
        out[801 + i] = tab[colour[i] & 15]
    return bytes(out)


def beacon_states(still, positions, row, radius):
    import math
    ident = list(range(16))
    lamps = [(255, 40, 40), (60, 80, 255)]
    cache = {}
    def table(lamp, w):
        key = (lamp, round(w, 2))
        if key not in cache:
            cache[key] = remap_table(lambda c: tuple(c[i] * (1 - w) + lamp[i] * w for i in range(3)))
        return cache[key]
    states = [apply(still, ident)]
    for p in range(positions):
        lx = 2 * p + 5
        for lamp in lamps:
            def tab_for_cell(cx, cy, lx=lx, lamp=lamp):
                d = math.hypot(cx - lx, (cy - row) * 1.0)
                w = max(0.0, 1.0 - d / radius)
                w = 0.95 * (w ** 1.5)               # strong at the lamp, gone by the radius
                return ident if w < 0.08 else table(lamp, w)
            states.append(apply_cells(still, tab_for_cell))
    return states


def apply(still, tab):
    bg = still[0]
    screen = still[1 + 8000:1 + 8000 + 1000]
    colour = still[1 + 9000:1 + 9000 + 1000]
    out = bytearray(STATE)
    out[0] = tab[bg]
    for i in range(800):
        s = screen[i]
        out[1 + i] = (tab[s >> 4] << 4) | tab[s & 15]
        out[801 + i] = tab[colour[i] & 15]
    return bytes(out)


def preview(still, state, path):
    """Render the still under a lighting state to a PNG (for checking)."""
    import zlib, struct
    bitmap = still[1:8001]
    bg = state[0]; screen = state[1:801]; colour = state[801:1601]
    W, H = 320, 160
    rows = []
    for y in range(H):
        row = bytearray()
        for x in range(0, W, 2):
            cx, cy = x // 8, y // 8
            byte = bitmap[(cy * 40 + cx) * 8 + (y & 7)]
            code = (byte >> (6 - 2 * ((x % 8) // 2))) & 3
            s = screen[cy * 40 + cx]
            c = [bg, s >> 4, s & 15, colour[cy * 40 + cx] & 15][code]
            row += bytes(RGB[c]) * 2
        rows.append(b"\x00" + bytes(row))
    raw = b"".join(rows)
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def main():
    src, dst, mode = sys.argv[1:4]
    still = open(src, "rb").read()
    if mode == "dusk":
        steps = int(sys.argv[sys.argv.index("--steps") + 1]) if "--steps" in sys.argv else 32
        tabs = dusk_tables(steps)
    elif mode == "strobe":
        tabs = strobe_tables()
    elif mode == "beacon":
        arg = lambda k, d: int(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d
        states = beacon_states(still, arg("--positions", 20), arg("--row", 13), arg("--radius", 9))
        tabs = None
    else:
        raise SystemExit("mode: dusk | strobe | beacon")
    if tabs is not None:
        states = [apply(still, t) for t in tabs]
    blob = b"".join(states)
    open(dst, "wb").write(blob)
    if "--preview" in sys.argv:
        pre = sys.argv[sys.argv.index("--preview") + 1]
        for k in sorted(set([0, len(states) // 4, len(states) // 2, 3 * len(states) // 4, len(states) - 1])):
            preview(still, states[k], f"{pre}-{k:02d}.png")
    if tabs is not None:
        changed = [sum(1 for c in range(16) if t[c] != c) for t in tabs]
        print(f"  {dst}: {len(tabs)} states x {STATE} bytes; colours remapped per state: {changed}")
    else:
        diff = [sum(1 for i in range(1, 1601) if s[i] != states[0][i]) for s in states[1:4]]
        print(f"  {dst}: {len(states)} states x {STATE} bytes; cells changed in the first states: {diff}")


if __name__ == "__main__":
    main()
