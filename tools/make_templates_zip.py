"""Builds assets/Templates.zip, the map templates setup installs, from its sources.

  PACK   the template pack as Aceman3000 shared it (a zip with Template_Soccar/Mannfield/Hoops/Dropshot/Test.umap
         in any folder; other maps in it are ignored)
  NAMES  EditorMapTemplates.int from the same pack (the names File > New Level shows)
  INDEX  MapTemplateIndex.upk from RocketLeagueMapmaking/UDK_RL_Setup (Goodies/Templates/), the New Level thumbnails

Every map gets the cubemap fix (patch_cubemap.py) and the index gets entries for Mannfield and Dropshot
(add_template_meta.py). After rebuilding, update Size and Md5 of MapTemplates in install.ps1.

Usage: python make_templates_zip.py PACK NAMES INDEX OUT.zip
"""
import hashlib
import os
import sys
import zipfile

from add_template_meta import add_entries
from patch_cubemap import patch

MAPS = ['Template_Soccar', 'Template_Mannfield', 'Template_Hoops', 'Template_Dropshot', 'Template_Test']
NEW_INDEX_ENTRIES = [('Template_Soccar', 'Template_Mannfield'), ('Template_Soccar', 'Template_Dropshot')]


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    pack_path, names_path, index_path, out_path = sys.argv[1:]
    with zipfile.ZipFile(pack_path) as pack:
        found = {os.path.splitext(os.path.basename(n))[0]: n for n in pack.namelist() if n.lower().endswith('.umap')}
        missing = [m for m in MAPS if m not in found]
        if missing:
            sys.exit('the pack has no ' + ', '.join(missing))
        maps = {m: pack.read(found[m]) for m in MAPS}

    files = []
    for m in MAPS:
        data, report = patch(maps[m])
        print(m + ':\n  ' + '\n  '.join(report))
        files.append((m + '.umap', data))
    with open(names_path, 'rb') as f:
        files.append(('EditorMapTemplates.int', f.read()))
    with open(index_path, 'rb') as f:
        index, report = add_entries(f.read(), NEW_INDEX_ENTRIES)
    print('MapTemplateIndex.upk:\n  ' + '\n  '.join(report))
    files.append(('MapTemplateIndex.upk', index))

    with zipfile.ZipFile(out_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, data in files:
            info = zipfile.ZipInfo(name, date_time=(2026, 11, 5, 0, 0, 0))   # fixed date: same input, same zip
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data, compresslevel=9)
    with open(out_path, 'rb') as f:
        body = f.read()
    print('%s: Size = %d, Md5 = %s' % (out_path, len(body), hashlib.md5(body).hexdigest().upper()))


if __name__ == '__main__':
    main()
