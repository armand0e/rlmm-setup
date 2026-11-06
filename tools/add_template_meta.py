"""Add TemplateMapMetadata entries to UDK's MapTemplateIndex.upk so File > New Level lists more templates.

Each new entry copies an existing entry's tagged properties (its Thumbnail), so new templates reuse that thumbnail.
Usage: add_template_meta.py IN.upk OUT.upk COPY_FROM=NEW_NAME [COPY_FROM=NEW_NAME ...]
  e.g. add_template_meta.py MapTemplateIndex.upk out.upk Template_Soccar=Template_Mannfield Template_Soccar=Template_Dropshot
"""
import struct, sys, bisect, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patch_cubemap import Pkg, Reader

EXPORT_ENTRY = 68  # version 868: no ComponentMap entries, no generation net counts


def main():
    src, dst = sys.argv[1], sys.argv[2]
    pairs = [a.split('=', 1) for a in sys.argv[3:]]
    b = open(src, 'rb').read()
    pkg = Pkg(b)
    if pkg.export_end > pkg.do:
        raise SystemExit('export table is not followed by the depends map')
    # depends map: one TArray<int> per export
    r = Reader(b); r.p = pkg.do
    for _ in range(pkg.ec):
        n = r.i32(); r.p += 4 * n
    depends_end = r.p

    exports_by_name = {e['name']: (i, e) for i, e in enumerate(pkg.exports)}
    new_names, new_entries, new_data = [], [], []
    name_count = pkg.nc
    data_tail = len(b)
    for copy_from, new_name in pairs:
        if new_name in exports_by_name:
            print('  %s already listed' % new_name); continue
        i, e = exports_by_name[copy_from]
        idx = pkg.name_index(new_name)
        if idx < 0:
            idx = name_count; name_count += 1
            s = new_name.encode('latin1') + b'\x00'
            flags = pkg.names[pkg.name_index(copy_from)][1]
            new_names.append(struct.pack('<i', len(s)) + s + struct.pack('<Q', flags))
        entry = bytearray(b[pkg.eo + EXPORT_ENTRY * i: pkg.eo + EXPORT_ENTRY * (i + 1)])
        if pkg.export_end - pkg.eo != EXPORT_ENTRY * pkg.ec or struct.unpack_from('<i', entry, 12)[0] != pkg.name_index(copy_from):
            raise SystemExit('export table layout mismatch')
        struct.pack_into('<ii', entry, 12, idx, 0)            # ObjectName
        data = struct.pack('<i', -1) + b[e['off'] + 4: e['off'] + e['size']]   # NetIndex = INDEX_NONE, same properties
        new_entries.append((entry, data))
        print('  %s -> %s (thumbnail copied from %s)' % (copy_from, new_name, copy_from))
    if not new_entries:
        open(dst, 'wb').write(b); return

    names_blob = b''.join(new_names)
    entries_blob_len = EXPORT_ENTRY * len(new_entries)
    depends_blob = struct.pack('<i', 0) * len(new_entries)
    inserts = [(pkg.name_end, len(names_blob)), (pkg.export_end, entries_blob_len), (depends_end, len(depends_blob))]
    ins_pos = [p for p, _ in inserts]
    cum = []; t = 0
    for _, n in inserts:
        t += n; cum.append(t)

    def new(old):
        k = bisect.bisect_right(ins_pos, old)
        return old + (cum[k - 1] if k else 0)

    out = bytearray()
    out += b[:pkg.name_end] + names_blob
    out += b[pkg.name_end:pkg.export_end] + b'\x00' * entries_blob_len
    out += b[pkg.export_end:depends_end] + depends_blob
    out += b[depends_end:]
    # new export data at the end of the file
    entry_pos = new(pkg.export_end) - entries_blob_len
    for k, (entry, data) in enumerate(new_entries):
        struct.pack_into('<ii', entry, 32, len(data), len(out))   # SerialSize, SerialOffset
        out[entry_pos + EXPORT_ENTRY * k: entry_pos + EXPORT_ENTRY * (k + 1)] = entry
        out += data

    struct.pack_into('<i', out, 8, new(pkg.hdr_size))
    ec = pkg.ec + len(new_entries)
    struct.pack_into('<7i', out, pkg.pos_counts, name_count, pkg.no, ec, new(pkg.eo), pkg.ic, new(pkg.io), new(pkg.do))
    struct.pack_into('<i', out, pkg.pos_counts + 28, new(pkg.iego) if pkg.iego else 0)
    struct.pack_into('<i', out, pkg.pos_counts + 40, new(pkg.tto) if pkg.tto else 0)
    if pkg.gens:
        g = pkg.pos_gens + 12 * (len(pkg.gens) - 1)
        struct.pack_into('<ii', out, g, ec, name_count)

    for i, e in enumerate(pkg.exports):
        struct.pack_into('<i', out, new(e['pos_size']) + 4, new(e['off']))
    if pkg.tto:
        r = Reader(b); r.p = pkg.tto
        for _ in range(r.i32()):
            r.fstring(); r.fstring()
            pos = r.p; off = r.i32()
            struct.pack_into('<i', out, new(pos), new(off))
    fixed = 0
    for e in pkg.exports:
        s, end = e['off'], e['off'] + e['size']
        q = s + 12
        while q + 4 <= end:
            if struct.unpack_from('<i', b, q)[0] == q + 4:
                sz = struct.unpack_from('<i', b, q - 4)[0]
                if 0 <= sz <= end - (q + 4):
                    struct.pack_into('<i', out, new(q), new(q + 4)); fixed += 1
            q += 1
    open(dst, 'wb').write(out)
    print('  %d exports now, %d bulk-data offsets moved' % (ec, fixed))


if __name__ == '__main__':
    main()
