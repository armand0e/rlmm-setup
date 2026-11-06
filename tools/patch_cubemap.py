"""Sets MaxCaptureTime on every SceneCaptureCubeMapComponent of a map (the cubemap fix for the map templates).

MaxCaptureTime defaults to 0, and a property at its default isn't stored in the package, so most templates don't
even have the name. This adds the name when needed and a FloatProperty tag to each cubemap component (an existing
value is overwritten); everything else stays byte for byte the same.

Usage: python patch_cubemap.py IN.umap OUT.umap [VALUE]      (VALUE defaults to 2)
"""
import struct
import sys

from ue3package import Package, name_entry, relocate, set_counts


def patch(data, value=2.0):
    pkg = Package(data)
    float_type = pkg.name_index('FloatProperty')
    if float_type < 0:
        raise ValueError('the package has no FloatProperty name')
    name = pkg.name_index('MaxCaptureTime')
    add_name = name < 0
    if add_name:
        name = pkg.nc

    inserts, overwrites, grown, report = [], [], {}, []
    for i, e in enumerate(pkg.exports):
        if pkg.class_name(e) != 'SceneCaptureCubeMapComponent':
            continue
        where = '%s.%s' % (pkg.object_name(e['outer']), e['name'])
        props = pkg.properties(e, preamble=8)
        have = [p for p in props if p[0] == 'MaxCaptureTime']
        if have:
            overwrites.append((have[0][3], struct.pack('<f', value)))
            report.append(where + ': MaxCaptureTime overwritten')
            continue
        # after FarPlane (where UDK puts it), else after the last property before it
        before = [p for p in props if p[0] in ('TextureTarget', 'NearPlane', 'FarPlane')]
        at = before[-1][3] + before[-1][4] if before else e['off'] + 8
        tag = struct.pack('<6i', name, 0, float_type, 0, 4, 0) + struct.pack('<f', value)
        inserts.append((at, tag))
        grown[i] = len(tag)
        report.append(where + ': MaxCaptureTime added')
    if not report:
        raise ValueError('no SceneCaptureCubeMapComponent in this package')
    if add_name:
        inserts.append((pkg.name_end, name_entry('MaxCaptureTime', pkg.names[pkg.name_index('FarPlane')][1])))

    out, new = relocate(pkg, inserts)
    for i, extra in grown.items():
        e = pkg.exports[i]
        struct.pack_into('<i', out, new(e['entry']) + 32, e['size'] + extra)
    for pos, raw in overwrites:
        p = new(pos)
        out[p:p + len(raw)] = raw
    set_counts(out, pkg, pkg.nc + (1 if add_name else 0), pkg.ec)
    return bytes(out), report


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    value = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
    with open(sys.argv[1], 'rb') as f:
        data = f.read()
    out, report = patch(data, value)
    with open(sys.argv[2], 'wb') as f:
        f.write(out)
    for line in report:
        print('  ' + line)


if __name__ == '__main__':
    main()
