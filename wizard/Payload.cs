using System;
using System.IO;
using System.Reflection;

namespace RLMMSetup
{
    /// <summary>install.ps1, unpacked to a temp folder on first use. Everything it installs comes from GitHub
    /// (sources.json in the repo), so the exe never needs rebuilding for new templates or assets.</summary>
    static class Payload
    {
        static string dir;
        public static string Dir { get { if (dir == null) Extract(); return dir; } }
        public static string Script => Path.Combine(Dir, "install.ps1");

        static void Extract()
        {
            dir = Path.Combine(Path.GetTempPath(), "RLMM-Setup-" + Guid.NewGuid().ToString("N").Substring(0, 8));
            Directory.CreateDirectory(dir);
            Write("install.ps1", Script);
        }

        /// <summary>A resource embedded by RLMMSetup.csproj (install.ps1, RLMM.ico, logo.png).</summary>
        public static Stream Open(string resource) => Assembly.GetExecutingAssembly().GetManifestResourceStream(resource);

        static void Write(string resource, string path)
        {
            using (var s = Open(resource))
            using (var f = File.Create(path)) s.CopyTo(f);
        }

        public static void Cleanup()
        {
            if (dir == null) return;
            try { Directory.Delete(dir, true); } catch { }
        }
    }
}
