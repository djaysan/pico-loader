#!/usr/bin/env python3
"""Locate the arm9 OSi_IrqVBlank by its shared-memory VBlank counter literal.

The arm7 version references 0x027FFC3C (0x02FFFC3C on SDK5) — the shared
area VBlank count. The arm9 twin references the same word (or FC38).
Find literal occurrences in the decompressed arm9, walk back to a
function prologue, dump bytes for disassembly.
"""
import struct, sys
from scan_vblank import u32, blz_decompress, find_module_params

CANDIDATE_LITERALS = [0x027FFC3C, 0x02FFFC3C, 0x027FFC38, 0x02FFFC38]

def get_arm9(path):
    rom = open(path, "rb").read()
    a9_off, a9_entry, a9_load, a9_size = struct.unpack_from("<IIII", rom, 0x20)
    arm9 = rom[a9_off:a9_off + a9_size]
    mp = find_module_params(arm9)
    if mp and mp["compressedEnd"]:
        end_idx = mp["compressedEnd"] - a9_load
        if 8 < end_idx <= len(arm9):
            arm9, _ = blz_decompress(arm9, end_idx)
    return arm9, a9_load, (mp or {}).get("sdkVersion", 0)

def scan_rom(path):
    name = path.split("/")[-1]
    arm9, load, sdk = get_arm9(path)
    print(f"\n=== {name} (sdk {sdk:08X}) ===")
    n = len(arm9) & ~3
    for i in range(0, n, 4):
        w = u32(arm9, i)
        if w not in CANDIDATE_LITERALS:
            continue
        # walk back for a function prologue within 0x100 bytes
        start = None
        kind = None
        for back in range(4, 0x104, 4):
            j = i - back
            if j < 0: break
            wj = u32(arm9, j)
            if (wj & 0xFFFF0000) == 0xE92D0000:  # arm push
                start = j; kind = "arm"; break
            h0 = wj & 0xFFFF
            h1 = wj >> 16
            if (h0 & 0xFF00) == 0xB500:  # thumb push {...,lr} low half
                start = j; kind = "thumb@+0"; break
            if (h1 & 0xFF00) == 0xB500:
                start = j + 2; kind = "thumb@+2"; break
        if start is None:
            continue
        print(f"  literal {w:08X} @ +0x{i:X}; {kind} prologue @ +0x{start:X} (0x{load + start:08X}) delta 0x{i - start:X}")
        words = " ".join(f"{u32(arm9, start + k):08X}" for k in range(0, 0x60, 4))
        print(f"    {words}")

for p in sys.argv[1:]:
    scan_rom(p)
