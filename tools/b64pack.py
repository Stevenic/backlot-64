#!/usr/bin/env python3
"""backlot-64 REU image packer.

Lays out an REU image from a manifest and emits slots.inc with the REU
address of every slot so nothing in assembly hard-codes an offset.

Manifest is a text file, one slot per line:

    size    8192              ; image size in KiB (VICE -reusize)
    slot    WORLD    $000000  build/world.map
    slot    REGIONS  $400000  build/world.reg
    slot    TILESET0 $401000  build/bellamar_day.bin
    slot    SPRITES0 $431000  build/sprites0.spr
    slot    SCRATCH  $7F0000  -

A '-' file reserves the slot without contents.

    header  $4FF000           ; where the image describes itself

With a header line the image carries, at that address:

    +0   "B64R"
    +4   format version (1)
    +5   layout hash, 16 bits: CRC-16/CCITT over "NAME=ADDR;" for every slot
    +7   slot count
    +8   image size in MB
    +16  one 16-byte descriptor per slot: address (3), length (3), 0, 0, name (8)

The same magic, version and hash go into slots.inc as the bytes the engine
compares at boot (b64_boot_check), so a program refuses an REU that holds
nothing, or an image packed from a different manifest, instead of running
on whatever it finds.  The hash covers names and addresses only, which the
manifest alone decides, so slots.inc never depends on the assets.
After Honza Slesinger, DOOM for the C64 Ultimate (its self-describing REU
image with boot cross-checks).  Changed: the check is one REU verify
command against constants in ROM-side data, no bytes are fetched, because
resident RAM here is scarcer than in DOOM's 64 KB-per-module layout.

usage: b64pack.py <manifest> <out.reu> <out.inc|->
       b64pack.py --inc <manifest> <out.inc>   (addresses only, no files needed)
       b64pack.py --list <image.reu> [<manifest>]   (print the image's own header)
"""
import sys

FORMAT = 1
MAGIC = b"B64R"


def crc16(data, crc=0xFFFF):
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def layout_hash(slots):
    return crc16("".join(f"{n}={a:06X};" for n, a in slots).encode())


def read_manifest(manifest):
    size_kib, header, slots = 8192, None, []
    with open(manifest) as f:
        for line in f:
            line = line.split(";")[0].strip()
            if not line:
                continue
            parts = line.split()
            if parts[0] == "size":
                size_kib = int(parts[1])
            elif parts[0] == "header":
                header = parse_addr(parts[1])
            elif parts[0] == "slot":
                slots.append((parts[1], parse_addr(parts[2]), parts[3]))
    return size_kib, header, slots


def list_image(image, manifest):
    _, header, _ = read_manifest(manifest)
    d = open(image, "rb").read()
    if header is None or d[header:header + 4] != MAGIC:
        raise SystemExit(f"{image}: no backlot-64 header at ${header or 0:06X}")
    ver, h, n, mb = d[header + 4], d[header + 5] | (d[header + 6] << 8), d[header + 7], d[header + 8]
    print(f"{image}: format {ver}, layout hash ${h:04X}, {n} slots, {mb} MB")
    for i in range(n):
        r = d[header + 16 + 16 * i: header + 32 + 16 * i]
        print(f"  {r[8:16].decode().rstrip():<8} ${int.from_bytes(r[0:3], 'little'):06X}  {int.from_bytes(r[3:6], 'little'):>8} bytes")


def parse_addr(s):
    return int(s[1:], 16) if s.startswith("$") else int(s, 0)


def main():
    if sys.argv[1] == "--list":
        return list_image(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "reu.manifest")
    inc_only = sys.argv[1] == "--inc"
    if inc_only:
        manifest, out_reu, out_inc = sys.argv[2], None, sys.argv[3]
    else:
        manifest, out_reu, out_inc = sys.argv[1], sys.argv[2], sys.argv[3]
    size_kib, header, slots = read_manifest(manifest)
    image = bytearray(size_kib * 1024)
    placed = []
    for name, addr, path in slots:
        if inc_only:
            placed.append((name, addr, 0))
            continue
        if path != "-":
            with open(path, "rb") as f:
                data = f.read()
            if addr + len(data) > len(image):
                raise SystemExit(f"slot {name} at ${addr:06X} + {len(data)} bytes exceeds the {size_kib} KiB image")
            image[addr:addr + len(data)] = data
            placed.append((name, addr, len(data)))
        else:
            placed.append((name, addr, 0))
    for i in range(len(placed) - 1):
        n, a, ln = placed[i]
        n2, a2, _ = placed[i + 1]
        if a + ln > a2:
            raise SystemExit(f"slot {n} overlaps {n2}")
    lhash = layout_hash([(n, a) for n, a, _ in slots])
    if header is not None:
        hdr = bytearray(MAGIC + bytes([FORMAT, lhash & 255, lhash >> 8, len(placed), size_kib // 1024]) + bytes(7))
        for name, addr, ln in placed:
            hdr += addr.to_bytes(3, "little") + ln.to_bytes(3, "little") + bytes(2) + name[:8].ljust(8).encode()
        for name, addr, ln in placed:
            if addr < header + len(hdr) and header < addr + max(ln, 1):
                raise SystemExit(f"the header at ${header:06X} ({len(hdr)} bytes) overlaps slot {name}")
        image[header:header + len(hdr)] = hdr
    if out_reu:
        with open(out_reu, "wb") as f:
            f.write(image)
    if out_inc != "-":
        with open(out_inc, "w") as f:
            f.write("; generated by b64pack.py -- REU slot addresses\n")
            f.write(f"REU_SIZE_KIB = {size_kib}\n")
            if header is not None:
                f.write(f"SLOT_HEADER       = ${header:06X}\n")
                f.write(f"REU_FORMAT        = {FORMAT}\n")
                f.write(f"REU_LAYOUT_HASH   = ${lhash:04X}\n")
            for name, addr, ln in placed:
                f.write(f"SLOT_{name:<12} = ${addr:06X}\n")
    for name, addr, ln in placed:
        print(f"  {name:<12} ${addr:06X}  {ln:>8} bytes")
    if header is not None:
        print(f"  header at ${header:06X}, layout hash ${lhash:04X}")


if __name__ == "__main__":
    main()
