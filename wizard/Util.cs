using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

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
