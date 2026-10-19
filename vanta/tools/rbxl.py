import struct, sys, json, lz4.block, zstandard

def rd_chunks(b):
    assert b[:8] == b'<roblox!'
    pos = 32
    while pos < len(b):
        name = b[pos:pos+4]; clen, ulen, _ = struct.unpack('<III', b[pos+4:pos+16]); pos += 16
        if clen == 0:
            data = b[pos:pos+ulen]; pos += ulen
        else:
            raw = b[pos:pos+clen]; pos += clen
            if raw[:4] == b'\x28\xb5\x2f\xfd':
                data = zstandard.ZstdDecompressor().decompress(raw, max_output_size=ulen)
            else:
                data = lz4.block.decompress(raw, uncompressed_size=ulen)
        yield name, data
        if name == b'END\0': break

class R:
    def __init__(s, d): s.d = d; s.p = 0
    def u8(s): v = s.d[s.p]; s.p += 1; return v
    def u32(s): v = struct.unpack('<I', s.d[s.p:s.p+4])[0]; s.p += 4; return v
    def f32(s): v = struct.unpack('<f', s.d[s.p:s.p+4])[0]; s.p += 4; return v
    def string(s): n = s.u32(); v = s.d[s.p:s.p+n]; s.p += n; return v
    def raw(s, n): v = s.d[s.p:s.p+n]; s.p += n; return v
    def deint(s, n, w=4):
        b = s.raw(n*w)
        return [bytes(b[j*n+i] for j in range(w)) for i in range(n)]
    def i32s(s, n):
        out = []
        for x in s.deint(n):
            u = int.from_bytes(x, 'big'); out.append((u >> 1) ^ -(u & 1))
        return out
    def refs(s, n):
        a = s.i32s(n); acc = 0; out = []
        for v in a: acc += v; out.append(acc)
        return out
    def rfloats(s, n):
        out = []
        for x in s.deint(n):
            u = int.from_bytes(x, 'big'); u = (u >> 1) | ((u & 1) << 31)
            out.append(struct.unpack('>f', u.to_bytes(4, 'big'))[0])
        return out

def parse(path):
    b = open(path, 'rb').read()
    classes = {}; inst = {}; sstr = []
    for name, data in rd_chunks(b):
        r = R(data)
        if name == b'INST':
            cid = r.u32(); cname = r.string().decode(); r.u8(); n = r.u32()
            ids = r.refs(n); classes[cid] = (cname, ids)
            for i in ids: inst[i] = {'class': cname, 'props': {}, 'children': [], 'parent': None}
        elif name == b'PROP':
            cid = r.u32(); pname = r.string().decode(); t = r.u8()
            cname, ids = classes[cid]; n = len(ids)
            try:
                if t == 1:
                    for i in ids: inst[i]['props'][pname] = r.string().decode('utf-8', 'replace')
                elif t == 2:
                    for i in ids: inst[i]['props'][pname] = bool(r.u8())
                elif t == 0x0E:
                    xs, ys, zs = r.rfloats(n), r.rfloats(n), r.rfloats(n)
                    for k, i in enumerate(ids): inst[i]['props'][pname] = (round(xs[k],2), round(ys[k],2), round(zs[k],2))
                elif t == 0x10:
                    for i in ids:
                        idb = r.u8()
                        if idb == 0: [r.f32() for _ in range(9)]
                    xs, ys, zs = r.rfloats(n), r.rfloats(n), r.rfloats(n)
                    for k, i in enumerate(ids): inst[i]['props'][pname] = ('CF', round(xs[k],2), round(ys[k],2), round(zs[k],2))
                elif t == 0x13:
                    a = r.refs(n)
                    for k, i in enumerate(ids): inst[i]['props'][pname] = ('ref', a[k])
                elif t == 0x1C:
                    a = [int.from_bytes(x,'big') for x in r.deint(n)]
                    for k, i in enumerate(ids): inst[i]['props'][pname] = ('sstr', a[k])
            except Exception as e:
                pass
        elif name == b'SSTR':
            r.u32(); n = r.u32()
            for _ in range(n): r.raw(16); sstr.append(r.string())
        elif name == b'PRNT':
            r.u8(); n = r.u32(); ch = r.refs(n); pa = r.refs(n)
            for c, p in zip(ch, pa):
                inst[c]['parent'] = p
                if p in inst: inst[p]['children'].append(c)
    for i in inst.values():
        for k, v in list(i['props'].items()):
            if isinstance(v, tuple) and v[0] == 'sstr' and v[1] < len(sstr):
                i['props'][k] = sstr[v[1]].decode('utf-8', 'replace')
    return inst
