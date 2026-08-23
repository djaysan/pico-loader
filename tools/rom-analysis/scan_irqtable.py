#!/usr/bin/env python3
"""Scan NDS roms for the arm9 IRQ-dispatcher tail that nds-bootstrap hooks.

The tail loads the IRQ vector TABLE address from its literal pool, indexes it by
irq number and branches. If it is present we can repoint one table entry instead
of patching the (runtime-built, ITCM-resident) dispatcher code.
The arm9 binary is usually BLZ-compressed, so a raw search alone under-reports.
"""
import struct, sys, os

SIGS = {
  'handlerEndSig':    bytes.fromhex('0810 9fe5'.replace(' ','')) + bytes.fromhex('000191e7') + bytes.fromhex('04e09fe5') + bytes.fromhex('10ff2fe1'),
  'handlerStartSig':  struct.pack('<4I', 0xe3a0c301, 0xe28cce21, 0xe51c1008, 0xe14f0000),
  'handlerEndSigAlt': struct.pack('<4I', 0xe8bd5003, 0xe14c10b8, 0xe169f000, 0xe12fff1e),
  'handlerStartAlt5': struct.pack('<4I', 0xe3a0c301, 0xe5bc2208, 0xe1ec00d8, 0xe3520000),
}

def blz_decompress(data):
    """BLZ / MIi_UncompressBackward - the arm9 binary's backwards LZ."""
    if len(data) < 8:
        return None
    footer = data[-8:]
    extra = struct.unpack('<I', footer[4:8])[0]
    hdr_and_cmp = struct.unpack('<I', footer[0:4])[0]
    hdr_size = hdr_and_cmp >> 24
    cmp_len = hdr_and_cmp & 0xFFFFFF
    if hdr_size < 8 or hdr_size > 0x20 or cmp_len == 0 or cmp_len > len(data):
        return None
    out = bytearray(data)
    out += b'\x00' * extra
    src = len(data) - hdr_size
    dst = len(data) + extra
    end = len(data) - cmp_len
    try:
        while src > end and dst > 0:
            src -= 1; flags = out[src]
            for i in range(8):
                if src <= end or dst <= 0:
                    break
                if flags & 0x80:
                    src -= 1; b1 = out[src]
                    src -= 1; b2 = out[src]
                    length = (b1 >> 4) + 3
                    disp = (((b1 & 0xF) << 8) | b2) + 3
                    for _ in range(length):
                        if dst <= 0: break
                        out[dst-1] = out[dst-1+disp]; dst -= 1
                else:
                    src -= 1
                    out[dst-1] = out[src]; dst -= 1
                flags = (flags << 1) & 0xFF
    except IndexError:
        return None
    return bytes(out)

def arm9_of(path):
    with open(path,'rb') as f:
        hdr = f.read(0x200)
        if len(hdr) < 0x200: return None, None
        off, _entry, _ram, size = struct.unpack('<IIII', hdr[0x20:0x30])
        title = hdr[0:12].rstrip(b'\x00').decode('ascii','replace')
        code  = hdr[12:16].decode('ascii','replace')
        if off == 0 or size == 0 or size > 8*1024*1024: return None, (title, code)
        f.seek(off); return f.read(size), (title, code)

def main(paths):
    rows=[]
    for path in paths:
        a9, meta = arm9_of(path)
        name = os.path.basename(path)
        if a9 is None:
            rows.append((name, meta[1] if meta else '????', 'no arm9', '-')); continue
        found, how = None, 'raw'
        for k,s in SIGS.items():
            if s in a9: found = k; break
        if not found:
            d = blz_decompress(a9)
            if d:
                how='blz'
                for k,s in SIGS.items():
                    if s in d: found = k; break
        rows.append((name, meta[1], found or 'MISS', how))

    hits = sum(1 for r in rows if r[2] != 'MISS' and r[2] != 'no arm9')
    for n,c,f,h in rows:
        print(f'  {"HIT " if f not in ("MISS","no arm9") else "MISS"}  {c}  {f:16} {h:4} {n[:52]}')
    print(f'\n{hits}/{len(rows)} roms carry the hookable dispatcher tail')

# guarded so the other tools here can import blz_decompress / arm9_of
if __name__ == '__main__':
    main(sys.argv[1:])
