#!/usr/bin/env python3
"""Extract the arm9 IRQ vector table address each rom's dispatcher reads.

Same search as FindIrqTable in arm9/source/patches/arm9/guide/GuideOverlay9.cpp
(GUIDE_IPC_FREEZE), so a table found here is a game the M2 hook can install on.

Classic tail (sdk 2-5):
  S+0   e59f1008  ldr r1,[pc,#8]      -> literal at S+16 = IRQ TABLE ADDRESS
  S+4   e7910100  ldr r0,[r1,r0,lsl#2]
  S+8   e59fe004  ldr lr,[pc,#4]      -> literal at S+20 = irq return address
  S+12  e12fff10  bx  r0

Twl sdk 5 head (Golden Sun: Dark Dawn), indexed down from table[31]:
  S+0   e3a0c301  mov r12,#0x04000000
  S+4   e5bc2208  ldr r2,[r12,#0x208]!
  S+8   e1ec00d8  ldrd r0,[r12,#8]!
  S+12  e3520000  cmp r2,#0
  S+24  159fe...  ldrne lr,[pc,#imm]  -> literal = &table[31]
  S+40  171ee100  ldrne lr,[lr,-r0,lsl#2]   (r0 = clz(bit) = 31 - bit)
"""
import struct, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scan_irqtable import blz_decompress, arm9_of

SIG = struct.pack('<4I', 0xe59f1008, 0xe7910100, 0xe59fe004, 0xe12fff10)
SIG5 = struct.pack('<4I', 0xe3a0c301, 0xe5bc2208, 0xe1ec00d8, 0xe3520000)

def find_table(img):
    """Return (table, how) or (None, None). Word aligned, like fastSearch16."""
    for sig in (SIG, SIG5):
        i = img.find(sig)
        while i >= 0 and i % 4:
            i = img.find(sig, i + 1)
        if i < 0:
            continue
        w = lambda o: struct.unpack_from('<I', img, i + o)[0]
        if sig is SIG:
            return w(16), 'tail'
        if (w(24) & 0xFFFFF000) == 0x159FE000 and w(40) == 0x171EE100:
            return w(24 + 8 + (w(24) & 0xFFF)) - 31 * 4, 'sdk5'
    return None, None

ok = 0
for path in sys.argv[1:]:
    a9, meta = arm9_of(path)
    name = os.path.basename(path)[:40]
    if a9 is None:
        print(f'  --      {name}'); continue
    table, how = find_table(a9)
    if table is None:
        table, how = find_table(blz_decompress(a9) or b'')
    if table is None:
        print(f'  no sig  {meta[1]}  {name}'); continue
    # Same guard as the loader: OS_IRQTable lives in dtcm.
    plaus = 'OK ' if 0x027C0000 <= table < 0x02800000 else '?? '
    if plaus == 'OK ': ok += 1
    print(f'  {plaus} table=0x{table:08X} ({how})  {meta[1]}  {name}')
print(f'\n{ok}/{len(sys.argv)-1} gave a dtcm table address the loader accepts')
