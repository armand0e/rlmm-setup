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
- **Dummy classes** from [RL-dummy-classes2](https://github.com/ghostrider-05/RL-dummy-classes2) (generated from the current
  Rocket League build, so the Not So Dummy Assets load without missing-class errors), copied in and compiled. Setup
  checks the compile result for you: 0 errors, or it tells you what failed. It also builds the Content Browser index,
  as Epic's installer does, so the editor doesn't re-index thousands of packages at every start.
- **Not So Dummy Assets**, plus the classic **dummy assets**. The dummy assets only fill in packages the Not So Dummy
  Assets don't have, so no package name is ever ambiguous.
- **Complexity** by Aceman3000 as the Soccar template (File > New Level), with its **Misc** assets so boost pads and
  goal crossbar physics work.
- **Rocket League testing:** your Steam or Epic install is found automatically and Utopia Retro is backed up. Drag a
  saved map onto `Test map in Rocket League.bat` in your Maps folder to play it.
- **Shortcuts:** "UDK - Rocket League" on the desktop, and Start menu > RLMM (editor, maps folder, update, restore Utopia).

You answer three questions at most: the UDK license (you can read it first), the install folder (Enter keeps
`C:\UDK\RLMM`), and, when updating, whether to apply the updates. Windows asks once for administrator rights.

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
- Expect 15 to 30 minutes, mostly downloads (about 5.5 GB).

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

## Building the wizard

`wizard\` holds RLMM-Setup.exe's source (C#, .NET Framework 4.8, which Windows 10 and 11 include). It embeds
`install.ps1` and `assets\Misc.zip`, so rebuild it after changing either:

```powershell
powershell -ExecutionPolicy Bypass -File wizard\build.ps1
```

The exe lands in `dist\`. Building needs the .NET SDK; running the exe needs nothing extra.

## Where everything comes from

| Component | Source |
|---|---|
| UDK 2015-02 installer | archive.org (Google Drive mirrors as fallback); MD5 and Epic's signature are verified |
| Dummy classes | [ghostrider-05/RL-dummy-classes2](https://github.com/ghostrider-05/RL-dummy-classes2), latest commit |
| Not So Dummy Assets, dummy assets, map templates | [RocketLeagueMapmaking](https://github.com/RocketLeagueMapmaking) on GitHub, latest commit (Not So Dummy Assets file by file from Git LFS, 16 downloads at a time) |
| Complexity template | Aceman3000, via [bakkesplugins](https://bakkesplugins.com/maps/339) |
| Misc assets | Aceman3000, bundled in this repo with his permission (`assets/Misc.zip`) |

The UDK EULA belongs to Epic Games. Setup shows it, straight from the installer, before anything is downloaded.

## Credits

The RocketLeagueMapmaking community and [rocketleaguemapmaking.com](https://rocketleaguemapmaking.com); Mr. Swaggles'
UDK_RL_Setup, which this replaces; Aceman3000 for Complexity and the Misc assets.
