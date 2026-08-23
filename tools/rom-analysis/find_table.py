#!/usr/bin/env python3
"""Extract the arm9 IRQ vector table address each rom's dispatcher reads.

  S+0   e59f1008  ldr r1,[pc,#8]      -> literal at S+16 = IRQ TABLE ADDRESS
  S+4   e7910100  ldr r0,[r1,r0,lsl#2]
  S+8   e59fe004  ldr lr,[pc,#4]      -> literal at S+20 = irq return address
  S+12  e12fff10  bx  r0
"""
import struct, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scan_irqtable import blz_decompress, arm9_of

SIG = struct.pack('<4I', 0xe59f1008, 0xe7910100, 0xe59fe004, 0xe12fff10)
ok = 0
for path in sys.argv[1:]:
    a9, meta = arm9_of(path)
    name = os.path.basename(path)[:40]
    if a9 is None:
        print(f'  --      {name}'); continue
    img = a9 if SIG in a9 else (blz_decompress(a9) or b'')
    i = img.find(SIG)
    if i < 0:
        print(f'  no sig  {meta[1]}  {name}'); continue
    table, ret = struct.unpack('<II', img[i+16:i+24])
    # DS main ram is 0x02000000-0x023FFFFF; dtcm typically 0x027E0000+
    plaus = 'OK ' if 0x02000000 <= table <= 0x02FFFFFF else '?? '
    if plaus == 'OK ': ok += 1
    print(f'  {plaus} table=0x{table:08X} ret=0x{ret:08X}  {meta[1]}  {name}')
print(f'\n{ok}/{len(sys.argv)-1} gave a plausible main-RAM table address')
