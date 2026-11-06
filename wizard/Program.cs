using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

namespace RLMMSetup
{
    static class Program
    {
        public static string Version => Assembly.GetExecutingAssembly().GetName().Version.ToString(3);

        // Hidden options (tests and power users):
        //   /cache <dir>              download folder (passed to install.ps1 -CacheDir)
        //   /selftest <dir> <shots>   drive the wizard automatically, off screen, saving a PNG of each page
        //   /pagesonly                with /selftest: stop at the install or update page instead of running
        //   /uninstall [<dir>]        uninstall (Apps & features and Start menu use this)
        public static string CacheDir;
        public static string SelfTestDir;
        public static string ShotDir;
        public static bool PagesOnly;

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
            PagesOnly = Find("/pagesonly") >= 0;

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
}
