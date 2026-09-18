#!/usr/bin/env python3
"""backlot-64 palette report: every colour a screen can show, given its three
shared colours, as solids and as luminance-safe dithers.

For each shared trio it lists the solids (3 shared + 8 cell colours), the
blends that pass the dither rule from docs/ART.md, the mixed RGB of each
blend, and how many are visually distinct.  Writes a swatch PNG and a
markdown table per trio, and a union count across all trios.

usage: b64palette.py <out-dir> [name=bg0,bg1,bg2 ...]
       with no trios given, reports the Priors-64 regions.
"""
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from b64tileset import LUMA, COLOUR_NAMES, DITHER_MAX_STEP  # noqa: E402

# Pepto's measured PAL palette
RGB = [
    (0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x68, 0x37, 0x2B), (0x70, 0xA4, 0xB2),
    (0x6F, 0x3D, 0x86), (0x58, 0x8D, 0x43), (0x35, 0x28, 0x79), (0xB8, 0xC7, 0x6F),
    (0x6F, 0x4F, 0x25), (0x43, 0x39, 0x00), (0x9A, 0x67, 0x59), (0x44, 0x44, 0x44),
    (0x6C, 0x6C, 0x6C), (0x9A, 0xD2, 0x84), (0x6C, 0x5E, 0xB5), (0x95, 0x95, 0x95),
]
NAME_TO_ID = {n: i for i, n in enumerate(COLOUR_NAMES)}
CELL_COLOURS = list(range(8))
DISTINCT = 28          # euclidean RGB distance below which two colours count as the same
STEP = DITHER_MAX_STEP # max luminance gap for a blend to count


def mix(a, b):
    return tuple((RGB[a][i] + RGB[b][i]) // 2 for i in range(3))


def dist(p, q):
    return sum((p[i] - q[i]) ** 2 for i in range(3)) ** 0.5


def screen_palette(trio):
    """All colours one screen can show with these shared colours.
    Returns list of (label, rgb, kind)."""
    avail = list(dict.fromkeys(list(trio) + CELL_COLOURS))
    out = [(COLOUR_NAMES[c], RGB[c], "solid") for c in avail]
    # a dither is only possible inside a cell, which has the 3 shared + 1 cell colour
    seen = set()
    for cell in CELL_COLOURS:
        four = list(dict.fromkeys(list(trio) + [cell]))
        for i in range(len(four)):
            for j in range(i + 1, len(four)):
                a, b = four[i], four[j]
                key = (min(a, b), max(a, b))
                if key in seen:
                    continue
                seen.add(key)
                if abs(LUMA[a] - LUMA[b]) > STEP:
                    continue
                out.append((f"{COLOUR_NAMES[a]}+{COLOUR_NAMES[b]}", mix(a, b), "blend"))
    return out


def distinct(colours):
    kept = []
    for label, rgb, kind in colours:
        if all(dist(rgb, k[1]) >= DISTINCT for k in kept):
            kept.append((label, rgb, kind))
    return kept


def write_png(path, rows):
    h, w = len(rows), len(rows[0])
    raw = b"".join(b"\x00" + bytes(v for px in row for v in px) for row in rows)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def swatch(path, colours, cols=8, size=40):
    rows = (len(colours) + cols - 1) // cols
    img = [[(20, 20, 20)] * (cols * size) for _ in range(rows * size)]
    for n, (label, rgb, kind) in enumerate(colours):
        cx, cy = (n % cols) * size, (n // cols) * size
        for y in range(cy + 2, cy + size - 2):
            for x in range(cx + 2, cx + size - 2):
                if kind == "blend" and (x + y) & 1:
                    # show the actual dither pattern in the bottom half
                    if y > cy + size // 2:
                        a, b = label.split("+")
                        img[y][x] = RGB[NAME_TO_ID[b]]
                        continue
                if kind == "blend" and y > cy + size // 2:
                    a, b = label.split("+")
                    img[y][x] = RGB[NAME_TO_ID[a]]
                else:
                    img[y][x] = rgb
    write_png(path, img)


def report(outdir, name, trio):
    pal = screen_palette(trio)
    uniq = distinct(pal)
    solids = [c for c in pal if c[2] == "solid"]
    blends = [c for c in pal if c[2] == "blend"]
    swatch(os.path.join(outdir, f"palette-{name}.png"), uniq)
    with open(os.path.join(outdir, f"palette-{name}.md"), "w") as f:
        f.write(f"# Palette: {name}\n\nShared: {', '.join(COLOUR_NAMES[c] for c in trio)}\n\n")
        f.write(f"{len(solids)} solids, {len(blends)} luminance-safe blends, {len(uniq)} visually distinct.\n\n")
        f.write("| Colour | RGB | Kind |\n|---|---|---|\n")
        for label, rgb, kind in uniq:
            f.write(f"| {label} | #{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X} | {kind} |\n")
    print(f"{name:<14} shared {', '.join(COLOUR_NAMES[c] for c in trio):<28} "
          f"solids {len(solids):>2}  blends {len(blends):>2}  distinct {len(uniq):>2}")
    return uniq


# Priors-64: stable core (dgray/lgray by day, black/dgray by night) plus a
# regional accent, and full-trio interiors.
PRIORS64_REGIONS = {
    "bellamar-day": ("dgray", "lgray", "white"),
    "bellamar-night": ("black", "dgray", "pink"),
    "keys-day": ("dgray", "lgray", "lblue"),
    "keys-night": ("black", "dgray", "blue"),
    "reedwater-day": ("dgray", "lgray", "brown"),
    "reedwater-night": ("black", "dgray", "blue"),
    "port-day": ("dgray", "lgray", "orange"),
    "port-night": ("black", "dgray", "red"),
    "canebrook-day": ("dgray", "lgray", "green"),
    "canebrook-night": ("black", "dgray", "mgray"),
    "kestrel-day": ("dgray", "lgray", "lgreen"),
    "kestrel-night": ("black", "dgray", "mgray"),
    "in-club": ("black", "purple", "pink"),
    "in-shop": ("dgray", "mgray", "lgray"),
    "in-safehouse": ("brown", "orange", "lgray"),
    "in-station": ("lgray", "white", "cyan"),
    "in-warehouse": ("dgray", "brown", "orange"),
    "in-trailer": ("brown", "green", "lgray"),
}


def main():
    global DISTINCT, STEP
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    for a in sys.argv[1:]:
        if a.startswith("--step="):
            STEP = int(a[7:])
        if a.startswith("--distinct="):
            DISTINCT = int(a[11:])
    outdir = args[0]
    os.makedirs(outdir, exist_ok=True)
    trios = {}
    for arg in args[1:]:
        name, cols = arg.split("=")
        trios[name] = tuple(cols.split(","))
    if not trios:
        trios = PRIORS64_REGIONS
    union = []
    for name, names in trios.items():
        trio = tuple(NAME_TO_ID[n] for n in names)
        union += report(outdir, name, trio)
    u = distinct(union)
    swatch(os.path.join(outdir, "palette-union.png"), u)
    print(f"{'union':<14} {'':<28} distinct across all: {len(u)}")


if __name__ == "__main__":
    main()
