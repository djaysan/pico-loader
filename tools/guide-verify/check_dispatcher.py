#!/usr/bin/env python3
import time, threading, struct
from gdbc import Gdb, show
g=Gdb(port=3333); print("halt:",g.cmd("?"))
def w32(m,i): return struct.unpack("<I",m[i:i+4])[0]
def intr(s):
    time.sleep(s)
    try: g.s.sendall(b"\x03")
    except: pass
# boot
threading.Thread(target=intr,args=(16,),daemon=True).start()
g.send("c"); g.recv(); show(g,"booted")

# 1) is the game alive? BP dispatcher
print("\nbp dispatcher 0x010001D8:", g.set_bp(0x010001D8))
threading.Thread(target=intr,args=(4,),daemon=True).start()
g.send("c"); rep=g.recv(); r=g.regs(); pc=r[15] if len(r)>=16 else 0
alive = (pc==0x010001D8)
print("  dispatcher BP: rep=%r PC=%08X -> %s"%(rep,pc,"ALIVE" if alive else "not hit"))
g.del_bp(0x010001D8)

# 2) dispatcher bytes now
m=g.read_mem(0x010001D8,8)
print("\ndispatcher @010001D8: %08X %08X (%s)"%(w32(m,0),w32(m,4),
      "PATCHED by installer" if w32(m,0)==0xE51FF004 else "unpatched"))

# 3) scan whole ITCM for E51FF004 (my install marker) anywhere
print("\nscan ITCM 0x01000000..0x01008000 for E51FF004:")
hits=[]
a=0x01000000
while a<0x01008000:
    mm=g.read_mem(a,0x200)
    if mm:
        for off in range(0,len(mm)-4,4):
            if w32(mm,off)==0xE51FF004: hits.append(a+off)
    a+=0x200
print("  E51FF004 in ITCM at:", [hex(x) for x in hits] if hits else "none")

# 4) scan main RAM for the guide blob (installer consts) to see if it survived anywhere
sig=struct.pack("<III",0xE24EE004,0xE92D500F,0xE51FF004)
found=None; a=0x02000000
while a<0x02400000 and not found:
    mm=g.read_mem(a,0x200)
    if mm and mm.find(sig)>=0: found=a+mm.find(sig)
    a+=0x1F0
print("guide blob (installer consts) in main RAM:", hex(found) if found else "NOT FOUND")
