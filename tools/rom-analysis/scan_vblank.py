#!/usr/bin/env python3
"""Find OSi_IrqVBlank in NDS arm9/arm7 binaries.

Mirrors pico-loader: header parse, module params magic scan,
MIi_UncompressBackward (backwards BLZ), then signature search.
The arm7 exact-pattern hit doubles as tooling validation (the beep
works on hardware, so the arm7 signature is known to match).
"""
import struct, sys

PATTERNS = [
    ("arm0",  [0xE92D4008, 0xE59F2038, 0xE59F0038, 0xE5921000], 0x3C),
    ("arm1",  [0xE92D4000, 0xE24DD004, 0xE59F003C, 0xE5902060], 0x40),
    ("thumb0",[0x4809B508, 0x69024909, 0x1C406808, 0x2A006008], 0x20),
]

def u32(b, o): return struct.unpack_from("<I", b, o)[0]

def blz_decompress(buf, end_idx):
    """MIi_UncompressBackward. buf grows by extraLen; returns new buf."""
    hdr = u32(buf, end_idx - 8)
    extra = u32(buf, end_idx - 4)
    comp_len = hdr & 0xFFFFFF
    hdr_len = hdr >> 24
    if comp_len == 0 or comp_len > end_idx:
        return buf, False
    out = bytearray(buf) + bytearray(extra)
    src = end_idx - hdr_len       # read pointer, moves down
    src_start = end_idx - comp_len
    dst = end_idx + extra         # write pointer, moves down
    while src > src_start:
        src -= 1
        flags = out[src]
        for _ in range(8):
            if src <= src_start:
                break
            if flags & 0x80:
                src -= 1; b1 = out[src]
                src -= 1; b2 = out[src]
                disp = (((b1 & 0x0F) << 8) | b2) + 2
                length = (b1 >> 4) + 3
                for _ in range(length):
                    val = out[dst + disp]
                    dst -= 1
                    out[dst] = val
            else:
                src -= 1
                dst -= 1
                out[dst] = out[src]
            flags = (flags << 1) & 0xFF
    return bytes(out), True

def find_module_params(arm9):
    for i in range(0, len(arm9) - 8, 4):
        if u32(arm9, i) == 0xDEC00621 and u32(arm9, i + 4) == 0x2106C0DE:
            start = i + 8 - 36
            if start < 0: continue
            return {
                "compressedEnd": u32(arm9, start + 20),
                "sdkVersion": u32(arm9, start + 24),
            }
    return None

def masked_eq(word, pat):
    # pc-relative ldr (arm): literal pool distance may shift, ignore imm12
    if (pat & 0xFFFF0000) in (0xE59F0000, 0xE59F1000 & 0xFFFF0000):
        pass
    if (pat & 0x0FFF0000) >> 16 in range(0x59F, 0x5A0):  # E59Fx
        return (word & 0xFFFFF000) == (pat & 0xFFFFF000)
    return word == pat

def search(blob, patterns, masked=False):
    hits = []
    n = len(blob) & ~3
    for name, pat, off in patterns:
        for i in range(0, n - 16, 4):
            ok = True
            for j, p in enumerate(pat):
                w = u32(blob, i + j * 4)
                if masked:
                    if not masked_eq(w, p): ok = False; break
                else:
                    if w != p: ok = False; break
            if ok:
                hits.append((name, i, off))
    return hits

def dump(blob, i, length=0x70):
    words = [f"{u32(blob, i + k):08X}" for k in range(0, length, 4)]
    return " ".join(words)

def scan_rom(path):
    rom = open(path, "rb").read()
    name = path.split("/")[-1]
    print(f"\n=== {name} ===")
    a9_off, a9_entry, a9_load, a9_size = struct.unpack_from("<IIII", rom, 0x20)
    a7_off, a7_entry, a7_load, a7_size = struct.unpack_from("<IIII", rom, 0x30)
    arm9 = rom[a9_off:a9_off + a9_size]
    arm7 = rom[a7_off:a7_off + a7_size]

    # arm7: exact patterns (tooling ground truth)
    for nm, i, off in search(arm7, PATTERNS):
        print(f"  arm7 exact {nm} @ +0x{i:X} (0x{a7_load + i:08X})")
        print(f"    bytes: {dump(arm7, i)}")

    mp = find_module_params(arm9)
    decompressed = False
    if mp and mp["compressedEnd"]:
        end_idx = mp["compressedEnd"] - a9_load
        if 8 < end_idx <= len(arm9):
            arm9, decompressed = blz_decompress(arm9, end_idx)
    print(f"  sdk: {mp['sdkVersion']:08X}" if mp else "  no module params",
          f"| arm9 {a9_size} -> {len(arm9)} bytes | decompressed: {decompressed}")

    hits = search(arm9, PATTERNS)
    for nm, i, off in hits:
        print(f"  arm9 EXACT {nm} @ +0x{i:X} (0x{a9_load + i:08X}), tail @ +0x{off:X}:")
        print(f"    bytes: {dump(arm9, i)}")
    if not hits:
        mhits = search(arm9, PATTERNS, masked=True)
        for nm, i, off in mhits:
            print(f"  arm9 masked {nm} @ +0x{i:X} (0x{a9_load + i:08X}):")
            print(f"    bytes: {dump(arm9, i)}")
        if not mhits:
            print("  arm9: no exact or masked hits")

for p in sys.argv[1:]:
    scan_rom(p)
