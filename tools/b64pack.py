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

    module  COLLISION COLLISION base=$8000 size=$0D00 provides=COL:1 requires=PHYS:1 default

A module (docs/MODULES.md) names its slot, the address it is linked for and
loads to, how many bytes it occupies there, the interface it provides and
its version, the interfaces it requires (at least those versions), the entry
to call when it replaces another provider of its interface (swap=n), and
whether it is its interface's default provider (loaded when a requirement is
unmet).  The packer numbers modules and interfaces from 1 in the order they
appear, writes MOD_* and IF_* into slots.inc, and writes the module table
into the slot named MODTAB: 16 bytes a module, module n at 16 * n:

    +0 id  +1 flags (1 default)  +2 REU address (3)  +5 base (2)  +7 size (2)
    +9 provides, version  +11 requires, version  +13 requires, version
    +15 swap entry ($FF none)

and at +0 the module count.  A module that provides nothing leaves +9 and
+10 zero.  Providers of one interface must share a base address, so only
one is resident at a time; there are at most 15 modules and 15 interfaces.

    op      80 DRAW   DEMO_OPS 0

A game opcode (80-127, docs/MODULES.md): its number, its name (OP_DRAW in
slots.inc), the module whose jump table holds its handler and the entry
there (the handler is at base + 3 * entry).  The module must provide an
interface: the VM loads its provider when the opcode runs and it is away.
The 48 game opcodes follow the module table in MODTAB as three 48-byte
arrays: the interface (0 none), the handler's low bytes, its high bytes.
The module and op lines are in the layout hash, so a program refuses an
image packed with a different module table.

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


def layout_hash(slots, extra=""):
    return crc16(("".join(f"{n}={a:06X};" for n, a in slots) + extra).encode())


def read_manifest(manifest):
    size_kib, header, slots, modules, ops = 8192, None, [], [], []
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
            elif parts[0] == "op":
                ops.append({"num": int(parts[1]), "name": parts[2], "module": parts[3], "entry": int(parts[4])})
            elif parts[0] == "module":
                m = {"name": parts[1], "slot": parts[2], "requires": [], "swap": 0xFF, "default": False, "provides": None}
                for tok in parts[3:]:
                    if tok == "default":
                        m["default"] = True
                        continue
                    k, v = tok.split("=")
                    if k in ("base", "size"):
                        m[k] = parse_addr(v)
                    elif k == "provides":
                        m["provides"] = (v.split(":")[0], int(v.split(":")[1]))
                    elif k == "requires":
                        m["requires"] = [(r.split(":")[0], int(r.split(":")[1])) for r in v.split(",")]
                    elif k == "swap":
                        m["swap"] = int(v)
                modules.append(m)
    return size_kib, header, slots, modules, ops


def module_table(modules, ops, slot_addr):
    """The module table's bytes (with the game opcodes), the interface ids, and the text the layout hash covers."""
    ifaces = []
    for m in modules:
        for name, _ in ([m["provides"]] if m["provides"] else []) + m["requires"]:
            if name not in ifaces:
                ifaces.append(name)
    if len(modules) > 15 or len(ifaces) > 15:
        raise SystemExit("at most 15 modules and 15 interfaces")
    bases = {}
    for m in modules:
        if m["provides"]:
            b = bases.setdefault(m["provides"][0], m["base"])
            if b != m["base"]:
                raise SystemExit(f"module {m['name']}: providers of {m['provides'][0]} must share a base address")
    tab = bytearray(16 * 16)
    tab[0] = len(modules)
    text = ""
    for n, m in enumerate(modules, 1):
        if len(m["requires"]) > 2:
            raise SystemExit(f"module {m['name']}: at most two requirements")
        e = bytearray(16)
        e[0], e[1] = n, 1 if m["default"] else 0
        e[2:5] = slot_addr[m["slot"]].to_bytes(3, "little")
        e[5:7] = m["base"].to_bytes(2, "little")
        e[7:9] = m["size"].to_bytes(2, "little")
        if m["provides"]:
            e[9], e[10] = ifaces.index(m["provides"][0]) + 1, m["provides"][1]
        for k, (iname, ver) in enumerate(m["requires"]):
            e[11 + 2 * k], e[12 + 2 * k] = ifaces.index(iname) + 1, ver
        e[15] = m["swap"]
        tab[16 * n:16 * n + 16] = e
        text += f"M:{m['name']},{m['slot']},{m['base']:04X},{m['size']:04X},{m['provides']},{m['requires']},{m['swap']},{m['default']};"
    gif, glo, ghi = bytearray(48), bytearray(48), bytearray(48)
    names = [m["name"] for m in modules]
    for op in ops:
        if not 80 <= op["num"] <= 127:
            raise SystemExit(f"op {op['name']}: game opcodes are 80-127")
        if op["module"] not in names:
            raise SystemExit(f"op {op['name']}: no module {op['module']}")
        m = modules[names.index(op["module"])]
        if not m["provides"]:
            raise SystemExit(f"op {op['name']}: module {m['name']} provides no interface")
        k = op["num"] - 80
        if ghi[k]:
            raise SystemExit(f"op {op['name']}: opcode {op['num']} is taken")
        h = m["base"] + 3 * op["entry"]
        gif[k], glo[k], ghi[k] = ifaces.index(m["provides"][0]) + 1, h & 255, h >> 8
        text += f"O:{op['num']},{op['name']},{op['module']},{op['entry']};"
    return bytes(tab + gif + glo + ghi), ifaces, text


def list_image(image, manifest):
    _, header, _, _, _ = read_manifest(manifest)
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
    size_kib, header, slots, modules, ops = read_manifest(manifest)
    slot_addr = {n: a for n, a, _ in slots}
    modtab, ifaces, modtext = module_table(modules, ops, slot_addr) if modules else (b"", [], "")
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
    lhash = layout_hash([(n, a) for n, a, _ in slots], modtext)
    if modules and not inc_only:
        if "MODTAB" not in slot_addr:
            raise SystemExit("module lines need a slot MODTAB for the module table")
        a = slot_addr["MODTAB"]
        image[a:a + len(modtab)] = modtab
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
            if modules:
                f.write(f"MOD_COUNT         = {len(modules)}\n")
                for n, m in enumerate(modules, 1):
                    f.write(f"MOD_{m['name']:<12} = {n}\n")
                for n, i in enumerate(ifaces, 1):
                    f.write(f"IF_{i:<13} = {n}\n")
                for op in ops:
                    f.write(f"OP_{op['name']:<13} = {op['num']}\n")
    for name, addr, ln in placed:
        print(f"  {name:<12} ${addr:06X}  {ln:>8} bytes")
    if header is not None:
        print(f"  header at ${header:06X}, layout hash ${lhash:04X}")


if __name__ == "__main__":
    main()
