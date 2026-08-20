#!/usr/bin/env python3
"""Minimal GDB Remote Serial Protocol client for melonDS's ARM9 stub.
melonDS sends an initial packet on connect and expects a '+' ack first."""
import socket, struct, time

class Gdb:
    def __init__(self, host="127.0.0.1", port=3333, timeout=20):
        self.s = socket.create_connection((host, port), timeout=timeout)
        self.s.settimeout(timeout)
        self.buf = b""
        self.s.sendall(b"+")           # initial ack melonDS is waiting for
        # drain any greeting packet(s) it sends
        self._drain_initial()

    def _rb(self):
        while not self.buf:
            data = self.s.recv(4096)
            if not data: raise EOFError
            self.buf += data
        b, self.buf = self.buf[:1], self.buf[1:]
        return b

    def _drain_initial(self):
        self.s.settimeout(1.0)
        try:
            while True:
                b = self._rb()
                if b == b"$":
                    self._read_body(); self.s.sendall(b"+")
        except (socket.timeout, EOFError):
            pass
        self.s.settimeout(20)

    def _read_body(self):
        body = b""
        while True:
            b = self._rb()
            if b == b"#": break
            body += b
        self._rb(); self._rb()  # 2 checksum hex digits
        return body

    def send(self, cmd):
        pkt = cmd.encode() if isinstance(cmd, str) else cmd
        csum = sum(pkt) & 0xff
        self.s.sendall(b"$" + pkt + b"#" + b"%02x" % csum)

    def recv(self):
        while True:
            b = self._rb()
            if b == b"$": break
            # '+'/'-' acks ignored
        body = self._read_body()
        self.s.sendall(b"+")
        return body.decode(errors="replace")

    def cmd(self, c):
        self.send(c)
        return self.recv()

    def regs(self):
        r = self.cmd("g")
        n = len(r)//8
        return [struct.unpack("<I", bytes.fromhex(r[i*8:i*8+8]))[0] for i in range(n)]

    def read_mem(self, addr, length):
        r = self.cmd("m%x,%x" % (addr, length))
        if r.startswith("E") or not r: return None
        return bytes.fromhex(r)

    def set_bp(self, addr, kind=4): return self.cmd("Z0,%x,%x" % (addr, kind))
    def del_bp(self, addr, kind=4): return self.cmd("z0,%x,%x" % (addr, kind))
    def cont(self):  return self.cmd("c")
    def step(self):  return self.cmd("s")

def show(g, label):
    r = g.regs()
    if len(r) < 16:
        print(f"{label}: short regs {[hex(x) for x in r]}"); return None
    names = "r0 r1 r2 r3 r4 r5 r6 r7 r8 r9 r10 r11 r12".split()
    print(f"{label}: PC={r[15]:08X} LR={r[14]:08X} SP={r[13]:08X} CPSR={r[16] if len(r)>16 else 0:08X}")
    print("   " + " ".join("%s=%08X"%(n,v) for n,v in zip(names, r[:13])))
    return r
