using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace RLMMSetup
{
    static class Uninstaller
    {
        /// <summary>The install that holds this exe (&lt;install&gt;\RLMM-Setup\RLMM-Setup.exe), if any.</summary>
        public static string DirFromExe()
        {
            var d = Path.GetDirectoryName(Application.ExecutablePath);
            if (!string.Equals(Path.GetFileName(d), "RLMM-Setup", StringComparison.OrdinalIgnoreCase)) return null;
            var root = Path.GetDirectoryName(d);
            return File.Exists(Path.Combine(root, @"Binaries\Win64\UDK.exe")) || File.Exists(Path.Combine(root, @"RLMM-Setup\state.json")) ? root : null;
        }
    }

    /// <summary>
    /// Removes an install made by RLMM Setup: restores Utopia Retro, optionally keeps the user's maps, removes the
    /// shortcuts and the Apps &amp; features entry, then deletes the folder. The shared runtimes stay installed.
    /// </summary>
    class UninstallForm : WizardChrome
    {
        readonly string dir;
        readonly bool fromTemp;
        Panel pConfirm, pWork, pDone;
        CheckBox cKeepMaps;
        Label workLabel, doneTitle, doneText;
        ProgressBar bar;
        bool working, finished;
        readonly List<string> notes = new List<string>();
        string keptMaps;

        public UninstallForm(string dir, bool fromTemp)
        {
            this.dir = dir;
            this.fromTemp = fromTemp;
            Text = "Uninstall RLMM";
            int w = PageWidth(true);

            pConfirm = NewPage(true);
            var st = Stack(pConfirm);
            Para(st, "Uninstall RLMM", w, 0, Big);
            Para(st, "This removes UDK and everything RLMM Setup installed from:", w, 12);
            Para(st, dir, w, 6, Bold(9F));
            Para(st, "Utopia Retro is restored in Rocket League, and the shortcuts are removed. The Visual C++ and DirectX runtimes stay installed, because other programs use them too.", w, 12);
            cKeepMaps = new CheckBox { Text = "Keep my maps (the Maps folder is moved to Documents\\RLMM maps)", AutoSize = true, MaximumSize = new Size(w, 0), Checked = true, Margin = new Padding(0, 16, 0, 0) };
            st.Controls.Add(cKeepMaps);
            var warn = Para(st, "Anything else you saved inside this folder is deleted.", w, 10);
            warn.ForeColor = Color.Firebrick;

            pWork = NewPage(false);
            var sw = Stack(pWork);
            workLabel = Para(sw, "Removing...", PageWidth(false));
            bar = new ProgressBar { Size = new Size(PageWidth(false), 20), Style = ProgressBarStyle.Marquee, MarqueeAnimationSpeed = 30, Margin = new Padding(0, 10, 0, 0) };
            sw.Controls.Add(bar);

            pDone = NewPage(true);
            var sd = Stack(pDone);
            doneTitle = Para(sd, "", w, 0, Big);
            doneText = Para(sd, "", w, 12);

            FinishLayout();
            back.Visible = false;
            next.Text = "&Uninstall";
            next.Click += (s, e) => { if (finished) Close(); else Start(); };
            cancel.Click += (s, e) => Close();
            if (Program.SelfTestDir != null)
            {
                StartPosition = FormStartPosition.Manual;
                Location = new Point(-20000, -20000);
                ShowInTaskbar = false;
            }
            ShowPage(pConfirm);
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            if (Program.SelfTestDir == null) return;
            var t = new System.Windows.Forms.Timer { Interval = 700 };
            int stage = 0;
            t.Tick += (s, a) =>
            {
                if (stage == 0) { Util.Snapshot(this, "u1-confirm"); stage = 1; Start(); }
                else if (stage == 1 && finished) { Util.Snapshot(this, "u2-done"); stage = 2; t.Stop(); Close(); }
            };
            t.Start();
        }

        void Start()
        {
            while (Util.UdkRunningFrom(dir))
            {
                if (Program.SelfTestDir != null) return;
                if (MessageBox.Show(this, "UDK is running from this folder. Save your work and close UDK, then click OK.", Text,
                        MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return;
            }
            working = true;
            bool keep = cKeepMaps.Checked;
            ShowPage(pWork, "Uninstalling", "Please wait while RLMM is removed.");
            next.Enabled = false;
            cancel.Enabled = false;
            var ui = SynchronizationContext.Current;
            new Thread(() =>
            {
                void Say(string s) => ui.Post(_ => workLabel.Text = s, null);
                try
                {
                    Say("Restoring Utopia Retro...");
                    RestoreUtopia();
                    if (keep) { Say("Moving your maps to Documents..."); KeepMaps(); }
                    Say("Removing shortcuts and the Apps & features entry...");
                    RemoveShortcuts();
                    RemoveRegistry();
                    Say("Deleting files...");
                    DeleteFolder();
                }
                catch (Exception ex) { notes.Add(ex.Message); }
                ui.Post(_ => Done(), null);
            }) { IsBackground = true }.Start();
        }

        void RestoreUtopia()
        {
            // The restore script setup wrote names the backup and Rocket League's Utopia file.
            string bat = Path.Combine(dir, @"RLMM-Setup\Restore Utopia Retro.bat");
            if (!File.Exists(bat)) return;
            var m = Regex.Match(File.ReadAllText(bat), "-Source \"([^\"]+)\" -Target \"([^\"]+)\"");
            if (!m.Success) return;
            string backup = m.Groups[1].Value, target = m.Groups[2].Value;
            if (!File.Exists(backup) || !Directory.Exists(Path.GetDirectoryName(target))) return;
            try { File.Copy(backup, target, true); }
            catch (Exception ex) { notes.Add("Utopia Retro could not be restored (" + ex.Message + "). Verify Rocket League's files in Steam or Epic to restore it."); }
        }

        void KeepMaps()
        {
            string maps = Path.Combine(dir, @"UDKGame\Content\Maps");
            if (!Directory.Exists(maps)) return;
            var stock = StockFiles();
            var files = Directory.GetFiles(maps, "*", SearchOption.AllDirectories)
                .Where(f => !new[] { "Test map in Rocket League.bat", "UtopiaOverwrite.bat" }.Contains(Path.GetFileName(f), StringComparer.OrdinalIgnoreCase))
                .Where(f => !stock.Contains(f.Substring(dir.Length + 1).Replace('\\', '/')))
                .ToList();
            if (files.Count == 0) return;
            string docs = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            string dest = Path.Combine(docs, "RLMM maps");
            if (Directory.Exists(dest) && Directory.EnumerateFileSystemEntries(dest).Any()) dest = Path.Combine(docs, "RLMM maps " + DateTime.Now.ToString("yyyy-MM-dd HHmm"));
            foreach (var f in files)
            {
                string to = Path.Combine(dest, f.Substring(maps.Length + 1));
                Directory.CreateDirectory(Path.GetDirectoryName(to));
                File.Copy(f, to, true);
            }
            keptMaps = dest;
        }

        /// <summary>Files UDK itself installed (Binaries\InstallData\Manifest.xml), relative with '/', case-insensitive.</summary>
        HashSet<string> StockFiles()
        {
            var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                var doc = new System.Xml.XmlDocument();
                doc.Load(Path.Combine(dir, @"Binaries\InstallData\Manifest.xml"));
                void Walk(System.Xml.XmlNode node, string prefix)
                {
                    foreach (System.Xml.XmlElement f in node.SelectNodes("Files/FileProperties")) set.Add((prefix + f.GetAttribute("FileName")).Replace('\\', '/'));
                    foreach (System.Xml.XmlElement d in node.SelectNodes("Folders/FolderProperties")) Walk(d, prefix + d.GetAttribute("FolderName") + "/");
                }
                if (doc.DocumentElement != null) Walk(doc.DocumentElement, "");
                // The Empty Game project is copied from the template folder, so its files count as stock where they land.
                const string tpl = "UDKGame/ProjectTemplates/Template1/";
                foreach (var p in set.Where(p => p.StartsWith(tpl, StringComparison.OrdinalIgnoreCase)).ToList()) set.Add(p.Substring(tpl.Length));
            }
            catch { }
            return set;
        }

        void RemoveShortcuts()
        {
            try
            {
                if (File.Exists(Util.DesktopShortcut) && Util.ShortcutPointsInto(Util.DesktopShortcut, dir)) File.Delete(Util.DesktopShortcut);
                string menu = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms), "RLMM");
                if (Directory.Exists(menu) && Directory.GetFiles(menu, "*.lnk").Any(l => Util.ShortcutPointsInto(l, dir))) Directory.Delete(menu, true);
            }
            catch (Exception ex) { notes.Add("Some shortcuts could not be removed (" + ex.Message + ")."); }
        }

        void RemoveRegistry()
        {
            foreach (var view in new[] { RegistryView.Registry32, RegistryView.Registry64 })
            {
                try
                {
                    using (var hk = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view))
                    using (var un = hk.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", true))
                    {
                        if (un == null) continue;
                        foreach (var name in un.GetSubKeyNames().Where(n => n.StartsWith("UDK-")))
                        {
                            string loc;
                            using (var k = un.OpenSubKey(name)) loc = k?.GetValue("InstallLocation") as string;
                            if (loc != null && string.Equals(loc.TrimEnd('\\'), dir, StringComparison.OrdinalIgnoreCase)) un.DeleteSubKeyTree(name, false);
                        }
                    }
                }
                catch { }
            }
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(@"Software\RLMM-Setup"))
                {
                    string d = k?.GetValue("InstallDir") as string;
                    if (d == null || !string.Equals(d.TrimEnd('\\'), dir, StringComparison.OrdinalIgnoreCase)) return;
                }
                Registry.CurrentUser.DeleteSubKeyTree(@"Software\RLMM-Setup", false);
            }
            catch { }
            RemoveUdkAssociation();
        }

        /// <summary>.udk files stop opening with this install's UtopiaOverwrite.bat (setup set that up per user).</summary>
        void RemoveUdkAssociation()
        {
            try
            {
                string cmd;
                using (var k = Registry.CurrentUser.OpenSubKey(@"Software\Classes\RLMM.UDKMap\shell\open\command")) cmd = k?.GetValue("") as string;
                if (cmd == null || cmd.IndexOf(dir.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase) < 0) return;   // another install's
                Registry.CurrentUser.DeleteSubKeyTree(@"Software\Classes\RLMM.UDKMap", false);
                using (var ext = Registry.CurrentUser.OpenSubKey(@"Software\Classes\.udk", true))
                    if (ext != null && (ext.GetValue("") as string) == "RLMM.UDKMap") ext.DeleteValue("", false);
                SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero);
            }
            catch { }
        }

        [System.Runtime.InteropServices.DllImport("shell32.dll")] static extern void SHChangeNotify(int e, uint f, IntPtr a, IntPtr b);

        void DeleteFolder()
        {
            for (int attempt = 0; attempt < 3; attempt++)
            {
                try
                {
                    foreach (var f in Directory.EnumerateFiles(dir, "*", SearchOption.AllDirectories))
                    {
                        try { File.SetAttributes(f, FileAttributes.Normal); } catch { }
                    }
                    Directory.Delete(dir, true);
                    return;
                }
                catch (DirectoryNotFoundException) { return; }
                catch (Exception ex)
                {
                    if (attempt == 2) notes.Add("Some files could not be deleted (" + ex.Message + "). You can delete " + dir + " yourself.");
                    else Thread.Sleep(1500);
                }
            }
        }

        void Done()
        {
            working = false;
            finished = true;
            ShowPage(pDone);
            doneTitle.Text = notes.Count == 0 ? "RLMM was removed" : "RLMM was removed, with notes";
            var t = "UDK and the Rocket League map making files were removed from " + dir + ".";
            if (keptMaps != null) t += "\n\nYour maps were moved to " + keptMaps + ".";
            if (notes.Count > 0) t += "\n\n" + string.Join("\n", notes.Select(n => "• " + n));
            doneText.Text = t;
            next.Text = "&Finish";
            next.Enabled = true;
            cancel.Enabled = false;
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (working) { e.Cancel = true; return; }
            base.OnFormClosing(e);
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            base.OnFormClosed(e);
            if (fromTemp)
            {
                // Delete this temporary copy once it has exited.
                try
                {
                    Process.Start(new ProcessStartInfo("cmd.exe", "/c ping 127.0.0.1 -n 3 >nul & del /f /q " + Util.Quote(Application.ExecutablePath))
                    { CreateNoWindow = true, UseShellExecute = false, WorkingDirectory = Path.GetTempPath() });
                }
                catch { }
            }
        }
    }
}
