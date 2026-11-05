using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace RLMMSetup
{
    static class Program
    {
        public static string Version => Assembly.GetExecutingAssembly().GetName().Version.ToString(3);

        // Hidden options (tests and power users):
        //   /cache <dir>              download folder (passed to install.ps1 -CacheDir)
        //   /selftest <dir> <shots>   drive the wizard automatically, off screen, saving a PNG of each page
        //   /uninstall [<dir>]        uninstall (Apps & features and Start menu use this)
        public static string CacheDir;
        public static string SelfTestDir;
        public static string ShotDir;

        [STAThread]
        static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            var a = new List<string>(args);
            int Find(string name) => a.FindIndex(x => x.Equals(name, StringComparison.OrdinalIgnoreCase));
            string Opt(string name, int k = 1)
            {
                int i = Find(name);
                if (i < 0 || i + k >= a.Count || a[i + k].StartsWith("/")) return null;
                return a[i + k];
            }

            CacheDir = Opt("/cache");
            SelfTestDir = Opt("/selftest");
            ShotDir = Opt("/selftest", 2);

            if (Find("/uninstall") >= 0)
            {
                string dir = Opt("/uninstall") ?? Uninstaller.DirFromExe();
                if (dir == null || !Directory.Exists(dir))
                {
                    MessageBox.Show("RLMM Setup could not find the UDK install to remove.", "RLMM Setup", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return 1;
                }
                dir = Path.GetFullPath(dir).TrimEnd('\\');
                // Windows can't delete a running exe, so the copy inside the install hands over to a copy in %TEMP%.
                if (Find("/fromtemp") < 0 && Util.IsInside(Application.ExecutablePath, dir))
                {
                    string tmp = Path.Combine(Path.GetTempPath(), "RLMM-Uninstall-" + Guid.NewGuid().ToString("N").Substring(0, 8) + ".exe");
                    File.Copy(Application.ExecutablePath, tmp);
                    var rest = new List<string> { "/uninstall", dir, "/fromtemp" };
                    if (SelfTestDir != null) { rest.Add("/selftest"); rest.Add(SelfTestDir); if (ShotDir != null) rest.Add(ShotDir); }
                    Process.Start(new ProcessStartInfo(tmp, string.Join(" ", rest.Select(Util.Quote))) { UseShellExecute = false });
                    return 0;
                }
                Application.Run(new UninstallForm(dir, Find("/fromtemp") >= 0));
                return 0;
            }

            using (var mutex = new Mutex(false, "Global\\RLMM-Setup-Wizard", out bool created))
            {
                if (!created && SelfTestDir == null)
                {
                    MessageBox.Show("RLMM Setup is already running.", "RLMM Setup", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return 1;
                }
                Application.Run(new SetupForm());
            }
            Payload.Cleanup();
            return 0;
        }
    }

    /// <summary>install.ps1 and the bundled assets, unpacked to a temp folder on first use.</summary>
    static class Payload
    {
        static string dir;
        public static string Dir { get { if (dir == null) Extract(); return dir; } }
        public static string Script => Path.Combine(Dir, "install.ps1");
        public static string AssetsDir => Path.Combine(Dir, "assets");

        static void Extract()
        {
            dir = Path.Combine(Path.GetTempPath(), "RLMM-Setup-" + Guid.NewGuid().ToString("N").Substring(0, 8));
            Directory.CreateDirectory(Path.Combine(dir, "assets"));
            Write("install.ps1", Path.Combine(dir, "install.ps1"));
            Write("Misc.zip", Path.Combine(dir, "assets", "Misc.zip"));
        }

        static void Write(string resource, string path)
        {
            using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream(resource))
            using (var f = File.Create(path)) s.CopyTo(f);
        }

        public static Stream Open(string resource) => Assembly.GetExecutingAssembly().GetManifestResourceStream(resource);

        public static void Cleanup()
        {
            if (dir == null) return;
            try { Directory.Delete(dir, true); } catch { }
        }
    }

    /// <summary>
    /// Runs install.ps1 hidden with RLMM_WIZARD=1 and raises one event per '@@KIND|text' line it prints
    /// (STEP, STATUS, INFO, OK, WARN, DL, COMP, MODE, INSTALLS, FAILED, ERROR, SAY). Events arrive on the UI thread.
    /// </summary>
    class ScriptRunner
    {
        public event Action<string, string> Message;
        public event Action<string> Line;
        public event Action<int> Exited;

        Process proc;
        SynchronizationContext ctx;
        public bool Running { get; private set; }

        public void Start(params string[] args)
        {
            ctx = SynchronizationContext.Current ?? new SynchronizationContext();
            var sb = new StringBuilder("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ");
            sb.Append(Util.Quote(Payload.Script));
            foreach (var x in args) sb.Append(' ').Append(x.StartsWith("-") ? x : Util.Quote(x));
            var psi = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"), sb.ToString())
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                RedirectStandardInput = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8,
                WorkingDirectory = Payload.Dir,
            };
            psi.EnvironmentVariables["RLMM_WIZARD"] = "1";
            // Started from PowerShell 7, the inherited PSModulePath points Windows PowerShell at PS7's modules and
            // breaks built-in cmdlets (Get-FileHash); without it, powershell.exe uses its own default.
            psi.EnvironmentVariables.Remove("PSModulePath");
            proc = Process.Start(psi);
            Running = true;
            try { proc.StandardInput.Close(); } catch { }
            var readers = new[] { Reader(proc.StandardOutput), Reader(proc.StandardError) };
            var waiter = new Thread(() =>
            {
                proc.WaitForExit();
                foreach (var t in readers) t.Join(3000);
                int code = -1;
                try { code = proc.ExitCode; } catch { }
                ctx.Post(_ => { Running = false; Exited?.Invoke(code); }, null);
            }) { IsBackground = true };
            waiter.Start();
        }

        Thread Reader(StreamReader r)
        {
            var t = new Thread(() =>
            {
                var buf = new char[8192];
                var line = new StringBuilder();
                try
                {
                    int n;
                    while ((n = r.Read(buf, 0, buf.Length)) > 0)
                    {
                        for (int i = 0; i < n; i++)
                        {
                            char c = buf[i];
                            if (c == '\r' || c == '\n') { if (line.Length > 0) { Dispatch(line.ToString()); line.Clear(); } }
                            else line.Append(c);
                        }
                    }
                }
                catch { }
                if (line.Length > 0) Dispatch(line.ToString());
            }) { IsBackground = true };
            t.Start();
            return t;
        }

        void Dispatch(string line)
        {
            ctx.Post(_ =>
            {
                if (line.StartsWith("@@"))
                {
                    int bar = line.IndexOf('|');
                    string kind = bar < 0 ? line.Substring(2) : line.Substring(2, bar - 2);
                    string rest = bar < 0 ? "" : line.Substring(bar + 1);
                    Message?.Invoke(kind, rest);
                }
                else Line?.Invoke(line);
            }, null);
        }

        /// <summary>Stops the script and everything it started (curl, UDK.com, runtime installers).</summary>
        public void Kill()
        {
            if (proc == null || !Running) return;
            try
            {
                var k = Process.Start(new ProcessStartInfo("taskkill.exe", "/T /F /PID " + proc.Id) { CreateNoWindow = true, UseShellExecute = false });
                k.WaitForExit(10000);
            }
            catch { }
            try { if (!proc.HasExited) proc.Kill(); } catch { }
        }
    }

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
