"""Checks and fixes the map templates in templates/ (what File > New Level offers once setup has run).

  python tools/templates.py              check: report what's wrong, change nothing
  python tools/templates.py fix          fix what can be fixed automatically, then check again
  (add a folder to work on a copy instead of templates/, e.g. python tools/templates.py fix D:/my-templates)

Besides its Template_<Name>.umap, each template needs:
  - its cubemap capture time (MaxCaptureTime) at CAPTURE_TIME; UDK's default 0 breaks the reflections
  - an entry in MapTemplateIndex.upk, or New Level doesn't list it. fix adds a copy of the Soccar entry, so the new
    template shows the Soccar thumbnail
  - a name in EditorMapTemplates.int. fix adds "<Name> Template"; edit that line to rename it

fix only rewrites files that change. Setup installs whatever is in templates/ when it's pushed (see sources.json).
"""
import os
import sys

from add_template_meta import add_entries
from patch_cubemap import cubemap_values, patch
from ue3package import Package

CAPTURE_TIME = 2.0
THUMBNAIL_FROM = 'Template_Soccar'   # the index entry new templates copy
FOLDER = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'templates')
INDEX_FILE = 'MapTemplateIndex.upk'
NAMES_FILE = 'EditorMapTemplates.int'
NAMES_SECTION = '[TemplateMapMetadata.DisplayNames]'


def maps():
    return sorted(f[:-5] for f in os.listdir(FOLDER) if f.lower().startswith('template_') and f.lower().endswith('.umap'))


def read(path):
    with open(path, 'rb') as f:
        return f.read()


def write_if_changed(path, data):
    if os.path.exists(path) and read(path) == data:
        return False
    with open(path, 'wb') as f:
        f.write(data)
    return True


def index_entries(data):
    pkg = Package(data)
    return [e['name'] for e in pkg.exports if pkg.class_name(e) == 'TemplateMapMetadata']


def read_names():
    """EditorMapTemplates.int as lines (UTF-16, as UDK writes it) and its map -> display name pairs."""
    text = read(os.path.join(FOLDER, NAMES_FILE)).decode('utf-16')
    lines = text.splitlines()
    names = {}
    for line in lines:
        if '=' in line and not line.startswith(('[', ';')):
            k, v = line.split('=', 1)
            names[k.strip()] = v.strip()
    return lines, names


def write_names(lines):
    path = os.path.join(FOLDER, NAMES_FILE)
    end = '\r\n' if read(path).decode('utf-16').endswith('\n') else ''   # keep the file's own last line ending
    return write_if_changed(path, ('\r\n'.join(lines) + end).encode('utf-16'))   # UTF-16 with BOM, CRLF, as UDK writes it


def check():
    problems = 0
    index = index_entries(read(os.path.join(FOLDER, INDEX_FILE)))
    _, names = read_names()
    for m in maps():
        notes = []
        values = cubemap_values(read(os.path.join(FOLDER, m + '.umap')))
        if not values:
            notes.append('no cubemap')
        for where, v in values:
            if v != CAPTURE_TIME:
                notes.append('cubemap %s capture time %s (should be %g)' % (where, 'default 0' if v is None else '%g' % v, CAPTURE_TIME))
                problems += 1
        if m not in index:
            notes.append('not in MapTemplateIndex.upk (New Level will not list it)')
            problems += 1
        if m not in names:
            notes.append('no name in EditorMapTemplates.int')
            problems += 1
        shown = names.get(m, '?')
        print('  %-22s %-24s %s' % (m, '"%s"' % shown, '; '.join(notes) if notes else 'ok'))
    for m in sorted(set(index) - set(maps())):
        print('  %-22s index entry without a map (New Level may still list it)' % m)
    for m in sorted(set(names) - set(maps())):
        print('  %-22s name without a map (harmless)' % m)
    print('%d problem(s)%s' % (problems, ': run "python tools/templates.py fix"' if problems else ''))
    return problems


def fix():
    for m in maps():
        path = os.path.join(FOLDER, m + '.umap')
        data = read(path)
        values = cubemap_values(data)
        if values and any(v != CAPTURE_TIME for _, v in values):
            out, report = patch(data, CAPTURE_TIME)
            if write_if_changed(path, out):
                print('  %s: %s' % (m, '; '.join(report)))

    data = read(os.path.join(FOLDER, INDEX_FILE))
    missing = [m for m in maps() if m not in index_entries(data)]
    if missing:
        out, report = add_entries(data, [(THUMBNAIL_FROM, m) for m in missing])
        if write_if_changed(os.path.join(FOLDER, INDEX_FILE), out):
            print('  MapTemplateIndex.upk: ' + '; '.join(report))

    lines, names = read_names()
    added = [m for m in maps() if m not in names]
    if added:
        if NAMES_SECTION not in lines:
            lines.append(NAMES_SECTION)
        at = lines.index(NAMES_SECTION) + 1                      # after the section's last entry
        while at < len(lines) and not lines[at].startswith('['):
            at += 1
        while at > 0 and not lines[at - 1].strip():
            at -= 1
        lines[at:at] = ['%s=%s Template' % (m, m[len('Template_'):]) for m in added]
        if write_names(lines):
            print('  EditorMapTemplates.int: added ' + ', '.join(added))


def main():
    global FOLDER
    args = sys.argv[1:]
    cmd = args.pop(0) if args and args[0] in ('check', 'fix') else 'check'
    if args:
        FOLDER = os.path.abspath(args.pop(0))
    if args:
        sys.exit(__doc__)
    if cmd == 'fix':
        fix()
    print('Templates in %s:' % FOLDER)
    sys.exit(1 if check() else 0)


if __name__ == '__main__':
    main()
