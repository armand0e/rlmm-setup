"""Minimal reader/rewriter for uncompressed UE3 packages saved by UDK 2015 (file version 868).

Enough to add names, exports and properties to a package without UDK resaving it (a resave through the dummy
classes can silently drop Rocket League properties). relocate() inserts bytes and moves every offset the package
stores: the summary's table offsets, each export's SerialOffset, thumbnail offsets, and inline bulk data offsets
(UE3 writes BulkDataOffsetInFile as an absolute position and uses it for lazy loading).
"""
import bisect
import struct

PACKAGE_TAG = 0x9E2A83C1
EXPORT_ENTRY_SIZE = 68  # version 868, with no ComponentMap entries and no generation net object counts


class Reader:
    def __init__(self, data, pos=0):
        self.b, self.p = data, pos

    def i32(self):
        v = struct.unpack_from('<i', self.b, self.p)[0]
        self.p += 4
        return v

    def u32(self):
        v = struct.unpack_from('<I', self.b, self.p)[0]
        self.p += 4
        return v

    def u64(self):
        v = struct.unpack_from('<Q', self.b, self.p)[0]
        self.p += 8
        return v

    def fstring(self):
        n = self.i32()
        if n >= 0:
            s = self.b[self.p:self.p + n - 1].decode('latin1') if n else ''
            self.p += n
        else:
            s = self.b[self.p:self.p - n * 2 - 2].decode('utf-16le')
            self.p += -n * 2
        return s


class Package:
    """The summary, name, import and export tables of a package (positions are file offsets)."""

    def __init__(self, data):
        self.b = data
        r = Reader(data)
        tag, ver, self.hdr_size = r.u32(), r.i32(), r.i32()
        if tag != PACKAGE_TAG:
            raise ValueError('not a UE3 package')
        if ver & 0xFFFF != 868:
            raise ValueError('unsupported package version %d (only UDK 2015, 868)' % (ver & 0xFFFF))
        r.fstring()                                   # folder name
        self.flags = r.u32()
        self.pos_counts = r.p                         # NameCount ... DependsOffset (7 ints), then the GUID fields
        self.nc, self.no, self.ec, self.eo, self.ic, self.io, self.do = [r.i32() for _ in range(7)]
        self.iego, self.igc, self.egc = r.i32(), r.i32(), r.i32()   # ImportExportGuids offset and counts
        self.tto = r.i32()                            # ThumbnailTableOffset
        r.p += 16                                     # package GUID
        gc = r.i32()
        self.pos_gens = r.p
        self.gens = [(r.i32(), r.i32(), r.i32()) for _ in range(gc)]   # ExportCount, NameCount, NetObjectCount
        r.p += 8                                      # engine and cooker versions
        compression, chunks = r.i32(), r.i32()
        if compression or chunks:
            raise ValueError('compressed packages are not supported')

        r.p = self.no
        self.names = []                               # (text, flags)
        for _ in range(self.nc):
            s = r.fstring()
            self.names.append((s, r.u64()))
        self.name_end = r.p
        if self.name_end > min(self.io, self.eo):
            raise ValueError('the name table is not the first table; layout not supported')

        r.p = self.io
        self.imports = []                             # (object name, outer index, class name)
        for _ in range(self.ic):
            _, _, cls, _, outer, name, _ = struct.unpack_from('<7i', data, r.p)
            r.p += 28
            self.imports.append((self.names[name][0], outer, self.names[cls][0]))

        r.p = self.eo
        self.exports = []
        for _ in range(self.ec):
            e = {'entry': r.p}
            e['cls'], e['super'], e['outer'], name, number, e['arch'] = struct.unpack_from('<6i', data, r.p)
            e['name'] = self.names[name][0] + ('_%d' % (number - 1) if number else '')
            r.p += 32                                 # the six ints + ObjectFlags
            e['size'], e['off'] = struct.unpack_from('<ii', data, r.p)
            r.p += 8
            components = r.i32()
            r.p += components * 12
            r.p += 4                                  # ExportFlags
            netcounts = r.i32()
            r.p += netcounts * 4 + 16                 # GenerationNetObjectCount, PackageGuid
            self.exports.append(e)
        self.export_end = r.p

        r.p = self.do                                 # depends map: one int array per export
        for _ in range(self.ec):
            r.p += 4 * r.i32()
        self.depends_end = r.p

    def name_index(self, s):
        for i, (text, _) in enumerate(self.names):
            if text == s:
                return i
        return -1

    def object_name(self, index):
        if index < 0:
            return self.imports[-index - 1][0]
        if index > 0:
            return self.exports[index - 1]['name']
        return 'None'

    def class_name(self, export):
        return self.object_name(export['cls']) if export['cls'] else 'Class'

    def properties(self, export, preamble):
        """Tagged properties of an export: (name, type, tag_pos, value_pos, value_size). preamble: bytes before the
        first tag (4 = NetIndex for most objects, 8 for components)."""
        b, names = self.b, self.names
        p, end = export['off'] + preamble, export['off'] + export['size']
        out = []
        while p < end:
            name = names[struct.unpack_from('<i', b, p)[0]][0]
            if name == 'None':
                return out
            typ = names[struct.unpack_from('<i', b, p + 8)[0]][0]
            size = struct.unpack_from('<i', b, p + 16)[0]
            q = p + 24 + (8 if typ in ('StructProperty', 'ByteProperty') else 0)
            vsize = 1 if typ == 'BoolProperty' else size
            out.append((name, typ, p, q, vsize))
            p = q + vsize
        raise ValueError('property list of %s runs past the export' % export['name'])


def name_entry(text, flags):
    s = text.encode('latin1') + b'\x00'
    return struct.pack('<i', len(s)) + s + struct.pack('<Q', flags)


def relocate(pkg, inserts):
    """Applies inserts [(old_position, bytes)] and moves every stored offset. Returns (data, new) where new(old)
    maps an old file position to its new one (bytes at an insertion point move after the inserted bytes).
    Export sizes, counts and new table entries are the caller's job."""
    b = pkg.b
    inserts = sorted(inserts, key=lambda x: x[0])
    starts, shift = [], []
    total = 0
    for pos, data in inserts:
        total += len(data)
        starts.append(pos)
        shift.append(total)

    def new(old):
        k = bisect.bisect_right(starts, old)
        return old + (shift[k - 1] if k else 0)

    out = bytearray()
    last = 0
    for pos, data in inserts:
        out += b[last:pos]
        out += data
        last = pos
    out += b[last:]

    def move_int(old_field_pos, value):
        struct.pack_into('<i', out, new(old_field_pos), value)

    # Summary: it precedes the name table, so its own fields don't move.
    struct.pack_into('<i', out, 8, new(pkg.hdr_size))
    struct.pack_into('<i', out, pkg.pos_counts + 12, new(pkg.eo))
    struct.pack_into('<i', out, pkg.pos_counts + 20, new(pkg.io))
    struct.pack_into('<i', out, pkg.pos_counts + 24, new(pkg.do))
    if pkg.iego:
        struct.pack_into('<i', out, pkg.pos_counts + 28, new(pkg.iego))
    if pkg.tto:
        struct.pack_into('<i', out, pkg.pos_counts + 40, new(pkg.tto))

    for e in pkg.exports:
        move_int(e['entry'] + 36, new(e['off']))

    if pkg.tto:
        r = Reader(b, pkg.tto)
        for _ in range(r.i32()):
            r.fstring()
            r.fstring()
            move_int(r.p, new(r.i32()))

    # Inline bulk data: [flags][element count][size on disk][offset in file == position right after this field].
    for e in pkg.exports:
        start, end = e['off'], e['off'] + e['size']
        q = start + 12
        while q + 4 <= end:
            if struct.unpack_from('<i', b, q)[0] == q + 4 and 0 <= struct.unpack_from('<i', b, q - 4)[0] <= end - q - 4:
                move_int(q, new(q + 4))
            q += 1
    return out, new


def set_counts(out, pkg, names, exports):
    """Writes NameCount and ExportCount to the summary, and to the latest generation when it held the old counts
    (UDK saves the current counts there)."""
    struct.pack_into('<i', out, pkg.pos_counts, names)
    struct.pack_into('<i', out, pkg.pos_counts + 8, exports)
    if pkg.gens and pkg.gens[-1][:2] == (pkg.ec, pkg.nc):
        struct.pack_into('<ii', out, pkg.pos_gens + 12 * (len(pkg.gens) - 1), exports, names)
