using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace RLMMSetup
{
    /// <summary>
    /// The setup wizard: Welcome (detects an existing UDK) > License > Install location > Installing > Finish, or
    /// Welcome > Updates > Updating > Finish when UDK is already installed. The work is done by install.ps1.
    /// </summary>
    class SetupForm : WizardChrome
    {
        enum Pg { Welcome, License, Location, Update, Progress, Finish }
        Pg current;

        Panel pWelcome, pLicense, pLocation, pUpdate, pProgress, pFinish;
        Label wStatus, wNote;
        readonly RadioButton[] rUpdate = new RadioButton[3];
        RadioButton rNew;
        RichTextBox eula;
        RadioButton rAccept, rDecline;
        LinkLabel eulaRetry;
        TextBox dirBox;
        Label spaceLabel;
        CheckBox cRuntimes, cRocket, cKeep;
        Label updIntro, updStatus;
        ListView comps;
        Label stepLabel, detailLabel;
        ProgressBar overall, sub;
        TextBox log;
        Label fTitle, fText, fNotesTitle;
        TextBox fNotes;
        CheckBox cLaunch;
        LinkLabel fLog;

        // what was found / chosen
        readonly List<string> installs = new List<string>();
        string detectedMode, detectedDir;
        readonly List<string[]> detectedRows = new List<string[]>();
        bool detectDone, eulaLoaded, eulaLoading;
        string eulaFile, targetDir, checkMode;
        bool updating, nothingToDo;
        ScriptRunner detect, eulaRunner, checkRunner, run;

        // progress
        int stepNo, stepTotal, subPct = -1;
        DateTime stepChangedAt;
        readonly List<string> warnings = new List<string>(), failed = new List<string>();
        string error, logPath;
        bool cancelled, exitAllowed;
        readonly StringBuilder fullLog = new StringBuilder();
        readonly Timer dlTimer = new Timer { Interval = 500 };
        string dlPath, dlLabel;
        long dlSize, dlLastBytes = -1;
        bool dlApprox;
        DateTime dlLastTime;
        double dlRate;

        public SetupForm()
        {
            BuildWelcome();
            BuildLicense();
            BuildLocation();
            BuildUpdate();
            BuildProgress();
            BuildFinish();
            FinishLayout();

            back.Click += (s, e) => GoBack();
            next.Click += (s, e) => GoNext();
            cancel.Click += (s, e) => Close();
            dlTimer.Tick += (s, e) => TickDownload();
            if (Program.SelfTestDir != null)
            {
                StartPosition = FormStartPosition.Manual;
                Location = new Point(-20000, -20000);
                ShowInTaskbar = false;
            }
            GoWelcome();
        }

        // ------------------------------------------------------------------------------------------ pages
        void BuildWelcome()
        {
            pWelcome = NewPage(true);
            int w = PageWidth(true);
            var st = Stack(pWelcome);
            Para(st, "Welcome to RLMM Setup", w, 0, Big);
            Para(st, "This installs UDK, the editor Rocket League maps are made in, and sets it up for Rocket League map making:", w, 12);
            Para(st, "\u2022  UDK 2015 (the February 2015 build) and the runtimes it needs\n" +
                     "\u2022  Dummy classes, compiled and checked\n" +
                     "\u2022  Not So Dummy Assets and the classic dummy assets\n" +
                     "\u2022  Map templates: Soccar, Mannfield (Aceman3000's Complexity), Hoops, Dropshot, Test\n" +
                     "\u2022  Map testing in Rocket League, and shortcuts", w, 8);
            wStatus = Para(st, "Looking for an existing UDK install...", w, 18, Bold(9F));
            for (int i = 0; i < rUpdate.Length; i++)
            {
                rUpdate[i] = new RadioButton { AutoSize = true, MaximumSize = new Size(w, 0), Visible = false, Margin = new Padding(0, 6, 0, 0) };
                st.Controls.Add(rUpdate[i]);
            }
            rNew = new RadioButton { AutoSize = true, Text = "Install a new copy of UDK in another folder", Visible = false, Margin = new Padding(0, 6, 0, 0) };
            st.Controls.Add(rNew);
            wNote = Para(st, "", w, 14);
            wNote.ForeColor = SystemColors.GrayText;
        }

        void BuildLicense()
        {
            pLicense = NewPage(false);
            int w = PageWidth(false);
            var st = Stack(pLicense);
            Para(st, "UDK is made by Epic Games. Please read its End User License Agreement; you need to accept it to install UDK.", w);
            eula = new RichTextBox { ReadOnly = true, BackColor = SystemColors.Window, Size = new Size(w, 214), Margin = new Padding(0, 8, 0, 0), ScrollBars = RichTextBoxScrollBars.Vertical };
            st.Controls.Add(eula);
            eulaRetry = new LinkLabel { Text = "Try again", AutoSize = true, Visible = false, Margin = new Padding(0, 4, 0, 0) };
            eulaRetry.LinkClicked += (s, e) => StartEula();
            st.Controls.Add(eulaRetry);
            rAccept = new RadioButton { Text = "I &accept the agreement", AutoSize = true, Enabled = false, Margin = new Padding(0, 8, 0, 0) };
            rDecline = new RadioButton { Text = "I &do not accept the agreement", AutoSize = true, Checked = true, Margin = new Padding(0, 4, 0, 0) };
            rAccept.CheckedChanged += (s, e) => { if (current == Pg.License) next.Enabled = rAccept.Checked; };
            st.Controls.Add(rAccept);
            st.Controls.Add(rDecline);
        }

        void BuildLocation()
        {
            pLocation = NewPage(false);
            int w = PageWidth(false);
            var st = Stack(pLocation);
            Para(st, "UDK will be installed in this folder. Use an empty or new folder without spaces in its path (UDK's tools don't work with spaces).", w);
            var row = new Panel { Size = new Size(w, 27), Margin = new Padding(0, 10, 0, 0) };
            dirBox = new TextBox { Location = new Point(0, 2), Width = w - 100 };
            var browse = new Button { Text = "B&rowse...", Location = new Point(w - 92, 0), Size = new Size(92, 27) };
            browse.Click += (s, e) => Browse();
            dirBox.TextChanged += (s, e) => UpdateSpace();
            row.Controls.Add(dirBox);
            row.Controls.Add(browse);
            st.Controls.Add(row);
            spaceLabel = Para(st, "", w, 6);
            Para(st, "Options", w, 16, Bold(9F));
            cRuntimes = Check(st, "Install the Visual C++ 2010 and DirectX 9 runtimes UDK needs (recommended)", true);
            cRocket = Check(st, "Set up map testing in Rocket League (Utopia Retro is backed up first)", true);
            cKeep = Check(st, "Keep the downloaded files afterwards (about 5.5 GB)", false);
            var note = Para(st, "Setup downloads about 5.5 GB and takes 20 to 40 minutes, mostly downloading. You can keep using your PC meanwhile.", w, 16);
            note.ForeColor = SystemColors.GrayText;
        }

        CheckBox Check(Control parent, string text, bool on)
        {
            var c = new CheckBox { Text = text, Checked = on, AutoSize = true, Margin = new Padding(0, 6, 0, 0) };
            parent.Controls.Add(c);
            return c;
        }

        void BuildUpdate()
        {
            pUpdate = NewPage(false);
            int w = PageWidth(false);
            var st = Stack(pUpdate);
            updIntro = Para(st, "", w);
            comps = new ListView
            {
                View = View.Details, FullRowSelect = true, HeaderStyle = ColumnHeaderStyle.Nonclickable, MultiSelect = false,
                Size = new Size(w, 196), Margin = new Padding(0, 10, 0, 0),
            };
            comps.Columns.Add("Component");
            comps.Columns.Add("Installed");
            comps.Columns.Add("Latest");
            comps.Columns.Add("Action");
            st.Controls.Add(comps);
            updStatus = Para(st, "", w, 10);
        }

        void BuildProgress()
        {
            pProgress = NewPage(false);
            int w = PageWidth(false);
            var st = Stack(pProgress);
            stepLabel = Para(st, "Starting...", w, 0, Bold(9F));
            overall = new ProgressBar { Size = new Size(w, 20), Margin = new Padding(0, 8, 0, 0), Maximum = 1000 };
            st.Controls.Add(overall);
            detailLabel = new Label { AutoSize = false, AutoEllipsis = true, Size = new Size(w, 18), Margin = new Padding(0, 12, 0, 0) };
            st.Controls.Add(detailLabel);
            sub = new ProgressBar { Size = new Size(w, 12), Margin = new Padding(0, 4, 0, 0), Style = ProgressBarStyle.Marquee, MarqueeAnimationSpeed = 30 };
            st.Controls.Add(sub);
            log = new TextBox
            {
                Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, WordWrap = true, BackColor = SystemColors.Window,
                Size = new Size(w, 186), Margin = new Padding(0, 14, 0, 0), Font = new Font("Consolas", 8.5F),
            };
            st.Controls.Add(log);
        }

        void BuildFinish()
        {
            pFinish = NewPage(true);
            int w = PageWidth(true);
            var st = Stack(pFinish);
            fTitle = Para(st, "", w, 0, Big);
            fText = Para(st, "", w, 12);
            fNotesTitle = Para(st, "Notes", w, 12, Bold(9F));
            fNotes = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, BackColor = SystemColors.Window, Size = new Size(w, 92), Margin = new Padding(0, 4, 0, 0) };
            st.Controls.Add(fNotes);
            cLaunch = new CheckBox { Text = "Open UDK now", AutoSize = true, Checked = true, Margin = new Padding(0, 14, 0, 0) };
            st.Controls.Add(cLaunch);
            fLog = new LinkLabel { Text = "Open the setup log", AutoSize = true, Margin = new Padding(0, 10, 0, 0) };
            fLog.LinkClicked += (s, e) => { if (logPath != null) Util.OpenAsUser(logPath); };
            st.Controls.Add(fLog);
        }

        // ------------------------------------------------------------------------------------------ navigation
        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            StartDetection();
            StartEula();
            if (Program.SelfTestDir != null)
            {
                var t = new Timer { Interval = 500 };
                t.Tick += (s, a) => SelfTestTick();
                t.Start();
            }
        }

        void GoWelcome()
        {
            current = Pg.Welcome;
            ShowPage(pWelcome);
            back.Visible = true; back.Enabled = false;
            next.Text = "&Next >";
            UpdateWelcome();
        }

        void GoLicense()
        {
            current = Pg.License;
            ShowPage(pLicense, "License Agreement", "UDK End User License Agreement (Epic Games)");
            back.Enabled = true;
            next.Text = "&Next >";
            next.Enabled = rAccept.Checked;
        }

        void GoLocation()
        {
            current = Pg.Location;
            ShowPage(pLocation, "Install Location", "Where should UDK be installed?");
            back.Enabled = true;
            next.Text = "&Install";
            next.Enabled = true;
            if (dirBox.Text.Length == 0)
            {
                string d = @"C:\UDK\RLMM";
                for (int i = 2; Directory.Exists(d) && Directory.EnumerateFileSystemEntries(d).Any(); i++) d = @"C:\UDK\RLMM" + i;
                dirBox.Text = d;
            }
            UpdateSpace();
        }

        void GoUpdate()
        {
            current = Pg.Update;
            ShowPage(pUpdate, "Updates", "Installed components compared with the latest versions");
            back.Enabled = true;
            updIntro.Text = "UDK is installed at " + targetDir + ".";
            SizeColumns();
            if (string.Equals(targetDir, detectedDir, StringComparison.OrdinalIgnoreCase) && detectedRows.Count > 0)
            {
                FillUpdate(detectedRows, detectedMode, null);
                return;
            }
            comps.Items.Clear();
            updStatus.Text = "Checking for updates...";
            next.Enabled = false;
            var rows = new List<string[]>();
            string mode = null, err = null;
            checkRunner = new ScriptRunner();
            checkRunner.Message += (k, v) =>
            {
                if (k == "COMP") rows.Add(v.Split('|'));
                else if (k == "MODE") mode = v.Split('|')[0];
                else if (k == "ERROR") err = v;
            };
            checkRunner.Exited += code => { if (current == Pg.Update) FillUpdate(rows, mode, err); };
            checkRunner.Start("-NoElevate", "-Yes", "-CheckOnly", "-InstallDir", targetDir);
        }

        void GoBack()
        {
            if (current == Pg.License || current == Pg.Update) GoWelcome();
            else if (current == Pg.Location) GoLicense();
        }

        void GoNext()
        {
            switch (current)
            {
                case Pg.Welcome:
                    int i = Array.FindIndex(rUpdate, r => r.Visible && r.Checked);
                    if (i >= 0) { targetDir = installs[i]; updating = true; GoUpdate(); }
                    else { updating = false; GoLicense(); }
                    break;
                case Pg.License:
                    if (rAccept.Checked) GoLocation();
                    break;
                case Pg.Location:
                    if (ValidateFolder()) StartRun(true);
                    break;
                case Pg.Update:
                    if (nothingToDo) { exitAllowed = true; Close(); }
                    else StartRun(checkMode == "resume");
                    break;
                case Pg.Finish:
                    if (cLaunch.Visible && cLaunch.Checked && Util.ShortcutPointsInto(Util.DesktopShortcut, targetDir)) Util.OpenAsUser(Util.DesktopShortcut);
                    exitAllowed = true;
                    Close();
                    break;
            }
        }

        // ------------------------------------------------------------------------------------------ welcome: detection
        void StartDetection()
        {
            detect = new ScriptRunner();
            detect.Message += (k, v) =>
            {
                if (k == "INSTALLS") { installs.Clear(); installs.AddRange(v.Split('|').Where(x => x.Length > 0)); }
                else if (k == "MODE") { var p = v.Split(new[] { '|' }, 2); detectedMode = p[0]; detectedDir = p.Length > 1 ? p[1] : ""; }
                else if (k == "COMP") detectedRows.Add(v.Split('|'));
            };
            detect.Exited += code => { detectDone = true; if (current == Pg.Welcome) UpdateWelcome(); };
            detect.Start("-NoElevate", "-Yes", "-CheckOnly");
        }

        void UpdateWelcome()
        {
            if (!detectDone)
            {
                wStatus.Text = "Looking for an existing UDK install...";
                next.Enabled = false;
                return;
            }
            next.Enabled = true;
            if (installs.Count == 0)
            {
                wStatus.Text = "Click Next to continue.";
                wNote.Text = "Setup downloads about 5.5 GB, so it takes 20 to 40 minutes.";
                return;
            }
            wStatus.Text = installs.Count == 1 ? "UDK is already installed on this PC. What would you like to do?" : "UDK is installed in more than one place on this PC. What would you like to do?";
            bool any = false;
            for (int i = 0; i < rUpdate.Length; i++)
            {
                if (i < installs.Count)
                {
                    bool unfinished = detectedMode == "resume" && string.Equals(installs[i], detectedDir, StringComparison.OrdinalIgnoreCase);
                    rUpdate[i].Text = (unfinished ? "Finish the unfinished install at " : "Update the install at ") + installs[i];
                    rUpdate[i].Visible = true;
                    any |= rUpdate[i].Checked;
                }
                else rUpdate[i].Visible = false;
            }
            rNew.Visible = true;
            if (!any && !rNew.Checked) rUpdate[0].Checked = true;
            wNote.Text = "Updating brings the dummy classes, assets and map templates up to date. Your maps are not touched.";
        }

        // ------------------------------------------------------------------------------------------ license
        void StartEula()
        {
            if (eulaLoading || eulaLoaded) return;
            eulaLoading = true;
            eulaRetry.Visible = false;
            eula.Text = "Loading the license from Epic's UDK installer...";
            eulaFile = Path.Combine(Payload.Dir, "UDK-EULA.rtf");
            string err = null;
            eulaRunner = new ScriptRunner();
            eulaRunner.Message += (k, v) => { if (k == "ERROR") err = v; };
            eulaRunner.Exited += code =>
            {
                eulaLoading = false;
                if (code == 0 && File.Exists(eulaFile) && new FileInfo(eulaFile).Length > 1000)
                {
                    try
                    {
                        eula.LoadFile(eulaFile, RichTextBoxStreamType.RichText);
                        eulaLoaded = true;
                        rAccept.Enabled = true;
                        return;
                    }
                    catch (Exception ex) { err = ex.Message; }
                }
                eula.Text = "The license could not be loaded" + (err != null ? " (" + err + ")" : "") + ".\n\n" +
                            "Setup needs an internet connection: it downloads UDK and the Rocket League files. Check your connection and try again.";
                eulaRetry.Visible = true;
            };
            eulaRunner.Start("-NoElevate", "-SaveEula", eulaFile);
        }

        // ------------------------------------------------------------------------------------------ location
        void Browse()
        {
            using (var d = new FolderBrowserDialog { Description = "Choose a folder for UDK. Its path can't contain spaces.", ShowNewFolderButton = true })
            {
                if (d.ShowDialog(this) != DialogResult.OK) return;
                string p = d.SelectedPath;
                bool empty = !Directory.EnumerateFileSystemEntries(p).Any();
                dirBox.Text = empty ? p : Path.Combine(p, "RLMM");
            }
        }

        void UpdateSpace()
        {
            string d = dirBox.Text.Trim().Trim('"');
            long free = -1;
            string root = null;
            try { if (Path.IsPathRooted(d)) { root = Path.GetPathRoot(Path.GetFullPath(d)); free = Util.FreeSpace(d); } } catch { }
            string text = "Needs about 11 GB, and 20 GB free while setup runs.";
            if (free >= 0) text += " Free space on " + root.TrimEnd('\\') + " " + Util.Size(free) + ".";
            spaceLabel.Text = text;
            spaceLabel.ForeColor = free >= 0 && free < 20L * (1L << 30) ? Color.Firebrick : SystemColors.ControlText;
        }

        bool ValidateFolder()
        {
            string d = dirBox.Text.Trim().Trim('"');
            string problem = null;
            try
            {
                if (d.Length == 0 || !Path.IsPathRooted(d) || d.StartsWith(@"\\")) problem = @"Enter the full path of a folder on this PC, like C:\UDK\RLMM.";
                else
                {
                    d = Path.GetFullPath(d).TrimEnd('\\');
                    string root = Path.GetPathRoot(d);
                    if (d.Contains(' ')) problem = "The folder's path can't contain spaces: UDK's script compiler and tools break on them.";
                    else if (string.Equals(root.TrimEnd('\\'), d, StringComparison.OrdinalIgnoreCase)) problem = @"Choose a folder, not the root of a drive (for example " + root + @"UDK\RLMM).";
                    else if (!Directory.Exists(root)) problem = "Drive " + root + " was not found.";
                    else if (Directory.Exists(d) && Directory.EnumerateFileSystemEntries(d).Any())
                        problem = File.Exists(Path.Combine(d, @"Binaries\Win64\UDK.exe"))
                            ? "UDK is already installed in this folder. Go back to the first page to update it, or choose another folder."
                            : "This folder is not empty. Choose an empty or new folder.";
                    else
                    {
                        long free = Util.FreeSpace(d);
                        if (free >= 0 && free < 16L * (1L << 30)) problem = "There is only " + Util.Size(free) + " free on " + root + ". Setup needs about 20 GB while it runs.";
                    }
                }
            }
            catch (Exception ex) { problem = "That folder can't be used: " + ex.Message; }
            if (problem != null)
            {
                if (Program.SelfTestDir == null) MessageBox.Show(this, problem, "RLMM Setup", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                else Log("Folder rejected: " + problem);
                return false;
            }
            targetDir = d;
            return true;
        }

        // ------------------------------------------------------------------------------------------ updates
        void SizeColumns()
        {
            float k = DeviceDpi / 96f;
            int w = comps.ClientSize.Width - (int)(4 * k);
            comps.Columns[0].Width = (int)(w * 0.38); comps.Columns[1].Width = (int)(w * 0.23);
            comps.Columns[2].Width = (int)(w * 0.23); comps.Columns[3].Width = w - comps.Columns[0].Width - comps.Columns[1].Width - comps.Columns[2].Width;
        }

        void FillUpdate(List<string[]> rows, string mode, string err)
        {
            checkMode = mode;
            comps.Items.Clear();
            int todo = 0;
            foreach (var r in rows)
            {
                if (r.Length < 5) continue;
                string action = r[4] == "ok" ? "Up to date" : r[4] == "update" ? "Update" : r[4] == "repair" ? "Repair" : "Install";
                if (r[4] != "ok") todo++;
                var item = new ListViewItem(new[] { r[1], r[2], r[3], action });
                if (r[4] != "ok") item.Font = new Font(comps.Font, FontStyle.Bold);
                comps.Items.Add(item);
            }
            next.Enabled = true;
            nothingToDo = false;
            if (err != null) { updStatus.Text = "Could not check for updates: " + err; next.Enabled = false; return; }
            if (mode == "resume")
            {
                updIntro.Text = "An unfinished install was found at " + targetDir + ". Setup will finish it; the steps already done are skipped.";
                updStatus.Text = "";
                next.Text = "&Install";
            }
            else if (todo == 0)
            {
                updStatus.Text = "Everything is up to date.";
                next.Text = "&Close";
                nothingToDo = true;
            }
            else
            {
                updStatus.Text = (todo == 1 ? "1 component" : todo + " components") + " will be installed, updated or repaired. Your maps are not touched.";
                next.Text = "&Update";
            }
        }

        // ------------------------------------------------------------------------------------------ install / update run
        void StartRun(bool fresh)
        {
            while (Util.UdkRunningFrom(targetDir))
            {
                if (Program.SelfTestDir != null) return;
                if (MessageBox.Show(this, "UDK is running from " + targetDir + ". Save your work and close UDK, then click OK.", "RLMM Setup",
                        MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return;
            }
            var args = new List<string> { "-NoElevate", "-Yes", "-InstallDir", targetDir, "-SetupExe", Application.ExecutablePath };
            if (fresh)
            {
                if (!updating) args.Add("-AcceptEula");
                if (!cRuntimes.Checked) args.Add("-SkipPrerequisites");
                if (!cRocket.Checked) args.Add("-SkipRocketLeague");
                if (cKeep.Checked) args.Add("-KeepDownloads");
            }
            if (Program.CacheDir != null) { args.Add("-CacheDir"); args.Add(Program.CacheDir); }

            current = Pg.Progress;
            ShowPage(pProgress, updating ? "Updating" : "Installing",
                (updating ? "Please wait while RLMM Setup updates UDK at " : "Please wait while RLMM Setup installs UDK to ") + targetDir + ".");
            back.Enabled = false;
            next.Enabled = false;
            Log("RLMM Setup " + Program.Version + ", " + DateTime.Now.ToString("yyyy-MM-dd HH:mm") + (updating ? ", updating " : ", installing to ") + targetDir);
            run = new ScriptRunner();
            run.Message += OnRunMessage;
            run.Line += s => Log(s);
            run.Exited += OnRunExited;
            run.Start(args.ToArray());
        }

        void OnRunMessage(string kind, string v)
        {
            switch (kind)
            {
                case "STEP":
                {
                    var p = v.Split(new[] { '|' }, 3);
                    int.TryParse(p[0], out stepNo);
                    if (p.Length > 1) int.TryParse(p[1], out stepTotal);
                    string text = p.Length > 2 ? p[2] : "";
                    stepLabel.Text = "Step " + stepNo + " of " + stepTotal + ": " + text;
                    stepChangedAt = DateTime.Now;
                    SetSub(-1, "");
                    Log("");
                    Log("[" + stepNo + "/" + stepTotal + "] " + text);
                    break;
                }
                case "STATUS":
                    if (dlPath != null) break;
                    if (v.Length == 0) SetSub(-1, null);
                    else
                    {
                        var m = Regex.Match(v, @"(\d{1,3})\s*%");
                        SetSub(m.Success ? int.Parse(m.Groups[1].Value) : -1, v);
                    }
                    break;
                case "INFO":
                    Log("    " + v);
                    if (dlPath == null) detailLabel.Text = v;
                    break;
                case "OK":
                    Log("  OK  " + v);
                    if (dlPath == null) detailLabel.Text = v;
                    break;
                case "WARN":
                    Log("  !   " + v);
                    if (!warnings.Contains(v)) warnings.Add(v);
                    break;
                case "DL":
                    if (v.Length == 0) StopDownloadWatch();
                    else
                    {
                        var p = v.Split(new[] { '|' }, 4);
                        long.TryParse(p[0], out long size);
                        StartDownloadWatch(size, p.Length > 1 && p[1] == "1", p.Length > 2 ? p[2] : null, p.Length > 3 ? p[3] : "");
                    }
                    break;
                case "FAILED":
                    if (!failed.Contains(v)) failed.Add(v);
                    break;
                case "ERROR":
                    error = v;
                    Log("  ERROR  " + v);
                    break;
                case "COMP":
                {
                    var c = v.Split('|');
                    if (c.Length >= 5) Log("    " + c[1] + ": " + c[2] + " -> " + c[3] + " (" + c[4] + ")");
                    break;
                }
                case "SAY":
                    if (v.Trim().Length > 0 && !v.Trim().StartsWith("===")) Log(v.TrimEnd());
                    break;
            }
        }

        void OnRunExited(int code)
        {
            StopDownloadWatch();
            if (!cancelled && error == null && code != 0) error = "The setup script stopped unexpectedly (exit code " + code + ").";
            SaveLog();
            GoFinish();
        }

        void SetSub(int pct, string text)
        {
            subPct = pct;
            if (pct < 0) { if (sub.Style != ProgressBarStyle.Marquee) sub.Style = ProgressBarStyle.Marquee; }
            else
            {
                if (sub.Style != ProgressBarStyle.Continuous) sub.Style = ProgressBarStyle.Continuous;
                sub.Value = Math.Max(0, Math.Min(100, pct));
            }
            if (text != null) detailLabel.Text = text;
            if (stepTotal > 0)
            {
                overall.Maximum = stepTotal * 100;
                overall.Value = Math.Max(0, Math.Min(overall.Maximum, (stepNo - 1) * 100 + Math.Max(0, pct)));
            }
        }

        void StartDownloadWatch(long size, bool approx, string path, string label)
        {
            dlPath = path; dlSize = size; dlApprox = approx; dlLabel = label;
            dlLastBytes = -1; dlRate = 0;
            dlTimer.Start();
            TickDownload();
        }

        void StopDownloadWatch()
        {
            if (dlPath == null) return;
            dlTimer.Stop();
            dlPath = null;
            SetSub(-1, "");
        }

        void TickDownload()
        {
            if (dlPath == null) return;
            long bytes = 0;
            try
            {
                if (Directory.Exists(dlPath))   // many files downloading into one folder (Not So Dummy Assets)
                    foreach (var f in new DirectoryInfo(dlPath).EnumerateFiles("*", SearchOption.AllDirectories)) bytes += f.Length;
                else { var fi = new FileInfo(dlPath); if (fi.Exists) bytes = fi.Length; }
            }
            catch { }
            var now = DateTime.UtcNow;
            if (dlLastBytes < 0) { dlLastBytes = bytes; dlLastTime = now; }
            else
            {
                double dt = (now - dlLastTime).TotalSeconds;
                if (dt >= 1)
                {
                    double r = Math.Max(0, (bytes - dlLastBytes) / dt);
                    dlRate = dlRate <= 0 ? r : dlRate * 0.7 + r * 0.3;
                    dlLastBytes = bytes; dlLastTime = now;
                }
            }
            string text = "Downloading " + dlLabel + ": " + Util.Size(bytes);
            int pct = -1;
            if (dlSize > 0)
            {
                text += (dlApprox ? " of about " : " of ") + Util.Size(dlSize);
                pct = (int)Math.Min(dlApprox ? 99 : 100, bytes * 100 / dlSize);
            }
            if (dlRate > 10 * 1024)
            {
                text += ", " + Util.Size(dlRate) + "/s";
                if (dlSize > bytes)
                {
                    double min = (dlSize - bytes) / dlRate / 60;
                    text += min < 1 ? ", less than a minute left" : ", about " + Math.Ceiling(min) + " min left";
                }
            }
            SetSub(pct, text);
        }

        void Log(string s)
        {
            fullLog.AppendLine(s);
            if (log.TextLength > 200000) log.Text = log.Text.Substring(log.TextLength - 100000);
            log.AppendText(s + Environment.NewLine);
        }

        void SaveLog()
        {
            try
            {
                string dir = targetDir != null && Directory.Exists(targetDir) ? Path.Combine(targetDir, @"RLMM-Setup\logs") : Path.GetTempPath();
                Directory.CreateDirectory(dir);
                logPath = Path.Combine(dir, "setup-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".log");
                File.WriteAllText(logPath, fullLog.ToString());
            }
            catch { logPath = null; }
        }

        // ------------------------------------------------------------------------------------------ finish
        void GoFinish()
        {
            current = Pg.Finish;
            ShowPage(pFinish);
            back.Visible = false;
            cancel.Enabled = false;
            next.Text = "&Finish";
            next.Enabled = true;
            cLaunch.Visible = false;
            if (cancelled)
            {
                fTitle.Text = "Setup was cancelled";
                fText.Text = "Run RLMM Setup again to continue: the steps that already finished are skipped.";
            }
            else if (error != null)
            {
                fTitle.Text = "Setup could not finish";
                fText.Text = error + "\n\nRun RLMM Setup again to resume: the steps that already finished are skipped. The setup log has the details.";
            }
            else
            {
                bool ok = failed.Count == 0;
                fTitle.Text = updating ? (ok ? "Update complete" : "Update finished with problems")
                                       : (ok ? "UDK is ready for Rocket League map making" : "Setup finished with problems");
                var t = new StringBuilder();
                if (!ok) t.Append("Not installed: " + string.Join(", ", failed) + ". Run RLMM Setup again to retry.\n\n");
                t.Append("UDK is installed at " + targetDir + ".\n\n");
                t.Append("For a stadium, start with File > New Level > Soccar Template, or Mannfield Template (Aceman3000's Complexity). To play a map in Rocket League, drag the saved .udk onto \"Test map in Rocket League.bat\" in the Maps folder.\n\n");
                t.Append("Opening a stadium template (or any map built on Rocket League's assets) shows \"Load Errors\" and \"Updating Changed Materials\". That is normal: click OK on the errors and Cancel on the materials. Never resave the dummy asset packages: UDK can't save them and crashes. To update or repair them, use Start > RLMM > Update RLMM.");
                fText.Text = t.ToString();
                cLaunch.Visible = File.Exists(Util.DesktopShortcut) && Util.ShortcutPointsInto(Util.DesktopShortcut, targetDir);
            }
            fNotesTitle.Visible = fNotes.Visible = warnings.Count > 0;
            fNotes.Text = string.Join(Environment.NewLine, warnings.Select(x => "\u2022 " + x));
            fLog.Visible = logPath != null;
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (!exitAllowed && current != Pg.Finish)
            {
                if (run != null && run.Running)
                {
                    e.Cancel = true;
                    if (cancelled) return;
                    if (Program.SelfTestDir != null || MessageBox.Show(this,
                            "Stop setup now? Run RLMM Setup again later to continue; the steps that already finished are skipped.",
                            "RLMM Setup", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) == DialogResult.Yes)
                    {
                        cancelled = true;
                        stepLabel.Text = "Stopping...";
                        run.Kill();
                    }
                    return;
                }
                if (Program.SelfTestDir == null && MessageBox.Show(this, "Exit RLMM Setup? Nothing has been installed yet.", "RLMM Setup",
                        MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) != DialogResult.Yes)
                {
                    e.Cancel = true;
                    return;
                }
            }
            foreach (var r in new[] { detect, eulaRunner, checkRunner }) r?.Kill();
            base.OnFormClosing(e);
        }

        // ------------------------------------------------------------------------------------------ /selftest
        int stStage, stShotStep;

        void SelfTestTick()
        {
            switch (stStage)
            {
                case 0:
                    if (!detectDone || eulaLoading) return;
                    Util.Snapshot(this, "1-welcome");
                    int idx = installs.FindIndex(d => string.Equals(d, Program.SelfTestDir.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase));
                    if (idx >= 0 && idx < rUpdate.Length) { rUpdate[idx].Checked = true; GoNext(); stStage = 10; return; }
                    if (rNew.Visible) rNew.Checked = true;
                    GoNext();
                    stStage = 1;
                    return;
                case 1:
                    Util.Snapshot(this, "2-license");
                    if (!eulaLoaded) { exitAllowed = true; Close(); return; }
                    rAccept.Checked = true;
                    GoNext();
                    stStage = 2;
                    return;
                case 2:
                    dirBox.Text = Program.SelfTestDir;
                    cKeep.Checked = true;
                    Util.Snapshot(this, "3-location");
                    GoNext();
                    if (current != Pg.Progress) { exitAllowed = true; Close(); return; }
                    stStage = 3;
                    return;
                case 3:
                    if (current == Pg.Finish) { stStage = 4; return; }
                    if (stepNo > 0 && stepNo != stShotStep && (DateTime.Now - stepChangedAt).TotalSeconds >= 3)
                    {
                        Util.Snapshot(this, "4-progress-" + stepNo.ToString("00"));
                        stShotStep = stepNo;
                    }
                    return;
                case 4:
                    Util.Snapshot(this, "9-finish");
                    exitAllowed = true;
                    Close();
                    return;
                case 10:
                    if (checkRunner != null && checkRunner.Running) return;
                    Util.Snapshot(this, "5-update");
                    GoNext();
                    stStage = current == Pg.Progress ? 3 : 99;
                    return;
            }
        }
    }
}
