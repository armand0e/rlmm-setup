using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Microsoft.Win32;

namespace RLMMSetup
{
    static class Util
    {
        /// <summary>Quotes one command-line argument (CommandLineToArgvW rules).</summary>
        public static string Quote(string s)
        {
            var sb = new StringBuilder("\"");
            int bs = 0;
            foreach (char c in s)
            {
                if (c == '\\') { bs++; continue; }
                if (c == '"') { sb.Append('\\', bs * 2 + 1).Append('"'); bs = 0; continue; }
                sb.Append('\\', bs).Append(c); bs = 0;
            }
            sb.Append('\\', bs * 2).Append('"');
            return sb.ToString();
        }

        public static bool IsInside(string path, string dir) =>
            Path.GetFullPath(path).StartsWith(Path.GetFullPath(dir).TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase);

        public static string Size(double bytes)
        {
            if (bytes >= 1L << 30) return (bytes / (1L << 30)).ToString("0.0") + " GB";
            if (bytes >= 1L << 20) return (bytes / (1L << 20)).ToString("0") + " MB";
            return (bytes / 1024).ToString("0") + " KB";
        }

        public static long FreeSpace(string path)
        {
            try { return new DriveInfo(Path.GetPathRoot(Path.GetFullPath(path))).AvailableFreeSpace; } catch { return -1; }
        }

        /// <summary>UDK processes started from this install (they lock files setup has to replace).</summary>
        public static bool UdkRunningFrom(string dir)
        {
            foreach (var name in new[] { "UDK", "UDKLift" })
                foreach (var p in Process.GetProcessesByName(name))
                {
                    try { if (IsInside(p.MainModule.FileName, dir)) return true; } catch { }
                }
            return false;
        }

        /// <summary>True when a .lnk mentions this folder (shell links store the target path as text).</summary>
        public static bool ShortcutPointsInto(string lnk, string dir)
        {
            try
            {
                var bytes = File.ReadAllBytes(lnk);
                string a = Encoding.Default.GetString(bytes), u = Encoding.Unicode.GetString(bytes);
                string d = dir.TrimEnd('\\') + "\\";
                return a.IndexOf(d, StringComparison.OrdinalIgnoreCase) >= 0 || u.IndexOf(d, StringComparison.OrdinalIgnoreCase) >= 0;
            }
            catch { return false; }
        }

        // ------------------------------------------------------------------ Rocket League (same rules as install.ps1)

        /// <summary>The Rocket League folder for a path to it, its TAGame, CookedPCConsole, Binaries\Win64 or
        /// RocketLeague.exe; null when there is no Rocket League there.</summary>
        public static string ResolveRocketLeague(string path)
        {
            try
            {
                string p = (path ?? "").Trim().Trim('"').TrimEnd('\\');
                if (p.Length == 0) return null;
                p = Path.GetFullPath(p);
                if (p.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) p = Path.GetDirectoryName(p);
                for (int i = 0; i < 3 && !string.IsNullOrEmpty(p); i++)
                {
                    if (Directory.Exists(Path.Combine(p, @"TAGame\CookedPCConsole"))) return p.TrimEnd('\\');
                    p = Path.GetDirectoryName(p);
                }
            }
            catch { }
            return null;
        }

        /// <summary>Rocket League installs found in every Steam library and in the Epic launcher's list.</summary>
        public static List<string> FindRocketLeague()
        {
            var found = new List<string>();
            void Add(string p) { p = ResolveRocketLeague(p); if (p != null && !found.Contains(p, StringComparer.OrdinalIgnoreCase)) found.Add(p); }
            var steams = new List<string>();   // HKLM first: real case (HKCU's SteamPath is lower case)
            foreach (var key in new[] { @"SOFTWARE\WOW6432Node\Valve\Steam", @"SOFTWARE\Valve\Steam" })
                try { using (var k = Registry.LocalMachine.OpenSubKey(key)) if (k?.GetValue("InstallPath") is string s) steams.Add(s); } catch { }
            try { using (var k = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam")) if (k?.GetValue("SteamPath") is string s) steams.Add(s.Replace('/', '\\')); } catch { }
            foreach (var steam in steams)
            {
                var libs = new List<string> { steam };
                try
                {
                    string vdf = Path.Combine(steam, @"steamapps\libraryfolders.vdf");
                    if (File.Exists(vdf))
                        foreach (Match m in Regex.Matches(File.ReadAllText(vdf), "\"path\"\\s+\"([^\"]+)\"")) libs.Add(m.Groups[1].Value.Replace(@"\\", @"\"));
                }
                catch { }
                foreach (var lib in libs) Add(Path.Combine(lib, @"steamapps\common\rocketleague"));
            }
            try
            {
                string dat = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), @"Epic\UnrealEngineLauncher\LauncherInstalled.dat");
                if (File.Exists(dat))
                    foreach (Match m in Regex.Matches(File.ReadAllText(dat), "\\{[^{}]*\\}"))
                    {
                        if (!Regex.IsMatch(m.Value, "\"AppName\"\\s*:\\s*\"Sugar\"")) continue;
                        var loc = Regex.Match(m.Value, "\"InstallLocation\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
                        if (loc.Success) Add(Regex.Unescape(loc.Groups[1].Value));
                    }
            }
            catch { }
            return found;
        }

        /// <summary>The Rocket League folder an install was set up with (RLMM-Setup\state.json), or null.</summary>
        public static string SavedRocketLeague(string installDir)
        {
            try
            {
                string f = Path.Combine(installDir, @"RLMM-Setup\state.json");
                var m = Regex.Match(File.ReadAllText(f), "\"RocketLeagueDir\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
                if (m.Success && m.Groups[1].Value.Length > 0) return Regex.Unescape(m.Groups[1].Value);
            }
            catch { }
            return null;
        }

        public static string DesktopShortcut => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory), "UDK - Rocket League.lnk");

        /// <summary>Opens a file or shortcut as the signed-in user (not elevated), the way Explorer would.</summary>
        public static void OpenAsUser(string path)
        {
            try { Process.Start(new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe"), Quote(path)) { UseShellExecute = false }); }
            catch { }
        }

        [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);

        /// <summary>Renders a window to a PNG, also when it is off screen (used by /selftest).</summary>
        public static void Snapshot(Form f, string name)
        {
            if (Program.ShotDir == null) return;
            try
            {
                Directory.CreateDirectory(Program.ShotDir);
                f.Refresh();
                Application.DoEvents();
                using (var bmp = new Bitmap(f.Width, f.Height))
                {
                    using (var g = Graphics.FromImage(bmp))
                    {
                        IntPtr hdc = g.GetHdc();
                        PrintWindow(f.Handle, hdc, 0);
                        g.ReleaseHdc(hdc);
                    }
                    bmp.Save(Path.Combine(Program.ShotDir, name + ".png"), System.Drawing.Imaging.ImageFormat.Png);
                }
            }
            catch { }
        }
    }
}
