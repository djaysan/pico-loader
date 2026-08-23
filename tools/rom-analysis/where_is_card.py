#!/usr/bin/env python3
"""Is the card-read function in the static arm9, or in an autoload block?

An autoload block sits in the arm9 image at one address and is COPIED to a
different target address by the game's own startup before main() runs. A
patch that writes an absolute address into such a block survives the copy; a
PC-RELATIVE branch does not - it lands wherever the offset points from the
new location, which is garbage.

The loader only ever writes absolute jumps (ldr r0,=addr; blx r0 /
ldr pc,[pc,#-4] + literal). GuideOverlay9Install writes `b guide_tramp`.
"""
import struct, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scan_irqtable import arm9_of, blz_decompress
from check_exit_hook import CARD_ARM, CARD_THUMB, ROM_ARM, ROM_THUMB, MODPARAMS, find_first, sdk_version

def hdr(path):
    with open(path, 'rb') as f:
        h = f.read(0x200)
    off, entry, load, size = struct.unpack('<IIII', h[0x20:0x30])
    return dict(off=off, entry=entry, load=load, size=size,
                code=h[12:16].decode('ascii', 'replace'))

def modparams(img):
    i = img.find(MODPARAMS)
    if i < 0:
        return None
    # struct ends with the two magics; sdkVersion is the word before them
    # 7 words precede magicBigEndian: autoloadListStart, autoloadListEnd,
    # autoloadStart, bssStart, bssEnd, compressedEnd, sdkVersion
    base = i - 4 * 7
    f = struct.unpack('<7I', img[base:base + 28])
    return dict(autoloadListStart=f[0], autoloadListEnd=f[1], autoloadStart=f[2],
                bssStart=f[3], bssEnd=f[4], compressedEnd=f[5], sdkVersion=f[6])

for path in sys.argv[1:]:
    h = hdr(path)
    a9, _ = arm9_of(path)
    dec = blz_decompress(a9)
    name = os.path.basename(path)[:42]

    # pick whichever view actually contains a card signature
    chosen = None
    for img in ([a9] + ([dec] if dec and dec != a9 else [])):
        twl = (sdk_version(img) >> 24) == 5
        arm = ROM_ARM if twl else CARD_ARM
        sig, off = find_first(img, arm)
        if off >= 0:
            chosen = (img, sig, off, twl)
            break
    if not chosen:
        print(f'{name}: no ARM card entry'); continue
    img, sig, off, twl = chosen

    mp = modparams(img)
    addr = h['load'] + off
    print(f'\n{name}  [{h["code"]}]')
    print(f'  arm9 load 0x{h["load"]:08X}  card fn at image+0x{off:X} -> 0x{addr:08X}  ({sig})')
    if not mp:
        print('  no module params'); continue
    print(f'  autoloadStart     0x{mp["autoloadStart"]:08X}')
    print(f'  autoloadListStart 0x{mp["autoloadListStart"]:08X}  end 0x{mp["autoloadListEnd"]:08X}')

    if addr < mp['autoloadStart']:
        print('  => STATIC arm9. Not relocated. A relative branch would survive.')
        continue

    # walk the list: each entry describes one block, laid out consecutively
    # in the image starting at autoloadStart
    ent = 16 if twl else 12
    ls = mp['autoloadListStart'] - h['load']
    le = mp['autoloadListEnd'] - h['load']
    src = mp['autoloadStart']
    hit = False
    for i, p in enumerate(range(ls, le, ent)):
        if p + ent > len(img):
            break
        target, size = struct.unpack('<II', img[p:p + 8])
        if src <= addr < src + size:
            delta = target - src
            print(f'  => AUTOLOAD BLOCK {i}: image 0x{src:08X}..0x{src+size:08X}'
                  f' -> RUNS AT 0x{target:08X}')
            print(f'     shifted by {delta:+#x} at runtime.'
                  f' Card fn really runs at 0x{addr + delta:08X}.')
            print('     A PC-RELATIVE BRANCH WRITTEN HERE IS WRONG BY THAT AMOUNT.')
            hit = True
            break
        src += size
    if not hit:
        print('  => past autoloadStart but not inside a listed block')
