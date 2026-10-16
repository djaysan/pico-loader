#!/usr/bin/env python3
"""Predict what the GUIDE_ARENA_PROOF (phase 4 M1) loader does on each rom.

Two questions, both answered offline with the loader's own signatures:

  1. Is there an arm9 arena reservation? OsGetInitArenaHiPatch looks for the
     main-arena high literal (0x023E0000) of OS_GetInitArenaHi by the function's
     last return + that literal. Sdk 2.0 returns it with an immediate mov
     instead, so those roms get no reservation: the arm7 monitor stays silent.
  2. Is the card entry detoured? GuideOverlay9Install needs an ARM entry that
     starts with stmfd, and a second instruction it can replay from the blob
     (sub sp / mov rd,rm / ldr rd,[pc,#imm]). Otherwise the blob is still
     placed and the residency tone still plays, but nothing runs from it.

Usage:  check_arena_hi.py rom.nds [rom.nds ...]
        check_arena_hi.py --self-test
"""
import struct, sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_exit_hook import (CARD_ARM, CARD_THUMB, ROM_ARM, ROM_THUMB, MODPARAMS,
                             find_first, sdk_version, arm9_images, w)

# Copied from OsGetInitArenaHiPatch.cpp; the literal is the 4th word.
ARENA_HI = [
    w(0xE28DD004, 0xE8BD4000, 0xE12FFF1E, 0x023E0000),  # sdk 2.1-4
    w(0xE8BD8008, 0xE3A00000, 0xE8BD8008, 0x023E0000),  # sdk 4-5
    w(0xBD084808, 0xBD084808, 0xBD082000, 0x023E0000),  # thumb
]

def find_aligned(img, sig):
    # fastSearch16 walks words, so only 4-aligned matches count
    i = img.find(sig)
    while i >= 0 and i % 4:
        i = img.find(sig, i + 1)
    return i

def replayable(insn1):
    # Same whitelist as RelocateCardInstruction1 in GuideOverlay9.cpp.
    rd = (insn1 >> 12) & 0xF
    return ((insn1 & 0xFFFFF000) == 0xE24DD000
            or ((insn1 & 0xFFFF0FF0) == 0xE1A00000 and rd != 15 and (insn1 & 0xF) != 15)
            or ((insn1 & 0xFFFF0000) == 0xE59F0000 and rd != 15))

def predict(images):
    """-> (reserved, detoured, note)"""
    if isinstance(images, (bytes, bytearray)):
        images = [images]
    reserved = any(find_aligned(img, sig) >= 0 for img in images for sig in ARENA_HI)
    if not reserved:
        return False, False, 'no arena-hi literal (sdk 2.0?)'
    twl = any((sdk_version(i) >> 24) == 5 for i in images)
    arm, thumb = (ROM_ARM, ROM_THUMB) if twl else (CARD_ARM, CARD_THUMB)
    for img in images:
        name, off = find_first(img, arm)
        if off >= 0:
            insn0, insn1 = struct.unpack_from('<2I', img, off)
            if (insn0 & 0xFFFF0000) == 0xE92D0000 and replayable(insn1):
                return True, True, f'card [{name}]'
            return True, False, f'card insn 0x{insn0:08X} 0x{insn1:08X} not replayable'
    for img in images:
        name, _ = find_first(img, thumb)
        if name:
            # sdk 2-4: the loader's own blx into its card patch is repointed
            # at guide_tramp_call. Twl thumb (CARDi_ReadRomWithCPU): no hook yet.
            return True, not twl, f'thumb card entry ({name})'
    return True, False, 'card entry not found'

def self_test():
    pad = b'\x00' * 64
    hi = ARENA_HI[0]
    sdk2_card = CARD_ARM[1][1]             # insn1 = sub sp, sp, #4
    sdk4_card = CARD_ARM[5][1]             # insn1 = ldr r4, [pc, #0xD8]
    assert predict(pad + hi + pad + sdk2_card + pad)[:2] == (True, True)
    assert predict(pad + hi + pad + sdk4_card + pad)[:2] == (True, True)
    # no literal -> no reservation, whatever the card entry is
    assert predict(pad + sdk2_card + pad)[:2] == (False, False)
    # the OS_GetInitArenaLo pool holds 0x023E0000 too, but not after a return
    lo_pool = w(0x021901E0, 0x02094510, 0x023E0000, 0x01FFFFA0)
    assert predict(pad + lo_pool + pad + sdk2_card + pad)[:2] == (False, False)
    # a misaligned copy is not what the loader's word search finds
    assert predict(pad + b'\x00\x00' + hi + pad)[:2] == (False, False)
    # twl thumb card entry: reserved but not hooked
    twl = pad + struct.pack('<I', 0x05047531) + MODPARAMS
    ok, det, note = predict(twl + hi + pad + ROM_THUMB[0][1] + pad)
    assert ok and not det and 'thumb' in note, note
    # sdk 2-4 thumb card entry: hooked through the loader's own call
    ok, det, note = predict(pad + hi + pad + CARD_THUMB[0][1] + pad)
    assert ok and det and 'thumb' in note, note
    # an unreplayable second instruction (a branch) is refused
    bad = w(0xE92D4070, 0xEB000010, 0xE1A06000, 0xE3A00C02)
    assert predict(pad + hi + pad + bad + pad)[:2] == (True, False)
    print('self-test ok')

if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == '--self-test':
        self_test(); raise SystemExit(0)
    if len(sys.argv) < 2:
        print(__doc__); raise SystemExit(2)

    for path in sys.argv[1:]:
        imgs, meta = arm9_images(path)
        name = os.path.basename(path)[:40]
        if imgs is None:
            print(f'  ----  ????  no arm9  {name}'); continue
        reserved, detoured, note = predict(imgs)
        tone = ('HIGH' if reserved else 'none')
        what = 'hooked + residency' if detoured else ('residency only' if reserved else 'silent')
        print(f'  {tone}  {meta[1]:4}  {what:18}  {note:42.42} {name}')
