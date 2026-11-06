"""Set MaxCaptureTime on every SceneCaptureCubeMapComponent of a UE3 (UDK, version 868) map package.

The package is rewritten byte for byte except for:
  * one new name-table entry ("MaxCaptureTime") when the package lacks it,
  * one FloatProperty tag (28 bytes) inserted into each cubemap component that lacks the property
    (an existing value is overwritten in place),
  * every file offset that moves because of those insertions: summary offsets, export SerialOffset /
    SerialSize, thumbnail offsets, and inline bulk-data offsets (BulkDataOffsetInFile), which UE3 stores as
    absolute positions and uses for lazy loading.

Usage: patch_cubemap.py IN.umap OUT.umap [value]
"""
import struct, sys, bisect

VALUE = 2.0


class Pkg:
    def __init__(self, b):
        self.b = b
        r = Reader(b)
        self.tag, self.ver, self.hdr_size = r.i32(), r.i32(), r.i32()
        if self.tag != 0x9E2A83C1 & 0xFFFFFFFF and self.tag != -1641380927:
            raise SystemExit('not a UE3 package')
        if self.ver & 0xFFFF != 868:
            raise SystemExit('unexpected package version %d' % (self.ver & 0xFFFF))
        r.fstring()
        self.pos_flags = r.p
        self.flags = r.u32()
        self.pos_counts = r.p
        self.nc, self.no, self.ec, self.eo, self.ic, self.io, self.do = [r.i32() for _ in range(7)]
        self.iego, self.igc, self.egc = r.i32(), r.i32(), r.i32()
        self.tto = r.i32()
        r.p += 16  # guid
        gc = r.i32()
        self.pos_gens = r.p
        self.gens = [(r.i32(), r.i32(), r.i32()) for _ in range(gc)]
        self.engine, self.cooker = r.i32(), r.i32()
        self.compression = r.i32()
        nch = r.i32()
        if self.compression or nch:
            raise SystemExit('compressed packages are not supported')
        # names
        r.p = self.no
        self.names = []
        for _ in range(self.nc):
            start = r.p
            s = r.fstring()
            fl = r.u64()
            self.names.append((s, fl, start, r.p))
        self.name_end = r.p
        if self.name_end > self.io or self.name_end > self.eo:
            raise SystemExit('name table is not first; layout not supported')
        # imports
        r.p = self.io
        self.imports = []
        for _ in range(self.ic):
            cp, cpn, cl, cln, outer, on, onum = struct.unpack_from('<iiiiiii', b, r.p)
            r.p += 28
            self.imports.append((self.names[on][0], outer, self.names[cl][0]))
        # exports
        r.p = self.eo
        self.exports = []
        for _ in range(self.ec):
            e = {}
            e['cls'], e['sup'], e['outer'], on, onum, e['arch'] = struct.unpack_from('<iiiiii', b, r.p)
            e['name'] = self.names[on][0] + ('_%d' % (onum - 1) if onum else '')
            r.p += 24 + 8
            e['pos_size'] = r.p
            e['size'], e['off'] = struct.unpack_from('<ii', b, r.p)
            r.p += 8
            ncm = r.i32(); r.p += ncm * 12
            r.p += 4
            ngen = r.i32(); r.p += ngen * 4
            r.p += 16
            self.exports.append(e)
        self.export_end = r.p

    def name_index(self, s):
        for i, n in enumerate(self.names):
            if n[0] == s:
                return i
        return -1

    def class_name(self, e):
        c = e['cls']
        if c < 0:
            return self.imports[-c - 1][0]
        if c > 0:
            return self.exports[c - 1]['name']
        return 'Class'


class Reader:
    def __init__(self, b):
        self.b, self.p = b, 0

    def i32(self):
        v = struct.unpack_from('<i', self.b, self.p)[0]; self.p += 4; return v

    def u32(self):
        v = struct.unpack_from('<I', self.b, self.p)[0]; self.p += 4; return v

    def u64(self):
        v = struct.unpack_from('<Q', self.b, self.p)[0]; self.p += 8; return v

    def fstring(self):
        n = self.i32()
        if n >= 0:
            s = self.b[self.p:self.p + n - 1].decode('latin1') if n else ''; self.p += n
        else:
            s = self.b[self.p:self.p - n * 2 - 2].decode('utf-16le'); self.p += -n * 2
        return s


def walk_props(pkg, start, end):
    """Yields (name, type, tag_pos, value_pos, value_size) for a tagged property stream."""
    b, names = pkg.b, pkg.names
    p = start
    while p < end:
        ni = struct.unpack_from('<i', b, p)[0]
        nm = names[ni][0]
        if nm == 'None':
            return
        t = names[struct.unpack_from('<i', b, p + 8)[0]][0]
        size = struct.unpack_from('<i', b, p + 16)[0]
        q = p + 24
        if t in ('StructProperty', 'ByteProperty'):
            q += 8
        vs = 1 if t == 'BoolProperty' else size
        yield nm, t, p, q, vs
        p = q + vs
    raise ValueError('property stream overran export')


def main():
    src, dst = sys.argv[1], sys.argv[2]
    value = float(sys.argv[3]) if len(sys.argv) > 3 else VALUE
    b = open(src, 'rb').read()
    pkg = Pkg(b)
    float_idx = pkg.name_index('FloatProperty')
    if float_idx < 0:
        raise SystemExit('package has no FloatProperty name')
    mct_idx = pkg.name_index('MaxCaptureTime')
    add_name = mct_idx < 0
    if add_name:
        mct_idx = pkg.nc
    fbytes = struct.pack('<f', value)

    # Edits in OLD-file coordinates: (pos, bytes_to_insert) or overwrite (pos, bytes)
    inserts = []      # (old_pos, data)
    overwrites = []   # (old_pos, data)
    grown = {}        # export index -> extra bytes
    found = 0
    for i, e in enumerate(pkg.exports):
        if pkg.class_name(e) != 'SceneCaptureCubeMapComponent':
            continue
        found += 1
        props = list(walk_props(pkg, e['off'] + 8, e['off'] + e['size']))
        have = [x for x in props if x[0] == 'MaxCaptureTime']
        if have:
            overwrites.append((have[0][3], fbytes))
            print('  %s.%s: MaxCaptureTime overwritten' % (pkg.exports[e['outer'] - 1]['name'], e['name']))
            continue
        after = [x for x in props if x[0] in ('FarPlane', 'NearPlane', 'TextureTarget')]
        at = (after[-1][3] + after[-1][4]) if after else props[0][2] if props else e['off'] + 8
        tag = struct.pack('<iiiiii', mct_idx, 0, float_idx, 0, 4, 0) + fbytes
        inserts.append((at, tag))
        grown[i] = len(tag)
        print('  %s.%s: MaxCaptureTime added' % (pkg.exports[e['outer'] - 1]['name'], e['name']))
    if not found:
        raise SystemExit('no SceneCaptureCubeMapComponent in this package')

    if add_name:
        flags = pkg.names[pkg.name_index('FarPlane')][1]
        s = b'MaxCaptureTime\x00'
        inserts.append((pkg.name_end, struct.pack('<i', len(s)) + s + struct.pack('<Q', flags)))
    if not inserts and not overwrites:
        shutil_copy(src, dst); return

    inserts.sort(key=lambda x: x[0])
    ins_pos = [x[0] for x in inserts]
    cum = []
    tot = 0
    for _, d in inserts:
        tot += len(d); cum.append(tot)

    def new(old, inclusive=False):
        """New position of the byte at OLD position. An insertion at position p shifts bytes at p and after
        (the inserted bytes come first), so a byte AT an insertion point moves."""
        k = bisect.bisect_right(ins_pos, old)
        return old + (cum[k - 1] if k else 0)

    out = bytearray()
    last = 0
    for p, d in inserts:
        out += b[last:p]; out += d; last = p
    out += b[last:]
    for p, d in overwrites:
        np_ = new(p); out[np_:np_ + len(d)] = d

    def put(pos_old, v):
        struct.pack_into('<i', out, new(pos_old), v)

    # Summary (lives before the name table, so its own position does not move)
    struct.pack_into('<i', out, 8, new(pkg.hdr_size))
    vals = [pkg.nc + (1 if add_name else 0), pkg.no, pkg.ec, new(pkg.eo), pkg.ic, new(pkg.io), new(pkg.do)]
    struct.pack_into('<7i', out, pkg.pos_counts, *vals)
    struct.pack_into('<i', out, pkg.pos_counts + 28, new(pkg.iego) if pkg.iego else 0)
    struct.pack_into('<i', out, pkg.pos_counts + 40, new(pkg.tto) if pkg.tto else 0)
    if add_name and pkg.gens and pkg.gens[-1][1] == pkg.nc:
        struct.pack_into('<i', out, pkg.pos_gens + 12 * (len(pkg.gens) - 1) + 4, pkg.nc + 1)

    # Export table
    for i, e in enumerate(pkg.exports):
        size = e['size'] + grown.get(i, 0)
        noff = new(e['off'])
        # an insertion exactly at an export's first byte belongs to that export only if we grew it there
        put(e['pos_size'], size)
        struct.pack_into('<i', out, new(e['pos_size']) + 4, noff)

    # Thumbnails
    if pkg.tto:
        r = Reader(b); r.p = pkg.tto
        n = r.i32()
        for _ in range(n):
            r.fstring(); r.fstring()
            pos = r.p; off = r.i32()
            put(pos, new(off))

    # Inline bulk data: [flags][elementcount][sizeondisk][offsetinfile == position after this field]
    fixed = 0
    for e in pkg.exports:
        s, end = e['off'], e['off'] + e['size']
        q = s + 12
        while q + 4 <= end:
            if struct.unpack_from('<i', b, q)[0] == q + 4:
                sz = struct.unpack_from('<i', b, q - 4)[0]
                if 0 <= sz <= end - (q + 4):
                    put(q, new(q + 4))
                    fixed += 1
            q += 1
    open(dst, 'wb').write(out)
    print('  %d bytes inserted, %d bulk-data offsets moved' % (tot, fixed))


def shutil_copy(a, c):
    open(c, 'wb').write(open(a, 'rb').read())


if __name__ == '__main__':
    main()
