#!/usr/bin/env python3
"""A small PNG reader and writer for the check harness: 8-bit RGB, RGBA and
palette images, non-interlaced, which is what VICE's screenshot writes.
No dependencies, so the checks run wherever Python and VICE do."""
import struct
import zlib


def read_png(path):
    """-> (width, height, rows) where each row is a bytes object of RGB triples."""
    d = open(path, "rb").read()
    if d[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    pos, idat, plte = 8, b"", None
    while pos < len(d):
        ln, tag = struct.unpack(">I4s", d[pos:pos + 8])
        body = d[pos + 8:pos + 8 + ln]
        if tag == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif tag == b"PLTE":
            plte = body
        elif tag == b"IDAT":
            idat += body
        pos += 12 + ln
    if depth != 8 or interlace or ctype not in (2, 3, 6):
        raise ValueError(f"{path}: unsupported PNG (depth {depth}, colour type {ctype}, interlace {interlace})")
    bpp = {2: 3, 3: 1, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]
        cur = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        if f == 1:
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i - bpp]) & 255
        elif f == 2:
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = cur[i - bpp] if i >= bpp else 0
                cur[i] = (cur[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = cur[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                cur[i] = (cur[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = cur
        if ctype == 2:
            rows.append(bytes(cur))
        elif ctype == 6:
            out = bytearray(w * 3)
            out[0::3], out[1::3], out[2::3] = cur[0::4], cur[1::4], cur[2::4]
            rows.append(bytes(out))
        else:
            rows.append(b"".join(plte[3 * v:3 * v + 3] for v in cur))
    return w, h, rows


def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def px(rows, x, y):
    return rows[y][3 * x:3 * x + 3]


def diff(a, b, box=None, mask=None):
    """Pixels that differ between two frames, as a list of (x, y); box =
    (x0, y0, x1, y1) limits the area, mask is a set of (x, y) to ignore."""
    x0, y0, x1, y1 = box or (0, 0, len(a[0]) // 3, len(a))
    out = []
    for y in range(y0, y1):
        ra, rb = a[y][3 * x0:3 * x1], b[y][3 * x0:3 * x1]
        if ra == rb:
            continue
        for x in range(x1 - x0):
            if ra[3 * x:3 * x + 3] != rb[3 * x:3 * x + 3] and (mask is None or (x + x0, y) not in mask):
                out.append((x + x0, y))
    return out
