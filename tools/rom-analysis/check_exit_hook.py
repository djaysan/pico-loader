#!/usr/bin/env python3
"""Report whether EXIT_TO_LAUNCHER will install on each rom, before hardware.

The exit needs two things from the loader's patch pass, and either can miss:

  1. a card-read function to detour. The blob is hooked at instruction 0 of
     CARDi_ReadCard (sdk 2-4) or CARDi_ReadRomWithCPU (twl-sdk), and
     GuideOverlay9Install only accepts an ARM entry whose first instruction is
     an stmfd (top halfword 0xE92D) - a thumb entry is refused rather than
     mis-hooked, so those roms just never exit.
  2. the OS_ResetSystem tail, which is what the blob jumps to. Without it
     there is nothing to reboot into and the blob is not installed at all.

Both sets of signatures are copied from the loader so this stays a pure
offline check; keep them in sync with
  arm9/source/patches/arm9/sdk2to4/CardiReadCardPatch.cpp
  arm9/source/patches/arm9/sdk5/CardiReadRomWithCpuPatch.cpp
  arm9/source/patches/arm9/OSResetSystemPatch.cpp

Usage:  check_exit_hook.py rom.nds [rom.nds ...]
        check_exit_hook.py --self-test
"""
import struct, sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scan_irqtable import arm9_of, blz_decompress

def w(*words):
    return struct.pack('<%dI' % len(words), *words)

# CARDi_ReadCard, sdk 2-4. ARM entries are hookable, thumb ones are not.
CARD_ARM = [
    ('sdk2 unknown',      w(0xE92D4FF0, 0xE24DD004, 0xE1A0A000, 0xE59F90D8)),
    ('sdk2 0029A7',       w(0xE92D4FF0, 0xE24DD004, 0xE1A0A000, 0xE59F90E0)),
    ('sdk2 004E8B',       w(0xE92D4FF0, 0xE24DD004, 0xE1A0A000, 0xE59F90FC)),
    ('sdk2 007530',       w(0xE92D47F0, 0xE1A05000, 0xE59F40D4, 0xE5941018)),
    ('sdk4 002774',       w(0xE92D4070, 0xE59F40D0, 0xE1A06000, 0xE3A00C02)),
    ('sdk4 017530',       w(0xE92D4070, 0xE59F40D8, 0xE1A06000, 0xE3A00C02)),
    ('sdk4 027539',       w(0xE92D4070, 0xE59F40D4, 0xE1A06000, 0xE3A00C02)),
]
CARD_THUMB = [
    ('sdk2 004F4C thumb', w(0xB083B5F0, 0x4E279000, 0x30209001, 0x4F269001)),
    ('sdk2 027533 thumb', w(0xB083B5F0, 0x4E259000, 0x30209001, 0x4F249001)),
    ('sdk3 027530 thumb', w(0xB082B5F8, 0x90019000, 0x90013020, 0x69C24825)),
    ('sdk4 017530 thumb', w(0xB082B5F8, 0x90019000, 0x90013020, 0x69C24827)),
    ('sdk4 027531 thumb', w(0xB082B5F8, 0x90019000, 0x90013020, 0x69C14841)),
]
# CARDi_ReadRomWithCPU, twl-sdk.
ROM_ARM = [
    ('twl 00753B',        w(0xE92D4FF8, 0xE24DD008, 0xE59F00FC, 0xE1A08003)),
]
ROM_THUMB = [
    ('twl thumb',         w(0xB085B5F0, 0x1C1D482D, 0x91006840, 0x95049201)),
    ('twl 017537 thumb',  w(0xB085B5F0, 0x1C1D482D, 0x91006800, 0x95049201)),
    ('twl 007538 thumb',  w(0xB085B5F0, 0x1C1D482B, 0x91006800, 0x95049201)),
    ('twl 037531 thumb',  w(0xB086B5F8, 0x1C1D482F, 0x91006800, 0x482E9003)),
    ('twl 037531h thumb', w(0xB086B5F8, 0x1C1D482F, 0x91006840, 0x482E9003)),
]
# End of OS_ResetSystem - the tail the loader repoints at the reboot code.
RESET = [
    w(0xE59F101C, 0xE3A00010, 0xE5815000, 0xEB000005),
    w(0xE59F1018, 0xE3A00010, 0xE5814000, 0xEB000004),
    w(0xE59F1014, 0xE3A00010, 0xE5814000, 0xEB000003),
    w(0xE59F1014, 0xE3A00010, 0xE5814000, 0xEBFFFFD9),
    w(0xE59F103C, 0xE59F003C, 0xE5814000, 0xEBFFFFD6),
    w(0xE59F1010, 0xE3A00010, 0xE5814000, 0xEBFFFFDE),
    w(0xE1A04000, 0xE1D100B0, 0xE3500002, 0x1A000000),
    w(0xE1A05000, 0xE1D100B0, 0xE3500002, 0x1A000000),
    w(0xE1A04000, 0xE1D100B0, 0xE3500002, 0x0A000006),
    w(0xE1A05000, 0xE1D100B0, 0xE3500002, 0x0A000006),
]

MODPARAMS = w(0xDEC00621, 0x2106C0DE)

def sdk_version(img):
    i = img.find(MODPARAMS)
    return struct.unpack('<I', img[i - 4:i])[0] if i >= 4 else 0

def find_first(img, table):
    for name, sig in table:
        i = img.find(sig)
        if i >= 0:
            return name, i
    return None, -1

def check(images):
    """-> (ok, hook description, reason when not ok)

    `images` is every candidate view of the arm9 binary. A rom's arm9 is
    usually BLZ-compressed but not always, and blz_decompress() happily
    returns garbage for an already-plain binary, so both views are searched
    rather than guessing which one is live.
    """
    if isinstance(images, (bytes, bytearray)):
        images = [images]
    twl = any((sdk_version(i) >> 24) == 5 for i in images)
    arm, thumb = (ROM_ARM, ROM_THUMB) if twl else (CARD_ARM, CARD_THUMB)
    fn = 'CARDi_ReadRomWithCPU' if twl else 'CARDi_ReadCard'

    if not any(sig in img for img in images for sig in RESET):
        return False, '', 'no OS_ResetSystem tail'

    for img in images:
        name, off = find_first(img, arm)
        if off >= 0:
            insn0 = struct.unpack('<I', img[off:off + 4])[0]
            if (insn0 & 0xFFFF0000) != 0xE92D0000:
                # the tables cannot produce this, but the loader enforces it too
                return False, '', f'{fn} entry 0x{insn0:08X} is not an stmfd'
            return True, f'{fn} [{name}]', ''
    for img in images:
        name, off = find_first(img, thumb)
        if off >= 0:
            return False, '', f'{fn} is thumb ({name})'
    return False, '', f'{fn} not found'

def arm9_images(path):
    a9, meta = arm9_of(path)
    if a9 is None:
        return None, meta
    out = [a9]
    dec = blz_decompress(a9)
    if dec and dec != a9:
        out.append(dec)
    return out, meta

def self_test():
    # A hand-built image carrying one reset tail and one ARM card entry must
    # pass; drop either half and it must fail with the matching reason.
    pad = b'\x00' * 64
    reset, card = RESET[0], CARD_ARM[0][1]
    ok, hook, why = check(pad + reset + pad + card + pad)
    assert ok and 'CARDi_ReadCard' in hook, (ok, hook, why)

    ok, _, why = check(pad + card + pad)
    assert not ok and why == 'no OS_ResetSystem tail', why

    ok, _, why = check(pad + reset + pad)
    assert not ok and why == 'CARDi_ReadCard not found', why

    # A thumb card entry is refused by name, not silently treated as missing.
    twl_hdr = pad + MODPARAMS_PREFIX + MODPARAMS
    ok, _, why = check(twl_hdr + reset + pad + ROM_THUMB[0][1] + pad)
    assert not ok and 'is thumb' in why, why
    print('self-test ok')

# sdkVersion sits in the word before the module params magic; 0x05xxxxxx = twl.
MODPARAMS_PREFIX = struct.pack('<I', 0x05047531)

if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == '--self-test':
        self_test(); raise SystemExit(0)
    if len(sys.argv) < 2:
        print(__doc__); raise SystemExit(2)

    good = 0
    for path in sys.argv[1:]:
        imgs, meta = arm9_images(path)
        name = os.path.basename(path)[:44]
        if imgs is None:
            print(f'  ----  {"????":4}  no arm9            {name}')
            continue
        ok, hook, why = check(imgs)
        good += ok
        print(f'  {"EXIT" if ok else "----"}  {meta[1]:4}  {(hook or why):34.34} {name}')
    print(f'\n{good}/{len(sys.argv) - 1} roms will get the exit hook')
