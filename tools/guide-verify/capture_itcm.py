#!/usr/bin/env python3
import time, threading, struct
from gdbc import Gdb, show

g = Gdb(port=3333)
print("halt:", g.cmd("?"))

def stop_after(sec):
    time.sleep(sec)
    try: g.s.sendall(b"\x03")
    except: pass

# boot fully to gameplay
threading.Thread(target=stop_after, args=(16,), daemon=True).start()
g.send("c"); g.recv()
r = show(g, "booted")

def w32(m,i): return struct.unpack("<I", m[i:i+4])[0]

# Dump ITCM around the known dispatcher area
print("\n== ITCM 0x01000180..0x01000300 ==")
base = 0x01000180
m = g.read_mem(base, 0x180)
if m:
    for off in range(0, len(m), 16):
        words = " ".join("%08X"%w32(m,off+j) for j in range(0,16,4))
        print("  %08X: %s" % (base+off, words))

# Scan whole 32KB ITCM for the dispatcher signature:
#   sub lr,lr,#4      = E24EE004
#   stmfd sp!,{r0-r3,r12,lr} = E92D500F
print("\n== scan ITCM 0x01000000..0x01008000 for E24EE004 then E92D500F ==")
big = g.read_mem(0x01000000, 0x8000)
hits=[]
if big:
    for off in range(0, len(big)-8, 4):
        if w32(big,off)==0xE24EE004 and w32(big,off+4)==0xE92D500F:
            hits.append(0x01000000+off)
    for h in hits:
        print("  HIT dispatcher prologue at %08X" % h)
    if not hits:
        # looser: any E92D500F
        for off in range(0, len(big)-4, 4):
            if w32(big,off)==0xE92D500F:
                print("  stmfd{r0-r3,r12,lr} at %08X (prev word %08X)" % (0x01000000+off, w32(big,off-4)))

# Full disasm-bytes of the dispatcher (first 0x80 bytes) from the first hit
if hits:
    d = hits[0]
    print("\n== dispatcher bytes @ %08X (0x80) ==" % d)
    m = g.read_mem(d, 0x80)
    for off in range(0, len(m), 4):
        print("  %08X: %08X" % (d+off, w32(m,off)))
