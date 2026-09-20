#!/usr/bin/env python3
"""Encode any picture into characters the VIC-II can show, and report the cost.

Asked 2026-09-19: can a design-time tool take an image and turn it into a
charset?  It can, and this is it -- but the answer is a budget, not a yes.
A picture drawn freely needs a character per distinct cell, and the engine
has 192 scene codes.  Worse, a cell's colour is packed into its screen code
(tools/b64tileset.py, pack), so twelve characters may show any one colour.
This measures both, then fits the picture into what is left and shows what
that costs.

The colour rule that decides everything: in multicolour text mode a cell's
own colour is the low three bits of its colour nibble -- bit 3 only marks
the cell multicolour -- so the colour a cell adds is one of the first eight.
Of those only black and white are grey, which is why a grey picture puts its
greys in the three shared registers and gets one bright per cell.

    b64band.py measure <image.png> [--scale 0.25] [--preview out.png]
    b64band.py analyse <image.png> [--scale 0.25]   where the detail goes
    b64band.py encode  <image.png> [--scale 0.25] [--chars 96] [--iters 4]
                       [--preview out.png] [--tileset out.bin] [--strip out.strip]

encode clusters the picture's cells down to a legal charset, writes the
picture back as a preview, and can emit an engine tileset: the fitted cells
as characters, every distinct 4x4 block as a metatile, and the block ids as
a strip the world generator lays down (tools/b64world.py, district_image).
"""
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from b64palette import RGB  # noqa: E402
from b64png import read_png, write_png  # noqa: E402
from b64art import BLACK, WHITE, DGRAY, MGRAY, LGRAY, Char  # noqa: E402

SHARED = (BLACK, DGRAY, LGRAY)        # bg0, bg1, bg2: the whole screen's
OWN = (WHITE,)                        # all a multicolour cell may add: colours 0-7
PER_BUCKET = 12                       # codes a colour value has, below the font


def luma(rgb):
    r, g, b = rgb
    return (299 * r + 587 * g + 114 * b) // 1000


LUMA = [luma(RGB[c]) for c in range(16)]


def scaled(path, w, h, out):
    """sips, so this needs no image libraries (-c and -z are separate calls)."""
    subprocess.run(["sips", "-z", str(h), str(w), path, "--out", out],
                   check=True, capture_output=True)
    return read_png(out)


def cell_pixels(rows, cx, cy):
    """One 8x8 cell as 4x8 multicolour pixels: columns in pairs, averaged."""
    out = []
    for y in range(8):
        row = rows[cy * 8 + y]
        for x in range(4):
            p = 8 * cx + 2 * x
            a = luma(row[3 * p:3 * p + 3])
            b = luma(row[3 * p + 3:3 * p + 6])
            out.append((a + b) // 2)
    return out


def cell_pixels8(rows, cx, cy):
    """The same cell at full width: what a hires character would show, eight
    pixels across and two colours."""
    out = []
    for y in range(8):
        row = rows[cy * 8 + y]
        for x in range(8):
            p = 8 * cx + x
            out.append(luma(row[3 * p:3 * p + 3]))
    return out


def hires_error(px8, bg, ink):
    """A hires cell keeps the full 320 pixels and gives up two colours: the
    shared background where a bit is clear, its own colour where set."""
    lo, hi = LUMA[bg], LUMA[ink]
    return sum(min(abs(v - lo), abs(v - hi)) for v in px8) / len(px8)


def paint(px, colours):
    """The cell drawn with these four colours: the pattern and its error."""
    lum = [LUMA[c] for c in colours]
    vals, err = [], 0
    for v in px:
        k = min(range(len(lum)), key=lambda i: abs(v - lum[i]))
        vals.append(k)
        err += (v - lum[k]) ** 2
    return vals, err


def to_char(vals, own):
    ch = Char(True, own)
    for i, v in enumerate(vals):
        ch.put(i % 4, i // 4, v)
    return ch


def quantise(px, shared=SHARED, own=OWN):
    """The cell, with the one extra colour that costs it least, and what it
    would cost with no colour of its own at all -- a cell that can do
    without one is free of every colour budget."""
    best = min(((paint(px, list(shared) + [c]), c) for c in own), key=lambda t: t[0][1])
    (vals, err), colour = best
    flat, err3 = paint(px, list(shared))
    return vals, err, colour, flat, err3


def harvest(rows, w, h, shared=SHARED, own=OWN):
    """Every cell of the picture: its pixels and both quantisations."""
    out = []
    for cy in range(h // 8):
        for cx in range(w // 8):
            px = cell_pixels(rows, cx, cy)
            vals, err, colour, flat, err3 = quantise(px, shared, own)
            out.append(dict(px=px, px8=cell_pixels8(rows, cx, cy), vals=vals, err=err,
                            colour=colour, flat=flat, err3=err3, x=cx, y=cy))
    return out


def group(cells, slack=1.15):
    """Which cells need a colour of their own.  One that costs little more
    without it is put in the free pool, where it may take any code."""
    free, owned = [], {}
    for c in cells:
        if c["err3"] <= c["err"] * slack + 64:
            c["vals"], c["own"] = c["flat"], None
            free.append(c)
        else:
            c["own"] = c["colour"]
            owned.setdefault(c["colour"], []).append(c)
    return free, owned


def kmeans(cells, k, shared, own, iters=4):
    """Cluster cells onto k characters.  A cluster's character is drawn from
    its members' mean, so the charset is chosen by the picture rather than by
    which cells happened to be commonest.

    After Stuart Lloyd, least-squares quantisation in PCM (Bell Labs 1957,
    published 1982).  Changed: the cluster count is not free but set by the
    chip -- twelve characters a colour value for the ones that show a
    colour, the rest sharing the codes that are left (docs/VIEWS.md)."""
    if not cells:
        return []
    k = max(1, min(k, len(cells)))
    seen, seeds = set(), []
    for c in sorted(cells, key=lambda c: -sum(c["px"])):       # spread the seeds by weight
        key = tuple(c["vals"])
        if key not in seen:
            seen.add(key)
            seeds.append(list(c["px"]))
        if len(seeds) == k:
            break
    while len(seeds) < k:
        seeds.append(list(cells[len(seeds) % len(cells)]["px"]))
    colours = list(shared) + ([own] if own is not None else [])
    reps = [paint(s, colours)[0] for s in seeds]
    for _ in range(iters):
        sums = [[0] * 32 for _ in range(k)]
        n = [0] * k
        for c in cells:
            lum = [[LUMA[colours[v]] for v in r] for r in reps]
            break
        lum = [[LUMA[colours[v]] for v in r] for r in reps]
        for c in cells:
            px = c["px"]
            j = min(range(k), key=lambda i: sum((a - b) ** 2 for a, b in zip(px, lum[i])))
            c["cluster"] = j
            n[j] += 1
            for i in range(32):
                sums[j][i] += px[i]
        for j in range(k):
            if n[j]:
                reps[j] = paint([s // n[j] for s in sums[j]], colours)[0]
    return reps


def fit(cells, shared=SHARED, own=OWN, codes=96, iters=4, per_bucket=PER_BUCKET):
    """Fit the picture into the codes the engine has.  Characters that show
    a colour are capped at twelve a colour -- raise per_bucket to ask what a
    colour table per cell would buy, which is the fill cost of a second byte
    a cell (docs/PREPARE.md, tilesets)."""
    free, owned = group(cells)
    used = 0
    n = max(1, len(cells))
    for colour, members in owned.items():
        share = max(1, codes * len(members) // n)
        k = min(per_bucket, len(members), share)
        reps = kmeans(members, k, shared, colour, iters)
        for c in members:
            c["bits"] = reps[c["cluster"]]
        used += k
    reps = kmeans(free, max(1, codes - used), shared, None, iters)
    for c in free:
        c["bits"] = reps[c["cluster"]]
    used += len(reps)
    damage = 0
    for c in cells:
        lum = [LUMA[(list(shared) + ([c["own"]] if c["own"] is not None else []))[v]]
               for v in c["bits"]]
        damage += sum(abs(a - b) for a, b in zip(c["px"], lum))
    return used, damage / (len(cells) * 32)


def render(cells, w, h, shared, zoom=2):
    """What the chip would show."""
    out = [bytearray(b"\x00\x00\x00" * w * zoom) for _ in range(h * zoom)]
    for c in cells:
        colours = list(shared) + ([c["own"]] if c["own"] is not None else [BLACK])
        for i, v in enumerate(c["bits"]):
            r, g, b = RGB[colours[v]]
            x, y = c["x"] * 8 + (i % 4) * 2, c["y"] * 8 + i // 4
            for zy in range(zoom):
                row = out[y * zoom + zy]
                for zx in range(2 * zoom):
                    p = x * zoom + zx
                    row[3 * p:3 * p + 3] = bytes((r, g, b))
    return w * zoom, h * zoom, out


def tileset_from(cells, cw, ch, name, shared, props=None):
    """The fitted picture as an engine tileset: its cells are the charset,
    its distinct 4x4 blocks the metatiles, and the block ids a strip the
    world lays down.  The packer does the colour arithmetic and refuses the
    picture if a colour wants more than twelve characters.

    A picture carries no idea of what a car may drive on, so `props` names
    what each metatile row of the picture is -- road, pavement, solid --
    and the strip becomes a map the engine can play on rather than a
    backdrop.  A block that appears in rows of two different kinds is a
    different metatile in each: the charset is shared, the properties are
    not."""
    from b64tileset import Tileset, P_SOLID, P_SIDEWALK, P_ROAD_HV, BUILDING
    kinds = {"road": (P_ROAD_HV, 0), "walk": (P_SIDEWALK, 0),
             "solid": (P_SOLID, BUILDING), "": (0, 0)}
    ts = Tileset(name, shared)
    at = {(c["x"], c["y"]): c for c in cells}
    blocks, strip = {}, bytearray()
    for by in range(ch // 4):
        kind = (props or {}).get(by, "")
        for bx in range(cw // 4):
            chars = []
            for j in range(4):
                for i in range(4):
                    c = at[(bx * 4 + i, by * 4 + j)]
                    chars.append(to_char(c["bits"], c["own"] if c["own"] is not None else BLACK))
            key = (kind,) + tuple((tuple(k.bits()), k.colour) for k in chars)
            if key not in blocks:
                if len(blocks) >= 256:
                    raise SystemExit(f"{name}: more than 256 distinct blocks")
                p, height = kinds[kind]
                blocks[key] = ts.add_chars(f"mt{len(blocks)}", chars, p, height)
            strip.append(blocks[key])
    return ts, bytes(strip), cw // 4, ch // 4


def stage_error(cells, key):
    """Mean absolute luma error against the scaled picture, 0-255."""
    total = 0
    for c in cells:
        colours = list(SHARED) + ([c["own"] if c.get("own") is not None else BLACK])
        lum = [LUMA[colours[v]] for v in c[key]]
        total += sum(abs(a - b) for a, b in zip(c["px"], lum))
    return total / (len(cells) * 32)


def pairing_error(rows, cells, w):
    """What the multicolour pairing alone costs: every cell's four columns
    are two screen pixels wide, so the picture loses half its width before
    a single colour is chosen."""
    total = 0
    for c in cells:
        for y in range(8):
            row = rows[c["y"] * 8 + y]
            for x in range(4):
                p = 8 * c["x"] + 2 * x
                a = luma(row[3 * p:3 * p + 3])
                b = luma(row[3 * p + 3:3 * p + 6])
                m = (a + b) // 2
                total += abs(a - m) + abs(b - m)
    return total / (len(cells) * 64)


GREYS = (BLACK, DGRAY, MGRAY, LGRAY, WHITE)


def best_palette(band_rows, rows):
    """The three shared registers and the cell colour that suit this band
    best, searched over the greys.  A raster split can set them per band."""
    best = None
    for a in range(len(GREYS)):
        for b in range(a + 1, len(GREYS)):
            for c in range(b + 1, len(GREYS)):
                shared = (GREYS[a], GREYS[b], GREYS[c])
                for own in (WHITE, BLACK):
                    if own in shared:
                        continue
                    err = 0
                    for cell in band_rows:
                        err += paint(cell["px"], list(shared) + [own])[1]
                    if best is None or err < best[0]:
                        best = (err, shared, own)
    return best[1], best[2]


def split_gain(cells, h, band_cells=4):
    """What per-band registers would buy, with the charset still fitted."""
    total = 0
    for by in range(h // (8 * band_cells)):
        band = [c for c in cells if by * band_cells <= c["y"] < (by + 1) * band_cells]
        shared, own = best_palette(band, None)
        for c in band:
            c["vals"], c["err"] = paint(c["px"], list(shared) + [own])
            c["flat"], c["err3"] = paint(c["px"], list(shared))
            c["colour"] = own
            c.pop("bits", None)
        used, damage = fit(band, shared=shared, own=(own,), codes=96, iters=4)
        total += damage * len(band)
    return total / len(cells)


def analyse(rows, cells, w, h):
    """Where the detail goes, stage by stage and band by band, and what
    relaxing each limit would buy."""
    print("  loss by stage, mean absolute luma of 255 a pixel:")
    print(f"    multicolour pairing (320 -> 160 across)   {pairing_error(rows, cells, w):5.1f}")
    for c in cells:                                   # the free quantisation: four colours a cell
        c["own"] = c["colour"]
    print(f"    four colours a cell, charset unlimited    {stage_error(cells, 'vals'):5.1f}")
    for budget, bucket, label in ((96, 12, "96 characters, 12 a colour (what ships)"),
                                  (192, 12, "192 characters, 12 a colour"),
                                  (192, 192, "192 characters, colour RAM per cell"),
                                  (2048, 2048, "no charset limit at all")):
        for c in cells:
            c.pop("bits", None)
        used, damage = fit(cells, codes=budget, per_bucket=bucket, iters=4)
        print(f"    {label:41s} {damage:5.1f}   ({used} used)")
    for c in cells:                                   # back to what ships, for the band report
        c.pop("bits", None)
    fit(cells, codes=96, per_bucket=12, iters=4)
    mixed = 0
    hires_cells = 0
    for c in cells:
        mc_err = sum(abs(a - LUMA[(list(SHARED) + [c["colour"]])[v]])
                     for a, v in zip(c["px"], c["vals"])) / 32
        hi_err = min(hires_error(c["px8"], SHARED[0], WHITE),
                     hires_error(c["px8"], SHARED[2], WHITE))
        if hi_err < mc_err:
            hires_cells += 1
        mixed += min(mc_err, hi_err)
    print(f"    hires where it beats multicolour          {mixed / len(cells):5.1f}"
          f"   ({hires_cells} of {len(cells)} cells want hires)")
    for c in cells:
        c.pop("bits", None)
    print(f"    a raster split a band, own registers each  "
          f"{split_gain([dict(c) for c in cells], h):5.1f}")
    for c in cells:                                   # restore what ships
        c["own"] = c["colour"]
        c.pop("bits", None)
    fit(cells, codes=96, per_bucket=12, iters=4)
    print("  loss by band (four cell rows each, top to bottom):")
    for by in range(h // 32):
        band = [c for c in cells if by * 4 <= c["y"] < by * 4 + 4]
        print(f"    rows {by * 4:2d}-{by * 4 + 3:2d}  {stage_error(band, 'bits'):5.1f}")


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)

    def opt(name, default=None, cast=str):
        return cast(sys.argv[sys.argv.index(name) + 1]) if name in sys.argv else default

    cmd, src = sys.argv[1], sys.argv[2]
    scale = opt("--scale", 0.25, float)
    codes = opt("--chars", 96, int)
    iters = opt("--iters", 4, int)
    w0, h0, _ = read_png(src)
    w, h = int(w0 * scale) // 8 * 8, int(h0 * scale) // 8 * 8
    tmp = os.path.join(os.environ.get("TMPDIR", "/tmp"), "b64band-scaled.png")
    _, _, rows = scaled(src, w, h, tmp)
    cells = harvest(rows[:h], w, h)
    n = len(cells)
    print(f"{src} at {w}x{h} ({w // 8}x{h // 8} cells, {n} cells)")

    if cmd == "analyse":
        analyse(rows[:h], cells, w, h)
        return

    if cmd == "measure":
        distinct = {(tuple(c["vals"]), c["colour"]) for c in cells}
        show = {}
        for c in cells:
            if 3 in c["vals"]:
                show.setdefault(c["colour"], set()).add(tuple(c["vals"]))
        print(f"  drawn freely it wants {len(distinct)} characters, and the engine has 192")
        for col, s in show.items():
            print(f"  {len(s)} of them show colour {col}, and a colour has {PER_BUCKET} codes")
        print(f"  mean error {sum(c['err'] for c in cells) / (n * 32):.0f} luma^2 a pixel")
        return

    if cmd != "encode":
        raise SystemExit(__doc__)
    used, damage = fit(cells, codes=codes, iters=iters)
    print(f"  fitted into {used} characters, mean error {damage:.1f} luma of 255 a pixel")
    if "--preview" in sys.argv:
        out = opt("--preview")
        pw, ph, prows = render(cells, w, h, SHARED)
        write_png(out, pw, ph, prows)
        print(f"  wrote {out} ({pw}x{ph}, 2x)")
    if "--tileset" in sys.argv:
        name = os.path.splitext(os.path.basename(opt("--tileset")))[0]
        props = {}
        for kind in ("road", "walk", "solid"):           # --road 4 --walk 3,5 --solid 0,1,2,6,7
            for r in (opt(f"--{kind}", "") or "").split(","):
                if r.strip():
                    props[int(r)] = kind
        ts, strip, sw, sh = tileset_from(cells, w // 8, h // 8, name, SHARED, props)
        open(opt("--tileset"), "wb").write(ts.pack())
        print(f"  tileset {opt('--tileset')}: {len(ts.order)} characters, "
              f"{len(ts.metatiles)} metatiles, strip {sw}x{sh}")
        if "--strip" in sys.argv:
            open(opt("--strip"), "wb").write(struct.pack("<BB", sw, sh) + strip)
            print(f"  strip {opt('--strip')}: {sw}x{sh} metatiles")


if __name__ == "__main__":
    main()
