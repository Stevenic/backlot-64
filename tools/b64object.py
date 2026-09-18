#!/usr/bin/env python3
"""backlot-64 object packer: one master, two forms that match pixel for pixel.

    b64object.py <in.png> <out.b64o> <gw> <gh> --colours=mc0,ind,mc1 [--key=black,dgray]
                 [--floor=dgray | --still=<still.bin> --at=cx,cy] [--preview=out.png]
                 [--shadow] [--wheels=auto | x,y,rx,ry,...] [--wheel-frames=4] [--patch-still=out]
                 [--lights=dx,dy,radius,lamp:colour/frames,...;...]

--key lists the background colours that become transparent where they touch
the image edge.  --shadow paints a checkerboard black ellipse under the body:
it reads as a half-brightness shade and is identical in both forms.
--wheels finds (or takes) the wheel discs and generates frames with spokes at
four angles for every sprite a wheel touches; the animation section follows
the block data: nframes, nsprites, sprite indices, then frames.

The master is quantised ONCE under the sprite rule (three colours plus
transparent), then both the sprite grid and the bitmap block are cut from
it, so a sprite actor parked as a block is the same picture.

Transparent pixels in the block need something behind them.  --floor gives
them one flat colour; --still/--at composites the object over the still's
own pixels at the cell where it will be parked, which is seamless.

File layout (all offsets fixed so the engine needs no parsing):
    +0   gw, gh, cw, ch, mc0, ind, mc1, floor
    +8   row spans: ch pairs of (first visible cell, last visible cell + 1), 32 bytes reserved
    +40  sprite frames: gw*gh*64
    then bitmap rows ch*(cw*8), screen cw*ch, colour cw*ch
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from b64quant import bmp_pixels, to_pix, remap, edge_fill, sprite_grid, GREYS  # noqa: E402
from b64palette import RGB, write_png, COLOUR_NAMES  # noqa: E402
from b64formats import Pix  # noqa: E402

T = -1   # transparent marker in the master


def read_still(path):
    """Return (bg, pixel map 160x200 of palette indices) from a .still file."""
    data = open(path, "rb").read()
    bg = data[0]
    bitmap, screen, colour = data[1:8001], data[8001:9001], data[9001:10001]
    p = Pix(160, 200, bg)
    for cy in range(25):
        for cx in range(40):
            i = cy * 40 + cx
            cols = [bg, screen[i] >> 4, screen[i] & 15, colour[i] & 15]
            for r in range(8):
                b = bitmap[i * 8 + r]
                for k in range(4):
                    p.p[cy * 8 + r][cx * 4 + k] = cols[(b >> (6 - 2 * k)) & 3]
    return bg, p


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = {a.split("=")[0][2:]: a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--") and "=" in a}
    src, out, gw, gh = args[0], args[1], int(args[2]), int(args[3])
    mc0, ind, mc1 = (COLOUR_NAMES.index(n) for n in opts.get("colours", "black,white,blue").split(","))
    fat_w, h = gw * 12, gh * 21
    cw, ch = gw * 3, (h + 7) // 8

    # --- master: quantise under the sprite rule
    rows = bmp_pixels(src, fat_w * 2, h)
    p = to_pix(rows, fat_w, h)
    keys = [COLOUR_NAMES.index(n) for n in opts["key"].split(",")] if "key" in opts else [p.p[0][0]]
    key = keys[0]
    # one edge fill per key colour, OR-ed: a fill only crosses its own colour,
    # so a grey floor never leaks into black tyres that stand on it
    trans = [[False] * fat_w for _ in range(h)]
    for kc in keys:
        t = edge_fill(p, kc)
        for y in range(h):
            for x in range(fat_w):
                trans[y][x] = trans[y][x] or t[y][x]
    master = [[T if trans[y][x] else p.p[y][x] for x in range(fat_w)] for y in range(h)]
    for y in range(h):
        for x in range(fat_w):
            c = master[y][x]
            if c != T and c not in (mc0, ind, mc1):
                master[y][x] = remap(c, [mc0, ind, mc1])

    if "dump" in opts:
        leg = {T: '.', mc0: '#', ind: 'w', mc1: 'b'}
        for y in range(h):
            print("%2d " % y + "".join(leg.get(master[y][x], 'g') for x in range(fat_w)))

    # --- shadow: checkerboard black ellipse in the transparent area under the body
    if "shadow" in opts:
        cols = [x for x in range(fat_w) if any(master[y][x] != T for y in range(h))]
        bottom = max(y for y in range(h) for x in range(fat_w) if master[y][x] != T)
        x0, x1 = cols[0] + 2, cols[-1] - 2
        cx, rx = (x0 + x1) / 2, (x1 - x0) / 2
        cy, ry = bottom - 1, 3.0
        for y in range(int(cy - ry), min(h, int(cy + ry) + 1)):
            for x in range(x0, x1 + 1):
                if master[y][x] == T and ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0 and (x + y) & 1 == 0:
                    master[y][x] = mc0
                    trans[y][x] = False

    # --- wheels: find black discs in the lower half, or take them from --wheels
    wheels = []
    if opts.get("wheels") == "auto":
        seen = [[False] * fat_w for _ in range(h)]
        blobs = []
        for y in range(h // 2, h):
            for x in range(fat_w):
                if master[y][x] == mc0 and not seen[y][x]:
                    pts, stack = [], [(x, y)]
                    while stack:
                        ax, ay = stack.pop()
                        if not (0 <= ax < fat_w and h // 2 <= ay < h) or seen[ay][ax] or master[ay][ax] != mc0:
                            continue
                        seen[ay][ax] = True
                        pts.append((ax, ay))
                        stack += [(ax + 1, ay), (ax - 1, ay), (ax, ay + 1), (ax, ay - 1)]
                    if len(pts) > 12:
                        xs, ys = [a for a, _ in pts], [b for _, b in pts]
                        blobs.append((len(pts), (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2,
                                      (max(xs) - min(xs)) / 2, (max(ys) - min(ys)) / 2))
        # the two largest, roughly wheel-shaped (taller than wide in fat pixels, or close)
        blobs.sort(reverse=True)
        wheels = [(cx, cy, rx, ry) for _, cx, cy, rx, ry in blobs[:2] if ry >= 2 and rx >= 1]
        print("wheels detected:", [tuple(round(v, 1) for v in w) for w in wheels])
    elif "wheels" in opts:
        v = [float(t) for t in opts["wheels"].split(",")]
        wheels = [tuple(v[i:i + 4]) for i in range(0, len(v), 4)]
    nwf = int(opts.get("wheel-frames", "4"))
    wheel_frames = []            # list of masters, one per frame
    import math
    for k in range(nwf):
        m = [row[:] for row in master]
        for (cx, cy, rx, ry) in wheels:
            # keep the tyre ring; redraw the inside: hub dot and four spokes at 22.5 degree steps
            irx, iry = rx * 0.62, ry * 0.62
            for y in range(int(cy - ry), int(cy + ry) + 1):
                for x in range(int(cx - rx), int(cx + rx) + 1):
                    if 0 <= x < fat_w and 0 <= y < h and ((x - cx) / irx) ** 2 + ((y - cy) / iry) ** 2 <= 1.0:
                        m[y][x] = mc0
            for j in range(4):
                a = math.radians(k * (90.0 / nwf) + j * 90)
                for t in range(0, 20):
                    f = t / 20.0
                    x, y = int(round(cx + math.cos(a) * irx * f)), int(round(cy + math.sin(a) * iry * f))
                    if 0 <= x < fat_w and 0 <= y < h:
                        m[y][x] = ind
            if 0 <= int(cy) < h and 0 <= int(cx) < fat_w:
                m[int(cy)][int(cx)] = ind
        wheel_frames.append(m)
    if wheels:
        master = wheel_frames[0]

    # --- sprites straight from the master
    q = Pix(fat_w, h, key)
    for y in range(h):
        for x in range(fat_w):
            q.p[y][x] = key if master[y][x] == T else master[y][x]
    sprites = sprite_grid(q, gw, gh, mc0, ind, mc1, trans)

    # --- block: composite transparent pixels, then encode with FIXED codes
    still_bg, still = (None, None)
    if "still" in opts:
        still_bg, still = read_still(opts["still"])
        at_x, at_y = (int(v) for v in opts["at"].split(","))
        floor = still_bg
    else:
        floor = COLOUR_NAMES.index(opts.get("floor", "dgray"))
    bg = still_bg if still is not None else COLOUR_NAMES.index(opts.get("bg", "black"))
    block = Pix(cw * 4, ch * 8, bg)
    for y in range(ch * 8):
        for x in range(cw * 4):
            c = master[y][x] if y < h else T
            if c == T:
                if still is not None:
                    sy, sx = at_y * 8 + y, at_x * 4 + x
                    c = still.p[sy][sx] if 0 <= sy < 200 and 0 <= sx < 160 else bg
                else:
                    c = floor
            block.p[y][x] = c
    # per-cell colour codes: bg is 00; the sprite colours take fixed codes where
    # they differ from bg; anything else (still pixels) fills the remaining codes
    # and the least used extras are remapped, exactly like a still
    bitmap, screen, colour = bytearray(), bytearray(), bytearray()
    fixed = 0
    patched = {}               # (still cx, cy) -> allowed colours, for --patch-still
    for cy in range(ch):
        for cx in range(cw):
            counts = {}
            for yy in range(cy * 8, cy * 8 + 8):
                for xx in range(cx * 4, cx * 4 + 4):
                    c = block.p[yy][xx]
                    if c != bg:
                        counts[c] = counts.get(c, 0) + 1
            # sprite colours first so the object itself is never damaged
            order = [c for c in (mc0, ind, mc1) if c in counts and c != bg]
            order += [c for c in sorted(counts, key=lambda c: -counts[c]) if c not in order]
            keep = order[:3]
            if len(order) > 3:
                fixed += 1
                allowed = [bg] + keep
                for yy in range(cy * 8, cy * 8 + 8):
                    for xx in range(cx * 4, cx * 4 + 4):
                        c = block.p[yy][xx]
                        if c not in allowed:
                            block.p[yy][xx] = remap(c, allowed)
                if still is not None:
                    patched[(at_x + cx, at_y + cy)] = allowed
            while len(keep) < 3:
                keep.append(keep[-1] if keep else bg)
            codes = {bg: 0, keep[0]: 1, keep[1]: 2, keep[2]: 3}
            for r in range(8):
                b = 0
                for k in range(4):
                    b |= codes.get(block.p[cy * 8 + r][cx * 4 + k], 0) << (6 - 2 * k)
                bitmap.append(b)
            screen.append((keep[0] << 4) | keep[1])
            colour.append(keep[2])

    # --- row spans of cells with any object pixel
    spans = bytearray()
    for cy in range(ch):
        vis = [cx for cx in range(cw)
               if any(master[y][x] != T for y in range(cy * 8, min(cy * 8 + 8, h)) for x in range(cx * 4, cx * 4 + 4))]
        spans += bytes([vis[0], vis[-1] + 1] if vis else [0, 0])
    spans += bytes(32 - len(spans))

    # --patch-still: write a copy of the still whose cells under the object use
    # the same reduced colour sets, so parking there changes no pixel outside the car
    if "patch-still" in opts and still is not None:
        data = bytearray(open(opts["still"], "rb").read())
        for (scx, scy), allowed in patched.items():
            i = scy * 40 + scx
            keep = [c for c in allowed if c != bg]
            while len(keep) < 3:
                keep.append(keep[-1] if keep else bg)
            codes = {bg: 0, keep[0]: 1, keep[1]: 2, keep[2]: 3}
            for r in range(8):
                b = 0
                for k in range(4):
                    c = still.p[scy * 8 + r][scx * 4 + k]
                    if c not in codes:
                        c = remap(c, allowed)
                    b |= codes[c] << (6 - 2 * k)
                data[1 + i * 8 + r] = b
            data[8001 + i] = (keep[0] << 4) | keep[1]
            data[9001 + i] = keep[2]
        with open(opts["patch-still"], "wb") as f:
            f.write(bytes(data))

    anim = b""
    if wheels:
        touched = set()
        for (cx, cy, rx, ry) in wheels:
            for y in range(int(cy - ry), int(cy + ry) + 1):
                for x in range(int(cx - rx), int(cx + rx) + 1):
                    if 0 <= x < fat_w and 0 <= y < h:
                        touched.add((y // 21) * gw + x // 12)
        idx = sorted(touched)
        anim = bytes([nwf, len(idx)] + idx)
        for m in wheel_frames:
            qq = Pix(fat_w, h, key)
            for y in range(h):
                for x in range(fat_w):
                    qq.p[y][x] = key if m[y][x] == T else m[y][x]
            frames = sprite_grid(qq, gw, gh, mc0, ind, mc1, trans)
            for i in idx:
                anim += frames[i * 64:(i + 1) * 64]
        print(f"wheel animation: {nwf} frames over sprites {idx}, {len(anim)} bytes")
    if not anim:
        anim = bytes([0, 0])            # an explicit empty animation header so the sections after it are findable
    # --- lights: "dx,dy,radius,lamp:colour/frames,colour/frames;..." per light
    lights = b""
    if "lights" in opts:
        recs = []
        for spec in opts["lights"].split(";"):
            head, pat = spec.split(":")
            dx, dy, radius, lamp = [int(v) for v in head.split(",")]
            entries = [(int(c), int(f)) for c, f in (e.split("/") for e in pat.split(","))]
            assert 1 <= len(entries) <= 4, "a light pattern has 1 to 4 entries"
            rec = [dx & 255, dy & 255, radius, lamp, len(entries), 0]
            for c, f in entries:
                rec += [c, f]
            rec += [0] * (16 - len(rec))
            recs.append(bytes(rec))
        lights = bytes([len(recs)]) + b"".join(recs)
        print(f"lights: {len(recs)} light(s), {len(lights)} bytes")
    hdr = bytes([gw, gh, cw, ch, mc0, ind, mc1, floor])
    blob = hdr + spans + sprites + bytes(bitmap) + bytes(screen) + bytes(colour) + anim + lights
    with open(out, "wb") as f:
        f.write(blob)
    if "preview" in opts:
        # sprites on the left, block on the right, at 2x
        rows_a = q.render(2)
        rows_b = block.render(2)
        gap = [(20, 20, 20)] * 8
        rows_out = []
        for i in range(max(len(rows_a), len(rows_b))):
            ra = rows_a[i] if i < len(rows_a) else [(20, 20, 20)] * len(rows_a[0])
            rb = rows_b[i] if i < len(rows_b) else [(20, 20, 20)] * len(rows_b[0])
            rows_out.append(ra + gap + rb)
        write_png(opts["preview"], rows_out)
    print(f"object {os.path.basename(out)}: {gw}x{gh} sprites, {cw}x{ch} cells, {len(blob)} bytes, "
          f"{fixed} block cells repaired, composite {'still@%s' % opts['at'] if still is not None else COLOUR_NAMES[floor]}")


if __name__ == "__main__":
    main()
