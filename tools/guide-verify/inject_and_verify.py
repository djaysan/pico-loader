#!/usr/bin/env python3
import time, threading, struct, sys
from gdbc import Gdb, show

BASE=0x01006400
DATA=BASE+0xB4
DISP=0x010001D8
blob=open("_inject.bin","rb").read()
print("blob %d bytes, base %08X, guide_data %08X"%(len(blob),BASE,DATA))

g=Gdb(port=3333)
print("halt:",g.cmd("?"))

def write_mem(addr, data):
    # chunked M packets
    i=0
    while i<len(data):
        chunk=data[i:i+0x80]
        hexd="".join("%02x"%b for b in chunk)
        r=g.cmd("M%x,%x:%s"%(addr+i,len(chunk),hexd))
        if not r.startswith("OK"):
            print("  write FAIL @%08X: %r"%(addr+i,r)); return False
        i+=0x80
    return True
def rd32(a):
    m=g.read_mem(a,4); return struct.unpack("<I",m)[0] if m else None
def rd16(a):
    m=g.read_mem(a,2); return struct.unpack("<H",m)[0] if m else None
def intr(s):
    time.sleep(s)
    try: g.s.sendall(b"\x03")
    except: pass

# boot to gameplay
threading.Thread(target=intr,args=(15,),daemon=True).start()
g.send("c"); g.recv(); show(g,"booted")

# confirm dispatcher intact
m=g.read_mem(DISP,8)
print("dispatcher pre-patch: %08X %08X"%(struct.unpack("<I",m[0:4])[0],struct.unpack("<I",m[4:8])[0]))

# 1) inject overlay
ok=write_mem(BASE, blob)
back=g.read_mem(BASE,16)
print("inject overlay ok=%s, readback: %s"%(ok, back.hex() if back else "n/a"))

# 2) patch dispatcher: ldr pc,[pc,#-4]; .word BASE
write_mem(DISP, struct.pack("<II",0xE51FF004,BASE))
m=g.read_mem(DISP,8)
print("dispatcher post-patch: %08X %08X (expect E51FF004 %08X)"%(
    struct.unpack("<I",m[0:4])[0],struct.unpack("<I",m[4:8])[0],BASE))

# 3) BP on overlay to confirm it fires
print("\nbp overlay 0x%08X:"%BASE, g.set_bp(BASE))
threading.Thread(target=intr,args=(4,),daemon=True).start()
g.send("c"); rep=g.recv(); r=g.regs(); pc=r[15] if len(r)>=16 else 0
print("overlay BP: rep=%r PC=%08X -> %s"%(rep,pc,"FIRES" if pc==BASE else "not hit"))
g.del_bp(BASE)

# 4) prove per-frame: read frameCount twice across ~1s
f1=rd32(DATA+0x00)
threading.Thread(target=intr,args=(1.0,),daemon=True).start(); g.send("c"); g.recv()
f2=rd32(DATA+0x00)
print("\nframeCount: %d -> %d (delta %d over ~1s) %s"%(f1,f2,f2-f1,"PER-FRAME OK" if f2>f1 else "NOT FIRING"))

# 5) freeze proof via forceFreeze flag
print("\n--- freeze test (forceFreeze=1) ---")
write_mem(DATA+0x14, struct.pack("<I",1))
threading.Thread(target=intr,args=(1.0,),daemon=True).start(); g.send("c"); g.recv()
mbA=rd16(0x0400006C); mbB=rd16(0x0400106C)
fz=rd32(DATA+0x04); fc_frozen1=rd32(DATA+0x00)
print("MASTER_BRIGHT A=%04X B=%04X (expect 8010), freezeCount=%d"%(mbA,mbB,fz))
threading.Thread(target=intr,args=(1.0,),daemon=True).start(); g.send("c"); g.recv()
fc_frozen2=rd32(DATA+0x00)
print("frameCount during freeze: %d -> %d (%s)"%(fc_frozen1,fc_frozen2,
      "FROZEN (stopped advancing)" if fc_frozen2==fc_frozen1 else "still advancing"))
print("saved A=%04X B=%04X"%(rd16(DATA+0x0C+0) or 0, rd16(DATA+0x10) or 0))

# 6) release
print("\n--- release (forceFreeze=0) ---")
write_mem(DATA+0x14, struct.pack("<I",0))
threading.Thread(target=intr,args=(1.0,),daemon=True).start(); g.send("c"); g.recv()
mbA2=rd16(0x0400006C); mbB2=rd16(0x0400106C)
f3=rd32(DATA+0x00)
print("MASTER_BRIGHT A=%04X B=%04X (restored), frameCount now %d (resumed=%s)"%(
    mbA2,mbB2,f3,"YES" if f3>fc_frozen2 else "no"))
print("\nsummary: savedA=%08X savedB=%08X lastKeys=%08X"%(rd32(DATA+0x0C),rd32(DATA+0x10),rd32(DATA+0x08)))
