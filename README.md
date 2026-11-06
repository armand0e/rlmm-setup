# RLMM Setup

Install UDK for Rocket League map making, fully set up, in one go. Run it again later to update the dummy classes and
assets.

**Easiest:** download **RLMM-Setup.exe** from the [latest release](https://github.com/armand0e/rlmm-setup/releases/latest)
and run it. It is a normal setup wizard: accept the UDK license, pick a folder, click Install.

**Or with one command** in PowerShell (Start menu, type "PowerShell"):

```powershell
irm https://raw.githubusercontent.com/armand0e/rlmm-setup/main/install.ps1 | iex
```

Both do the same thing (the wizard runs the same script); use whichever you prefer.

## What you get

- **UDK 2015** (Feb 2015 build, the version Rocket League maps need), installed the way Epic's own installer does it
  with the "Empty Game" option, but with no installer windows to click through.
- **The runtimes UDK needs:** Visual C++ 2010 and DirectX 9, installed silently, as Epic's installer does.
- **Dummy classes**: the community's [RL-Dummy-Classes](https://github.com/RocketLeagueMapmaking/RL-Dummy-Classes)
  (editor icons for spawns, boost pads and goals) merged with [RL-dummy-classes2](https://github.com/ghostrider-05/RL-dummy-classes2)
  (generated from the current Rocket League build, so the Not So Dummy Assets load without missing-class errors), then
  compiled. Where a community class breaks the compile, setup uses the generated one instead, round by round, until
  it compiles with 0 errors. It also builds the Content Browser index, as Epic's installer does, so the editor
  doesn't re-index thousands of packages at every start.
- **Not So Dummy Assets**, plus the classic **dummy assets**. The dummy assets only fill in packages the Not So Dummy
  Assets don't have, so no package name is ever ambiguous.
- **Map templates** (File > New Level): Soccar, Hoops, Dropshot and Test by Mr. Swaggles, and Mannfield (Aceman3000's
  Complexity stadium), all with the cubemap fix; plus Aceman3000's **Misc** assets so boost pads and goal crossbar
  physics work.
- **Rocket League testing:** your Steam or Epic install is found automatically and Utopia Retro is backed up. Drag a
  saved map onto `Test map in Rocket League.bat` in your Maps folder to play it.
- **Shortcuts:** "UDK - Rocket League" on the desktop, and Start menu > RLMM (editor, maps folder, update, restore Utopia).

You answer three questions at most: the UDK license (you can read it first), the install folder (Enter keeps
`C:\UDK\RLMM`), and, when updating, whether to apply the updates. Windows asks once for administrator rights.

## Normal warnings in UDK

Opening a stadium template, or any map built on Rocket League's assets, shows a **Load Errors** list and an
**Updating Changed Materials** prompt. Both are expected: the dummy assets are stand-ins for Rocket League's files and
reference things UDK doesn't have. Click **OK** on the errors and **Cancel** on the materials prompt. Never resave
the dummy asset packages (EuroStadium_P, GameInfo_Soccar_SF and so on): UDK fails to save them and crashes. If one
got damaged anyway, Start menu > RLMM > Update repairs it.

## Updating (version control)

Run the command again, or use Start menu > RLMM > Update. Setup lists every component with the version you have and
the latest one, and updates only what changed. When the dummy classes change, it also recompiles. Files that upstream
removed are removed from your install too. Your maps are never touched.

It also works on a UDK installed some other way (manually, or with UDK_RL_Setup.bat). Setup finds it and offers to
bring its dummy classes, assets and templates up to date.

## Uninstalling

Settings > Apps > "Unreal Development Kit: 2015-02 (Rocket League)" > Uninstall, or Start menu > RLMM > Uninstall RLMM.
It restores Utopia Retro, removes the shortcuts and the install folder, and can move your Maps folder to
Documents\RLMM maps first. The Visual C++ and DirectX runtimes stay installed (other programs use them).

## Requirements

- 64-bit Windows 10 or 11.
- About 20 GB free during the install, and 11 GB afterwards.
- Expect 10 to 30 minutes, depending on your connection (about 5.5 GB of downloads).

## Options

Run as a file to pass options:
`powershell -ExecutionPolicy Bypass -File install.ps1 -InstallDir D:\UDK\RLMM`

| Option | Meaning |
|---|---|
| `-InstallDir <path>` | Where UDK goes (default `C:\UDK\RLMM`; no spaces) |
| `-ProjectName <name>` | UDK game project name (default `RLMM`) |
| `-CacheDir <path>` | Download folder; files already there are verified and reused |
| `-KeepDownloads` | Keep the installer and zips afterwards |
| `-CheckOnly` | Only show installed vs latest versions |
| `-SkipPrerequisites`, `-SkipRocketLeague` | Leave the runtimes, or the Rocket League folder, alone |
| `-AcceptEula`, `-Yes` | Unattended installs (only accept the EULA if you have read it) |

## For maintainers

| Path | What it is |
|---|---|
| `install.ps1` | The whole setup: one PowerShell function, in sections (sources, downloads, UDK base install, dummy classes, content packages, map templates, Rocket League testing, main) |
| `Install-RLMM.bat` | Double-click launcher for a downloaded copy of the repo |
| `wizard\` | RLMM-Setup.exe (C#, .NET Framework 4.8): a wizard that runs `install.ps1` and shows its progress |
| `assets\Misc.zip` | Aceman3000's Misc packages (embedded in the exe) |
| `assets\Templates.zip` | The map templates (downloaded from this repo at install time) |
| `tools\` | Python scripts that build `Templates.zip` |

**Building the wizard.** It embeds `install.ps1` and `assets\Misc.zip`, so rebuild it after changing either. Building
needs the .NET SDK; running the exe needs nothing extra. The exe lands in `dist\`.

```powershell
powershell -ExecutionPolicy Bypass -File wizard\build.ps1
```

**Rebuilding the map templates.** `tools\make_templates_zip.py` takes the template pack, its `EditorMapTemplates.int`
and UDK_RL_Setup's `MapTemplateIndex.upk`, and writes `Templates.zip`. On the way it sets "Max Capture Time" to 2 on
every cubemap (`patch_cubemap.py`) and adds Mannfield and Dropshot to the New Level list (`add_template_meta.py`).
Both edit the packages directly rather than resaving them in UDK, which could drop Rocket League properties the dummy
classes don't know. Then put the printed Size and Md5 into `MapTemplates` in `install.ps1`.

```powershell
python tools\make_templates_zip.py Templates.zip EditorMapTemplates.int MapTemplateIndex.upk assets\Templates.zip
```

## Where everything comes from

| Component | Source |
|---|---|
| UDK 2015-02 installer | Google Drive (the mirror rocketleaguemapmaking.com links), archive.org as fallback; MD5 and Epic's signature are verified |
| Dummy classes | [RocketLeagueMapmaking/RL-Dummy-Classes](https://github.com/RocketLeagueMapmaking/RL-Dummy-Classes) merged with [ghostrider-05/RL-dummy-classes2](https://github.com/ghostrider-05/RL-dummy-classes2), latest commits |
| Not So Dummy Assets, dummy assets | [RocketLeagueMapmaking](https://github.com/RocketLeagueMapmaking) on GitHub, latest commit (Not So Dummy Assets file by file from Git LFS, 16 downloads at a time) |
| Map templates | Mr. Swaggles (Soccar, Hoops, Dropshot, Test) and Aceman3000 (Mannfield; he also polished Dropshot), bundled in this repo (`assets/Templates.zip`); New Level thumbnails from [UDK_RL_Setup](https://github.com/RocketLeagueMapmaking/UDK_RL_Setup) |
| Misc assets | Aceman3000, bundled in this repo with his permission (`assets/Misc.zip`) |

The UDK EULA belongs to Epic Games. Setup shows it, straight from the installer, before anything is downloaded.

## Credits

The RocketLeagueMapmaking community and [rocketleaguemapmaking.com](https://rocketleaguemapmaking.com); Mr. Swaggles
for UDK_RL_Setup, which this replaces, and the map templates; Aceman3000 for Mannfield (Complexity), his work on the
Dropshot template and the Misc assets; ghostrider-05 for the generated dummy classes.
