using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;

namespace RLMMSetup
{
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
}
