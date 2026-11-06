# Map templates

What File > New Level offers once RLMM Setup has run. These are the exact files setup installs (rules in
`sources.json`, component `MapTemplates`):

| File | Installed to | What it is |
|---|---|---|
| `Template_<Name>.umap` | `Engine\Content\Maps\Templates` | One template map each |
| `EditorMapTemplates.int` | `Engine\Localization\INT` | The names New Level shows (`Template_Soccar=Soccar Template`). UTF-16 text: Notepad and VS Code keep that |
| `MapTemplateIndex.upk` | `Engine\Content` | The New Level list: a map without an entry here is not offered |

The first time, setup keeps the UDK files these replace as `<file>.bak`, and puts them back if a file is later removed
from this folder.

## Adding or replacing a template

1. Save the map in UDK as `Template_<Name>.umap` and copy it here (replace the old one to update it).
2. Run `python tools/templates.py fix` from the repo folder. It:
   - sets the cubemap's Max Capture Time to 2 (UDK's default 0 breaks the reflections), so this needn't be done by hand
     in UDK;
   - adds the map to `MapTemplateIndex.upk` if it's new. The entry is a copy of Soccar's, so it shows the Soccar
     thumbnail;
   - adds `Template_<Name>=<Name> Template` to `EditorMapTemplates.int` if the map has no name yet. Edit that line to
     rename it.
3. `python tools/templates.py` (check only) should report 0 problems. Then commit and push. Every install gets the
   change the next time it runs setup or Start menu > RLMM > Update, and only changed files are downloaded.

To test before pushing, run `install.ps1` from your copy of the repo: it installs from this folder instead of GitHub.

## Removing a template

Delete its `.umap` here and its line in `EditorMapTemplates.int`. Its entry in `MapTemplateIndex.upk` can stay (the
check notes it); New Level may still list it.

The tools edit the packages byte by byte instead of resaving them in UDK, which could drop Rocket League properties
the dummy classes don't know about.

## Credits

Soccar, Hoops, Dropshot and Test: Mr. Swaggles. Mannfield (the Complexity stadium): Aceman3000, who also polished
Dropshot. New Level thumbnails: [UDK_RL_Setup](https://github.com/RocketLeagueMapmaking/UDK_RL_Setup).
