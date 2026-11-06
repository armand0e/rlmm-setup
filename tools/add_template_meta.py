"""Adds entries to UDK's MapTemplateIndex.upk so File > New Level lists more map templates.

New Level only shows a template that has a TemplateMapMetadata object (named after the map, with a Thumbnail) in
this package. Each new entry is a copy of an existing one, so it shows that entry's thumbnail.

Usage: python add_template_meta.py IN.upk OUT.upk EXISTING=NEW [EXISTING=NEW ...]
  e.g. add_template_meta.py MapTemplateIndex.upk out.upk Template_Soccar=Template_Mannfield Template_Soccar=Template_Dropshot
"""
import struct
import sys

from ue3package import EXPORT_ENTRY_SIZE, Package, name_entry, relocate, set_counts


def add_entries(data, pairs):
    pkg = Package(data)
    if pkg.export_end - pkg.eo != EXPORT_ENTRY_SIZE * pkg.ec:
        raise ValueError('unexpected export table layout')
    by_name = {e['name']: (i, e) for i, e in enumerate(pkg.exports)}
    names, entries, report = [], [], []
    name_count = pkg.nc
    for existing, new_name in pairs:
        if new_name in by_name:
            report.append(new_name + ' is already listed')
            continue
        i, e = by_name[existing]
        index = pkg.name_index(new_name)
        if index < 0:
            index = name_count
            name_count += 1
            names.append(name_entry(new_name, pkg.names[pkg.name_index(existing)][1]))
        entry = bytearray(data[e['entry']:e['entry'] + EXPORT_ENTRY_SIZE])
        struct.pack_into('<ii', entry, 12, index, 0)                       # ObjectName
        body = struct.pack('<i', -1) + data[e['off'] + 4:e['off'] + e['size']]   # NetIndex none, same properties
        entries.append((entry, body))
        report.append('%s added (thumbnail of %s)' % (new_name, existing))
    if not entries:
        return data, report

    count = len(entries)
    out, new = relocate(pkg, [(pkg.name_end, b''.join(names)),
                              (pkg.export_end, bytes(EXPORT_ENTRY_SIZE * count)),   # filled in below
                              (pkg.depends_end, struct.pack('<i', 0) * count)])     # no dependencies
    first = new(pkg.export_end) - EXPORT_ENTRY_SIZE * count
    for k, (entry, body) in enumerate(entries):
        struct.pack_into('<ii', entry, 32, len(body), len(out))           # SerialSize, SerialOffset: end of file
        out[first + EXPORT_ENTRY_SIZE * k:first + EXPORT_ENTRY_SIZE * (k + 1)] = entry
        out += body
    set_counts(out, pkg, name_count, pkg.ec + count)
    return bytes(out), report


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    with open(sys.argv[1], 'rb') as f:
        data = f.read()
    out, report = add_entries(data, [a.split('=', 1) for a in sys.argv[3:]])
    with open(sys.argv[2], 'wb') as f:
        f.write(out)
    for line in report:
        print('  ' + line)


if __name__ == '__main__':
    main()
