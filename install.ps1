<#
    RLMM Setup: one command to install UDK for Rocket League map making.

    Installs UDK 2015 (the editor Rocket League maps are built in) and sets it up for Rocket League: compiled dummy
    classes, dummy assets, Not So Dummy Assets, the map templates (Soccar, Mannfield, Hoops, Dropshot, Test) with
    Aceman3000's Misc assets, a drag-and-drop "test in Rocket League" script and shortcuts.

    Run it again any time: when UDK is already installed it compares every component with the latest upstream version
    and offers to update what changed.

    Quick start (PowerShell):
        irm https://raw.githubusercontent.com/armand0e/rlmm-setup/main/install.ps1 | iex

    Options (when run as a file: powershell -ExecutionPolicy Bypass -File install.ps1 -InstallDir D:\UDK\RLMM):
        -InstallDir <path>    where UDK goes (default C:\UDK\RLMM, no spaces)
        -ProjectName <name>   UDK game project name (default RLMM)
        -CacheDir <path>      download folder; files already there are verified and reused
        -AcceptEula           accept the UDK EULA without the prompt (only if you have read it)
        -Yes                  answer yes to every other prompt
        -KeepDownloads        keep the downloaded installer and zips (about 9 GB)
        -SkipPrerequisites    skip the Visual C++ 2010 and DirectX 9 runtimes
        -SkipRocketLeague     do not touch the Rocket League folder
        -CheckOnly            only report installed vs latest versions
#>

function Invoke-RLMMSetup {
    [CmdletBinding()]
    param(
        [string]$InstallDir,
        [string]$ProjectName = 'RLMM',
        [string]$CacheDir,
        [switch]$AcceptEula,
        [switch]$Yes,
        [switch]$KeepDownloads,
        [switch]$SkipPrerequisites,
        [switch]$SkipRocketLeague,
        [switch]$CheckOnly,
        [switch]$NoElevate,
        [switch]$Elevated,
        [string]$LocalAssets,      # set automatically when run from a copy of the repo: its assets\ folder
        [string]$SetupExe,         # set by RLMM-Setup.exe: copied into the install for the Update shortcut and uninstall
        [string]$SaveEula          # write Epic's EULA (RTF) to this path and stop (used by RLMM-Setup.exe)
    )

    Set-StrictMode -Version 2
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $SetupVersion = '1.1.0'
    $DefaultInstallDir = 'C:\UDK\RLMM'
    $RepoRaw = 'https://raw.githubusercontent.com/armand0e/rlmm-setup/main'

    # --------------------------------------------------------------------------------------------------------
    # Sources. GitHub components resolve to their latest commit at run time; files are pinned by size/MD5.
    # --------------------------------------------------------------------------------------------------------
    $UdkInstaller = @{
        # Google Drive first: ~50 MB/s. archive.org caps each user at ~0.5-1.5 MB/s (more connections don't help),
        # so it is only the fallback for when Drive's download quota for the file is used up.
        Urls = @('https://drive.usercontent.google.com/download?id=1z9C3t6nKW1utWilVshODxyGcucxuzbOW&export=download&confirm=t',
                 'https://drive.usercontent.google.com/download?id=1ozqiKBgcWSgcq7X5J6g0AErKyevjMRwd&export=download&confirm=t',
                 'https://archive.org/download/udkinstaller/UDKInstall-2015-02.exe')
        File = 'UDKInstall-2015-02.exe'
        Size = [long]2001725784
        Md5  = '790744C95A74626E7C381CCF13C88F9D'
        # Where Epic's EULA sits inside the installer (local header of Binaries/InstallData/EULA.INT.rtf), so it can be
        # shown before the 2 GB download.
        EulaOffset = [long]21659229; EulaCompressed = [long]41421; EulaCrc = [uint32]606909622
    }
    # Order matters: Not So Dummy Assets and Misc before the classic dummy assets (which only fill gaps).
    $Components = [ordered]@{
        # Approx: typical archive size, only for progress display (GitHub archives are sent without a length).
        # Dummy classes are a merge of two repos. RocketLeagueMapmaking/RL-Dummy-Classes is hand-made for the editor:
        # sprites for spawns and boost pads, the goal and FX subobjects that the stadium packages and templates
        # reference. ghostrider-05/RL-dummy-classes2 is generated from the current Rocket League build and has the
        # ~1,400 classes the first one lacks (ProductAsset_*, WheelAsset*...); without those UDK logs ~30,000 load
        # warnings and re-indexes the assets at every start. The community classes win wherever both have a class,
        # except where that breaks the compile (Install-DummyClasses). Raise Merge when the merge rules change.
        DummyClasses = @{ Title = 'Dummy classes'; Kind = 'classes'; Repo = 'RocketLeagueMapmaking/RL-Dummy-Classes'
                          Generated = 'ghostrider-05/RL-dummy-classes2'; Merge = 1; Approx = [long]4MB }
        NotSoDummy   = @{ Title = 'Not So Dummy Assets'; Kind = 'github'; Repo = 'RocketLeagueMapmaking/RL_NotSoDummyAssets'; Approx = [long]3307434166
                          Fallback = 'https://rocketleaguemapmaking.com/resources/RL_NotSoDummyAssets-main.zip' }
        MiscAssets   = @{ Title = 'Misc assets (boost pads, crossbar)'; Kind = 'file'; File = 'Misc.zip'; Size = [long]4435
                          Md5 = '00143177BF26D54BADD34DFEA80D7CFD'; Url = "$RepoRaw/assets/Misc.zip"; Version = 'v1.0.6' }
        DummyAssets  = @{ Title = 'Dummy assets (gap fill)'; Kind = 'github'; Repo = 'RocketLeagueMapmaking/RL_DummyAssets'; Approx = [long]102MB }
        # Map templates: Soccar, Hoops, Dropshot and Test by Mr. Swaggles (Dropshot polished by Aceman3000), Mannfield
        # by Aceman3000 (his Complexity stadium). Built by tools\make_templates_zip.py, which applies the cubemap fix
        # (MaxCaptureTime 2) and adds Mannfield and Dropshot to UDK_RL_Setup's New Level index (MapTemplateIndex.upk).
        MapTemplates = @{ Title = 'Map templates'; Kind = 'file'; File = 'Templates.zip'; Size = [long]14275065
                          Md5 = 'E6F360169D1FB56977FACB54CB0885F2'; Url = "$RepoRaw/assets/Templates.zip"; Version = '2026-11 cubemap fix' }
    }

    # --------------------------------------------------------------------------------------------------------
    # Console helpers
    # --------------------------------------------------------------------------------------------------------
    $script:StepNo = 0; $script:StepTotal = 0
    $script:Warnings = New-Object System.Collections.Generic.List[string]
    # RLMM-Setup.exe sets RLMM_WIZARD=1 and reads one '@@KIND|fields' line per event instead of console text.
    $script:Wiz = $env:RLMM_WIZARD -eq '1'
    $script:SizeHint = [long]0
    function Emit([string]$Kind, [string]$Text = '') { Write-Host ('@@' + $Kind + '|' + ($Text -replace '[\r\n]+', ' ')) }
    function Say([string]$Text, [string]$Color = 'Gray') { if ($script:Wiz) { Emit 'SAY' $Text } else { Write-Host $Text -ForegroundColor $Color } }
    function Step([string]$Text) {
        $script:StepNo++
        if ($script:Wiz) { Emit 'STEP' ('{0}|{1}|{2}' -f $script:StepNo, $script:StepTotal, $Text); return }
        Write-Host ''
        Write-Host ('[{0}/{1}] {2}' -f $script:StepNo, $script:StepTotal, $Text) -ForegroundColor Cyan
    }
    function Info([string]$Text) { if ($script:Wiz) { Emit 'INFO' $Text } else { Write-Host "      $Text" } }
    function Good([string]$Text) { if ($script:Wiz) { Emit 'OK' $Text } else { Write-Host "      OK  $Text" -ForegroundColor Green } }
    function Warn([string]$Text) { if ($script:Wiz) { Emit 'WARN' $Text } else { Write-Host "      !   $Text" -ForegroundColor Yellow }; $script:Warnings.Add($Text) }
    function Status([string]$Text) { if ($script:Wiz) { Emit 'STATUS' $Text } else { Write-Host -NoNewline ("`r      {0,-92}" -f $Text) } }
    function EndStatus { if ($script:Wiz) { Emit 'STATUS' } else { Write-Host -NoNewline ("`r{0,-100}`r" -f '') } }
    function Ask([string]$Question, [string]$Default = 'y') {
        if ($Yes) { return ($Default -eq 'y') }
        $hint = if ($Default -eq 'y') { '[Y/n]' } else { '[y/N]' }
        while ($true) {
            $a = (Read-Host "      $Question $hint").Trim().ToLower()
            if ($a -eq '') { $a = $Default }
            if ($a -in 'y', 'yes') { return $true }
            if ($a -in 'n', 'no') { return $false }
        }
    }
    function Format-Size([double]$Bytes) {
        if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
        if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
        return '{0:N0} KB' -f ($Bytes / 1KB)
    }
    function Get-Rel([string]$Root, [string]$Path) { if ($Path.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) { return $Path.Substring($Root.Length + 1) } return $Path }

    # --------------------------------------------------------------------------------------------------------
    # Lenient ZIP reader (C#). Reads archives appended to executables (Epic's UDK installer: 6 stray bytes after
    # the end record and a non-zero base offset, which .NET's ZipArchive rejects), ZIP64, CRC-checks every file.
    # --------------------------------------------------------------------------------------------------------
    if (-not ('RLMMZip' -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
public class RLMMZipEntry {
    public string Name; public long Size; public long CompressedSize; public uint Crc; public int Method; public long HeaderOffset;
    public bool IsDirectory { get { return Name.EndsWith("/"); } }
}
public class RLMMZip : IDisposable {
    readonly FileStream _fs;
    public readonly List<RLMMZipEntry> Entries = new List<RLMMZipEntry>();
    public long BaseOffset;
    public RLMMZip(string path) { _fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20); ReadCentralDirectory(); }
    static uint U32(byte[] b, int o) { return BitConverter.ToUInt32(b, o); }
    static ushort U16(byte[] b, int o) { return BitConverter.ToUInt16(b, o); }
    static long U64(byte[] b, int o) { return (long)BitConverter.ToUInt64(b, o); }
    byte[] ReadAt(long pos, int count) {
        _fs.Position = pos; var b = new byte[count]; int got = 0;
        while (got < count) { int n = _fs.Read(b, got, count - got); if (n <= 0) throw new EndOfStreamException(); got += n; }
        return b;
    }
    void ReadCentralDirectory() {
        long len = _fs.Length; int tailLen = (int)Math.Min(len, 65557 + 64);
        byte[] tail = ReadAt(len - tailLen, tailLen); int eocd = -1;
        for (int i = tailLen - 22; i >= 0; i--) if (tail[i] == 0x50 && tail[i + 1] == 0x4B && tail[i + 2] == 5 && tail[i + 3] == 6) { eocd = i; break; }
        if (eocd < 0) throw new InvalidDataException("Not a zip file (no end-of-central-directory record).");
        long eocdPos = len - tailLen + eocd;
        long cdCount = U16(tail, eocd + 10), cdSize = U32(tail, eocd + 12), cdOffset = U32(tail, eocd + 16), endPos = eocdPos;
        if (eocdPos >= 20) {
            byte[] loc = ReadAt(eocdPos - 20, 20);
            if (U32(loc, 0) == 0x07064b50) {
                long z64 = eocdPos - 20 - 56; byte[] z = ReadAt(z64, 56);
                if (U32(z, 0) != 0x06064b50) throw new InvalidDataException("ZIP64 end record not found.");
                cdCount = U64(z, 32); cdSize = U64(z, 40); cdOffset = U64(z, 48); endPos = z64;
            }
        }
        long cdPos = endPos - cdSize; BaseOffset = cdPos - cdOffset;
        byte[] cd = ReadAt(cdPos, checked((int)cdSize)); int p = 0;
        for (long n = 0; n < cdCount; n++) {
            if (U32(cd, p) != 0x02014b50) throw new InvalidDataException("Bad central directory entry #" + n);
            var e = new RLMMZipEntry(); e.Method = U16(cd, p + 10); e.Crc = U32(cd, p + 16);
            long csize = U32(cd, p + 20), usize = U32(cd, p + 24), off = U32(cd, p + 42);
            int nameLen = U16(cd, p + 28), extraLen = U16(cd, p + 30), commentLen = U16(cd, p + 32);
            e.Name = System.Text.Encoding.UTF8.GetString(cd, p + 46, nameLen).Replace('\\', '/');
            int x = p + 46 + nameLen, xEnd = x + extraLen;
            while (x + 4 <= xEnd) {
                int id = U16(cd, x), sz = U16(cd, x + 2), q = x + 4;
                if (id == 1) {
                    if (usize == 0xFFFFFFFF && q + 8 <= x + 4 + sz) { usize = U64(cd, q); q += 8; }
                    if (csize == 0xFFFFFFFF && q + 8 <= x + 4 + sz) { csize = U64(cd, q); q += 8; }
                    if (off == 0xFFFFFFFF && q + 8 <= x + 4 + sz) { off = U64(cd, q); q += 8; }
                }
                x += 4 + sz;
            }
            e.Size = usize; e.CompressedSize = csize; e.HeaderOffset = BaseOffset + off; Entries.Add(e);
            p += 46 + nameLen + extraLen + commentLen;
        }
    }
    public Stream OpenEntry(RLMMZipEntry e) {
        byte[] lh = ReadAt(e.HeaderOffset, 30);
        if (U32(lh, 0) != 0x04034b50) throw new InvalidDataException("Bad local header for " + e.Name);
        long dataPos = e.HeaderOffset + 30 + U16(lh, 26) + U16(lh, 28);
        var raw = new RLMMSubStream(_fs, dataPos, e.CompressedSize);
        if (e.Method == 0) return raw;
        if (e.Method == 8) return new DeflateStream(raw, CompressionMode.Decompress);
        throw new NotSupportedException("Compression method " + e.Method + " (" + e.Name + ")");
    }
    public long Extract(RLMMZipEntry e, string dest) {
        string dir = Path.GetDirectoryName(dest); if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        string tmp = dest + ".rlmmtmp"; uint crc = 0xFFFFFFFF; long total = 0;
        using (var src = OpenEntry(e))
        using (var dst = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 20)) {
            var buf = new byte[1 << 20]; int n;
            while ((n = src.Read(buf, 0, buf.Length)) > 0) {
                for (int i = 0; i < n; i++) crc = RLMMCrc32.Table[(crc ^ buf[i]) & 0xFF] ^ (crc >> 8);
                dst.Write(buf, 0, n); total += n;
            }
        }
        crc ^= 0xFFFFFFFF;
        if (total != e.Size || crc != e.Crc) { File.Delete(tmp); throw new InvalidDataException("Corrupt archive entry (size/CRC mismatch): " + e.Name); }
        if (File.Exists(dest)) { File.SetAttributes(dest, FileAttributes.Normal); File.Delete(dest); }
        File.Move(tmp, dest);
        return total;
    }
    public string ReadText(RLMMZipEntry e) { using (var s = OpenEntry(e)) using (var r = new StreamReader(s)) return r.ReadToEnd(); }
    public void Dispose() { _fs.Dispose(); }
    // Inflates one deflate-compressed local entry fetched with an HTTP range request (EULA preview).
    public static byte[] InflateLocalEntry(byte[] chunk, out uint crc) {
        if (BitConverter.ToUInt32(chunk, 0) != 0x04034b50) throw new InvalidDataException("Not a local file header.");
        int start = 30 + BitConverter.ToUInt16(chunk, 26) + BitConverter.ToUInt16(chunk, 28);
        using (var ms = new MemoryStream(chunk, start, chunk.Length - start))
        using (var ds = new DeflateStream(ms, CompressionMode.Decompress))
        using (var outp = new MemoryStream()) {
            ds.CopyTo(outp); byte[] r = outp.ToArray(); uint c = 0xFFFFFFFF;
            foreach (byte b in r) c = RLMMCrc32.Table[(c ^ b) & 0xFF] ^ (c >> 8);
            crc = c ^ 0xFFFFFFFF; return r;
        }
    }
}
public static class RLMMCrc32 {
    public static readonly uint[] Table = Make();
    static uint[] Make() { var t = new uint[256]; for (uint i = 0; i < 256; i++) { uint c = i; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1; t[i] = c; } return t; }
}
class RLMMSubStream : Stream {
    readonly Stream _s; readonly long _start, _len; long _pos;
    public RLMMSubStream(Stream s, long start, long len) { _s = s; _start = start; _len = len; }
    public override bool CanRead { get { return true; } } public override bool CanSeek { get { return false; } } public override bool CanWrite { get { return false; } }
    public override long Length { get { return _len; } } public override long Position { get { return _pos; } set { throw new NotSupportedException(); } }
    public override int Read(byte[] b, int o, int c) { long left = _len - _pos; if (left <= 0) return 0; if (c > left) c = (int)left; _s.Position = _start + _pos; int n = _s.Read(b, o, c); _pos += n; return n; }
    public override long Seek(long o, SeekOrigin so) { throw new NotSupportedException(); }
    public override void Flush() { } public override void SetLength(long v) { throw new NotSupportedException(); } public override void Write(byte[] b, int o, int c) { throw new NotSupportedException(); }
}
'@
    }

    function Expand-Archive2([string]$ZipPath, [scriptblock]$Map, [bool]$StripTopFolder = $true) {
        # $Map gets the path inside the archive (top folder stripped for GitHub zips) and returns a destination or $null.
        $written = New-Object System.Collections.Generic.List[string]
        $zip = New-Object RLMMZip($ZipPath)
        try {
            $files = @($zip.Entries | Where-Object { -not $_.IsDirectory })
            $i = 0; $tick = [Diagnostics.Stopwatch]::StartNew()
            foreach ($e in $files) {
                $i++
                $inner = $e.Name
                if ($StripTopFolder -and $inner.IndexOf('/') -ge 0) { $inner = $inner.Substring($inner.IndexOf('/') + 1) }
                $dest = & $Map $inner
                if (-not $dest) { continue }
                [void]$zip.Extract($e, $dest)
                $written.Add($dest)
                if ($tick.ElapsedMilliseconds -gt 400) { Status ('Extracting... {0,3}%  ({1:N0} of {2:N0})' -f [int](100 * $i / $files.Count), $i, $files.Count); $tick.Restart() }
            }
            EndStatus
        } finally { $zip.Dispose() }
        return ,$written
    }

    function Remove-Obsolete([string]$Dest, $OldRel, $NewAbs, [string]$OnlyUnderAbs) {
        if (-not $OldRel) { return 0 }
        $keep = @{}; foreach ($f in $NewAbs) { $keep[(Get-Rel $Dest $f).ToLowerInvariant()] = $true }
        $n = 0
        foreach ($rel in @($OldRel)) {
            if ($keep.ContainsKey(([string]$rel).ToLowerInvariant())) { continue }
            $abs = Join-Path $Dest $rel
            if (-not $abs.StartsWith($OnlyUnderAbs + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
            if (Test-Path -LiteralPath $abs) { Remove-Item -LiteralPath $abs -Force; $n++ }
        }
        return $n
    }

    # --------------------------------------------------------------------------------------------------------
    # Downloads: curl.exe ships with Windows 10 (1803+) and 11 and gives resume, redirects and a progress bar.
    # --------------------------------------------------------------------------------------------------------
    $script:Curl = Join-Path $env:WINDIR 'System32\curl.exe'
    if (-not (Test-Path -LiteralPath $script:Curl)) { $script:Curl = $null }

    function Test-Download([string]$Path, [long]$Size, [string]$Md5) {
        if (-not (Test-Path -LiteralPath $Path)) { return $false }
        if ($Size -gt 0 -and (Get-Item -LiteralPath $Path).Length -ne $Size) { return $false }
        if ($Md5) {
            Status 'Checking file integrity...'
            $h = (Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash
            EndStatus
            return ($h -eq $Md5)
        }
        return $true
    }

    function Get-Download([string[]]$Urls, [string]$Dest, [long]$Size = 0, [string]$Md5 = '', [string]$Label = '') {
        # Tries each mirror in turn; each gets a few resumable attempts.
        if (Test-Download $Dest $Size $Md5) { Good "$Label (already downloaded)"; return }
        $sizeText = if ($Size -gt 0) { ' (' + (Format-Size $Size) + ')' } else { '' }
        Info "Downloading $Label$sizeText"
        $last = ''
        for ($m = 0; $m -lt $Urls.Count; $m++) {
            if ($m -gt 0) { Info "Trying mirror $($m + 1) of $($Urls.Count)" }
            try { Get-DownloadFrom $Urls[$m] $Dest $Size $Md5 $Label; return } catch { $last = $_.Exception.Message; Warn $last }
        }
        throw "Could not download $Label. $last"
    }

    function Get-DownloadFrom([string]$Url, [string]$Dest, [long]$Size, [string]$Md5, [string]$Label) {
        $part = "$Dest.part"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
        for ($attempt = 1; $attempt -le 4; $attempt++) {
            $code = 1
            if ($script:Curl) {
                $resume = @()
                if ((Test-Path -LiteralPath $part) -and (Get-Item -LiteralPath $part).Length -lt 1MB) { Remove-Item -LiteralPath $part -Force }   # a web page, not a partial file
                if ((Test-Path -LiteralPath $part) -and $Size -gt 0 -and (Get-Item -LiteralPath $part).Length -lt $Size) { $resume = @('-C', '-') }
                elseif (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force }
                $bar = if ($script:Wiz) { '-sS' } else { '--progress-bar' }
                if ($script:Wiz) { Emit 'DL' ('{0}|{1}|{2}|{3}' -f $(if ($Size -gt 0) { $Size } else { $script:SizeHint }), [int]($Size -le 0), $part, $Label) }
                & $script:Curl -L --fail --connect-timeout 30 --speed-limit 1024 --speed-time 90 $bar -A 'RLMM-Setup' @resume -o $part $Url
                if ($script:Wiz) { Emit 'DL' }
                $code = $LASTEXITCODE
                if ($code -in 33, 36) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }   # server refused to resume
            } else {
                try { Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $part -UserAgent 'RLMM-Setup'; $code = 0 } catch { $code = 1 }
            }
            $complete = (Test-Path -LiteralPath $part) -and ($Size -le 0 -or (Get-Item -LiteralPath $part).Length -eq $Size)
            if ($code -eq 0 -and $complete) { break }
            if ($code -eq 0 -and $Size -gt 1MB -and (Test-Path -LiteralPath $part) -and (Get-Item -LiteralPath $part).Length -lt 1MB) {
                # Google Drive answers with a web page when the file's download quota is used up: go to the next mirror
                Remove-Item -LiteralPath $part -Force
                throw "$(([uri]$Url).Host) sent a web page instead of the file (download limit reached?)."
            }
            if ($attempt -eq 4 -or $code -eq 22) { throw "Download failed from $(([uri]$Url).Host) (curl exit $code)." }   # 22: HTTP error, try the next mirror
            Info "Download interrupted (curl exit $code); retrying ($attempt/3)..."
            Start-Sleep -Seconds (5 * $attempt)
        }
        if ($Md5) {
            Status 'Checking file integrity...'
            $h = (Get-FileHash -LiteralPath $part -Algorithm MD5).Hash
            EndStatus
            if ($h -ne $Md5) { Remove-Item -LiteralPath $part -Force; throw "The download of $Label was corrupt (MD5 $h, expected $Md5)." }
        }
        Move-Item -LiteralPath $part -Destination $Dest -Force
        Good "$Label downloaded"
    }

    function Get-UrlRange([string]$Url, [long]$From, [long]$To) {
        $tmp = [IO.Path]::GetTempFileName()
        try {
            if ($script:Curl) {
                & $script:Curl -L --fail -s --connect-timeout 20 --max-time 120 -A 'RLMM-Setup' -r "$From-$To" -o $tmp $Url
                if ($LASTEXITCODE -ne 0) { return $null }
            } else {
                $req = [Net.HttpWebRequest]::Create($Url); $req.AddRange($From, $To); $req.UserAgent = 'RLMM-Setup'
                $resp = $req.GetResponse(); $fs = [IO.File]::Create($tmp); $resp.GetResponseStream().CopyTo($fs); $fs.Close(); $resp.Close()
            }
            $bytes = [IO.File]::ReadAllBytes($tmp)
            if ($bytes.Length -ne ($To - $From + 1)) { return $null }
            return ,$bytes
        } catch { return $null } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }

    function Get-GitHubHead([string]$Repo) {
        try {
            $c = Invoke-RestMethod -UseBasicParsing -Uri "https://api.github.com/repos/$Repo/commits/HEAD" -TimeoutSec 30 `
                -Headers @{ 'User-Agent' = 'RLMM-Setup'; 'Accept' = 'application/vnd.github+json' }
            return @{ Sha = [string]$c.sha; Date = ([datetime]$c.commit.committer.date).ToString('yyyy-MM-dd') }
        } catch { return $null }
    }

    function Get-BundledFile($c, [string]$What) {
        # A file kept in this repo's assets\ folder: copied from a local checkout (or the wizard) when it matches,
        # downloaded from GitHub otherwise.
        $zip = Join-Path $CacheDir $c.File
        $bundled = if ($LocalAssets) { Join-Path $LocalAssets $c.File } else { $null }
        if ($bundled -and -not (Test-Path -LiteralPath $zip) -and (Test-Path -LiteralPath $bundled) -and (Get-FileHash -LiteralPath $bundled -Algorithm MD5).Hash -eq $c.Md5) {
            Copy-Item -LiteralPath $bundled -Destination $zip
        }
        Get-Download @($c.Url) $zip $c.Size $c.Md5 $What
        return $zip
    }

    # --------------------------------------------------------------------------------------------------------
    # Machine checks
    # --------------------------------------------------------------------------------------------------------
    function Test-Admin {
        $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    function Wait-UdkClosed([string]$Dir) {
        while ($true) {
            $running = @(Get-Process -Name 'UDK', 'UDKLift' -ErrorAction SilentlyContinue | Where-Object {
                    try { $_.Path -and $_.Path.StartsWith($Dir, [StringComparison]::OrdinalIgnoreCase) } catch { $false } })
            if ($running.Count -eq 0) { return }
            Warn 'UDK is running from this folder. Save your work and close it.'
            if ($Yes) { throw 'UDK is running; close it and run the command again.' }
            Read-Host '      Press Enter once UDK is closed' | Out-Null
        }
    }
    function Get-FreeSpace([string]$Path) {
        $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
        return (New-Object IO.DriveInfo($root)).AvailableFreeSpace
    }

    # --------------------------------------------------------------------------------------------------------
    # Install state (the version-control part): <InstallDir>\RLMM-Setup\state.json
    # --------------------------------------------------------------------------------------------------------
    function Get-StateFile([string]$Dir) { Join-Path $Dir 'RLMM-Setup\state.json' }
    function ConvertTo-Hashtable($Obj) {
        if ($null -eq $Obj) { return $null }
        if ($Obj -is [System.Management.Automation.PSCustomObject]) {
            $h = @{}; foreach ($p in $Obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hashtable $p.Value }; return $h
        }
        if ($Obj -is [array]) { return ,@($Obj | ForEach-Object { ConvertTo-Hashtable $_ }) }
        return $Obj
    }
    function Read-State([string]$Dir) {
        $f = Get-StateFile $Dir
        $h = $null
        if (Test-Path -LiteralPath $f) { $h = ConvertTo-Hashtable (Get-Content -LiteralPath $f -Raw | ConvertFrom-Json) }
        if (-not $h) { $h = @{} }
        if (-not $h.ContainsKey('Components') -or -not $h.Components) { $h.Components = @{} }
        return $h
    }
    function Save-State([string]$Dir, $State) {
        $State.SetupVersion = $SetupVersion
        $f = Get-StateFile $Dir
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $f) | Out-Null
        [IO.File]::WriteAllText($f, ($State | ConvertTo-Json -Depth 6))
    }
    function Test-UdkDir([string]$Dir) { return [bool]($Dir -and (Test-Path -LiteralPath (Join-Path $Dir 'Binaries\Win64\UDK.exe'))) }

    function Find-UdkInstalls {
        $found = New-Object System.Collections.Generic.List[string]
        $candidates = New-Object System.Collections.Generic.List[string]
        try { $candidates.Add([string](Get-ItemProperty -Path 'HKCU:\Software\RLMM-Setup' -ErrorAction Stop).InstallDir) } catch { }
        foreach ($view in 'Registry32', 'Registry64') {
            try {
                $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view)
                $un = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
                foreach ($n in $un.GetSubKeyNames()) { if ($n -like 'UDK-*') { $candidates.Add([string]$un.OpenSubKey($n).GetValue('InstallLocation')) } }
            } catch { }
        }
        foreach ($drive in [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady }) {
            foreach ($top in 'UDK', 'Games\UDK') {
                $p = Join-Path $drive.RootDirectory.FullName $top
                if (Test-Path -LiteralPath $p) {
                    $candidates.Add($p)
                    Get-ChildItem -LiteralPath $p -Directory -ErrorAction SilentlyContinue | ForEach-Object { $candidates.Add($_.FullName) }
                }
            }
        }
        foreach ($c in $candidates) {
            if (-not $c) { continue }
            $d = $c.TrimEnd('\')
            if ((Test-UdkDir $d) -and -not ($found | Where-Object { $_ -ieq $d })) { $found.Add($d) }
        }
        return ,$found
    }

    # --------------------------------------------------------------------------------------------------------
    # UDK base install: what Epic's installer does for "Empty Game", without its GUI. The file list comes from
    # the installer's own Binaries/InstallData/Manifest.xml, the Unreal Tournament sample is filtered out with
    # UDKGame/ProjectTemplates/Template1/TemplateInfo.xml, the project template is copied and renamed, and every
    # UDKGame/Config/*.ini is rewritten per Template1/ConfigInfo.xml (same rules and file format as UnSetup.exe).
    # --------------------------------------------------------------------------------------------------------
    function Test-Excluded([string]$Path, $Rules) {
        $segs = $Path.Split('/')
        foreach ($r in $Rules) {
            $n = $r.Prefix.Count
            if ($segs.Length -le $n) { continue }
            $match = $true
            for ($i = 0; $i -lt $n; $i++) { if ($segs[$i] -ine $r.Prefix[$i]) { $match = $false; break } }
            if ($match -and $r.Regex.IsMatch($segs[$n])) { return $true }
        }
        return $false
    }

    function Install-UdkBase([string]$InstallerPath, [string]$Dest, [string]$Name) {
        $zip = New-Object RLMMZip($InstallerPath)
        try {
            $byName = @{}
            foreach ($e in $zip.Entries) { $byName[$e.Name.ToLowerInvariant()] = $e }
            $manifestEntry = $byName['binaries/installdata/manifest.xml']
            $templateEntry = $byName['udkgame/projecttemplates/template1/templateinfo.xml']
            if (-not $manifestEntry -or -not $templateEntry) { throw 'The UDK installer does not contain its install manifest.' }
            [xml]$manifest = $zip.ReadText($manifestEntry)
            [xml]$template = $zip.ReadText($templateEntry)

            $files = New-Object System.Collections.Generic.List[string]
            $stack = New-Object System.Collections.Stack
            $stack.Push(@($manifest.FolderProperties, ''))
            while ($stack.Count -gt 0) {
                $item = $stack.Pop(); $node = $item[0]; $prefix = $item[1]
                foreach ($f in $node.SelectNodes('Files/FileProperties')) {
                    $p = ($prefix + $f.GetAttribute('FileName')).Replace('\', '/')
                    # UnSetup writes this one itself at install time (it is the payload's Binaries/InstallData/Manifest.xml,
                    # which is copied below); it is the only manifest entry that is not in the archive.
                    if ($p -ieq 'Binaries/UnSetup.Manifests.xml') { continue }
                    $files.Add($p)
                }
                foreach ($d in $node.SelectNodes('Folders/FolderProperties')) { $stack.Push(@($d, ($prefix + $d.GetAttribute('FolderName') + '/'))) }
            }

            $rules = @(foreach ($spec in $template.SelectNodes('/ManifestOptions/MainFilesToExclude/string')) {
                    $parts = $spec.InnerText.Trim().Replace('\', '/').Split('/')
                    @{ Prefix = @($parts | Select-Object -First ($parts.Length - 1)); Regex = New-Object Text.RegularExpressions.Regex($parts[-1], 'IgnoreCase') }
                })
            $keep = New-Object System.Collections.Generic.List[string]
            foreach ($p in $files) { if (-not (Test-Excluded $p $rules)) { $keep.Add($p) } }
            $keep.Add('Binaries/InstallData/Manifest.xml')
            $total = [long]0; foreach ($p in $keep) { $e = $byName[$p.ToLowerInvariant()]; if ($e) { $total += $e.Size } }
            Info ("{0:N0} files ({1}); the Unreal Tournament sample game is left out, as Epic's ""Empty Game"" option does" -f $keep.Count, (Format-Size $total))
            $done = [long]0; $i = 0; $tick = [Diagnostics.Stopwatch]::StartNew()
            foreach ($p in $keep) {
                $e = $byName[$p.ToLowerInvariant()]
                if (-not $e) { throw "The UDK installer is missing $p" }
                [void]$zip.Extract($e, (Join-Path $Dest ($p.Replace('/', '\'))))
                $done += $e.Size; $i++
                if ($tick.ElapsedMilliseconds -gt 400) { Status ('Extracting UDK... {0,3}%  ({1:N0} of {2:N0} files)' -f [int](100 * $done / $total), $i, $keep.Count); $tick.Restart() }
            }
            EndStatus
        } finally { $zip.Dispose() }

        Copy-ProjectTemplate $Dest $Name
        Update-ProjectConfigs $Dest $Name
        Good "UDK installed (empty game project ""$Name"")"
    }

    function Copy-ProjectTemplate([string]$Dest, [string]$Name) {
        $t = Join-Path $Dest 'UDKGame\ProjectTemplates\Template1'
        foreach ($f in Get-ChildItem -LiteralPath $t -Recurse -File) {
            if ($f.DirectoryName -eq $t) { continue }                      # TemplateInfo.xml / ConfigInfo.xml stay put
            $rel = $f.FullName.Substring($t.Length + 1)
            $isGameSrc = $rel -like 'Development\Src\TemplateGame\*'
            $targetRel = $rel
            if ($isGameSrc) {
                $targetRel = 'Development\Src\' + $Name + 'Game\' + $rel.Substring('Development\Src\TemplateGame\'.Length)
                if ($f.Name.StartsWith('Template')) { $targetRel = (Split-Path -Parent $targetRel) + '\' + $Name + $f.Name.Substring('Template'.Length) }
            }
            $target = Join-Path $Dest $targetRel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            if (($f.Extension -eq '.uc' -and $isGameSrc) -or ($f.Extension -eq '.ini' -and $f.DirectoryName -like '*UDKGame\Config*')) {
                $text = [IO.File]::ReadAllText($f.FullName).Replace('TEMPLATE_FULL_NAME', $Name).Replace('TEMPLATE_SHORT_NAME', $Name)
                [IO.File]::WriteAllText($target, $text)
            } else {
                Copy-Item -LiteralPath $f.FullName -Destination $target -Force
            }
        }
    }

    # Epic's ConfigFile semantics: trimmed lines; ';' '#' '/' start comments; text before the first section is
    # dropped; repeated sections merge; sections without entries are dropped on save; UTF-8 without BOM, CRLF.
    function Read-UdkIni([string]$Path) {
        $sections = New-Object System.Collections.Specialized.OrderedDictionary -ArgumentList ([StringComparer]::Ordinal)
        $cur = $null
        foreach ($raw in [IO.File]::ReadAllLines($Path)) {
            $t = $raw.Trim()
            if ($t.Length -eq 0) { if ($null -ne $cur) { $sections[$cur].Add(@{ C = '' }) } }
            elseif (';#/'.IndexOf($t[0]) -ge 0) { if ($null -ne $cur) { $sections[$cur].Add(@{ C = $t }) } }
            elseif ($null -ne $cur -and $t.IndexOf('=') -gt 0) {
                $i = $t.IndexOf('=')
                $v = if ($i -lt $t.Length - 1) { $t.Substring($i + 1).TrimStart() } else { '' }
                $sections[$cur].Add(@{ K = $t.Substring(0, $i).TrimEnd(); V = $v })
            }
            elseif ($t.Length -gt 2 -and $t.StartsWith('[') -and $t.EndsWith(']')) {
                $cur = $t.Substring(1, $t.Length - 2).Trim()
                if (-not $sections.Contains($cur)) { $sections[$cur] = New-Object System.Collections.Generic.List[object] }
            }
        }
        return ,$sections
    }
    function Write-UdkIni([string]$Path, $Sections) {
        $sb = New-Object Text.StringBuilder
        foreach ($name in @($Sections.Keys)) {
            $list = $Sections[$name]
            $hasEntry = $false; foreach ($e in $list) { if ($e.ContainsKey('K')) { $hasEntry = $true; break } }
            if (-not $hasEntry) { continue }
            [void]$sb.Append('[' + $name + "]`r`n")
            foreach ($e in $list) { if ($e.ContainsKey('K')) { [void]$sb.Append($e.K + '=' + $e.V + "`r`n") } else { [void]$sb.Append($e.C + "`r`n") } }
        }
        [IO.File]::WriteAllText($Path, $sb.ToString())
    }

    function Update-ProjectConfigs([string]$Dest, [string]$Name) {
        [xml]$ci = [IO.File]::ReadAllText((Join-Path $Dest 'UDKGame\ProjectTemplates\Template1\ConfigInfo.xml'))
        $secEx = @($ci.SelectNodes('/ConfigOptions/ConfigSectionsToExclude/string') | ForEach-Object { $_.InnerText })
        $keyEx = @($ci.SelectNodes('/ConfigOptions/ConfigKeysToExculde/string') | ForEach-Object { $_.InnerText })   # sic (Epic's spelling)
        $valEx = @($ci.SelectNodes('/ConfigOptions/ConfigValuesToExclude/string') | ForEach-Object { $_.InnerText })
        $adds = @($ci.SelectNodes('/ConfigOptions/ConfigKeyValuesToAdd/ConfigKeyValues') | ForEach-Object {
                @{ Section = $_.SelectSingleNode('SectionName').InnerText; Key = $_.SelectSingleNode('KeyName').InnerText; Value = $_.SelectSingleNode('ValueString').InnerText } })
        foreach ($f in Get-ChildItem -LiteralPath (Join-Path $Dest 'UDKGame\Config') -Recurse -File -Filter *.ini) {
            $ini = Read-UdkIni $f.FullName
            foreach ($s in @($ini.Keys)) {
                $drop = $false; foreach ($x in $secEx) { if ($s.Contains($x)) { $drop = $true; break } }
                if ($drop) { $ini.Remove($s); continue }
                $list = $ini[$s]
                for ($i = $list.Count - 1; $i -ge 0; $i--) {
                    $e = $list[$i]
                    if (-not $e.ContainsKey('K')) { continue }
                    $kill = $false
                    foreach ($x in $keyEx) { if ($e.K.Contains($x)) { $kill = $true; break } }
                    if (-not $kill) { foreach ($x in $valEx) { if ($e.V.Contains($x)) { $kill = $true; break } } }
                    if ($kill) { $list.RemoveAt($i) }
                }
            }
            foreach ($a in $adds) {
                if (-not $ini.Contains($a.Section)) { continue }
                $list = $ini[$a.Section]
                $value = $a.Value.Replace('$(GameName)', $Name)
                if ($a.Key.StartsWith('+') -or $a.Key.StartsWith('-')) { $list.Insert(0, @{ K = $a.Key; V = $value }); continue }
                $hit = $false
                foreach ($e in $list) { if ($e.ContainsKey('K') -and $e.K -ceq $a.Key) { $e.V = $value; $hit = $true } }
                if (-not $hit) { $list.Insert(0, @{ K = $a.Key; V = $value }) }
            }
            Write-UdkIni $f.FullName $ini
        }
    }

    function Get-SetupExeCopy([string]$Dest) {
        # When run by RLMM-Setup.exe, a copy of it lives in the install: it is the Update shortcut and the uninstaller.
        if (-not $SetupExe -or -not (Test-Path -LiteralPath $SetupExe)) { return $null }
        $copy = Join-Path $Dest 'RLMM-Setup\RLMM-Setup.exe'
        if ([IO.Path]::GetFullPath($SetupExe) -ine $copy) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $copy) | Out-Null
            try { Copy-Item -LiteralPath $SetupExe -Destination $copy -Force } catch { if (-not (Test-Path -LiteralPath $copy)) { return $null } }
        }
        return $copy
    }

    function Register-UdkInstall([string]$Dest) {
        # The EULA acceptance record, where UDK.exe (64-bit) and UnSetup.exe (32-bit) look for it: both registry views
        # (the 64-bit copy is hidden from Apps & features so UDK is listed once) plus Binaries\InstallInfo.xml.
        $setupCopy = Get-SetupExeCopy $Dest
        $infoPath = Join-Path $Dest 'Binaries\InstallInfo.xml'
        $guid = $null
        if (Test-Path -LiteralPath $infoPath) { try { $guid = ([xml][IO.File]::ReadAllText($infoPath)).InstallInfo.InstallGuidString } catch { } }
        if (-not $guid) { $guid = [guid]::NewGuid().ToString() }
        $xml = "<?xml version=`"1.0`"?>`r`n<InstallInfo xmlns:xsd=`"http://www.w3.org/2001/XMLSchema`" xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`">`r`n  <InstallGuidString>$guid</InstallGuidString>`r`n</InstallInfo>"
        [IO.File]::WriteAllText($infoPath, $xml)
        foreach ($view in 'Registry32', 'Registry64') {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view)
            $k = $base.CreateSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\UDK-$guid")
            $k.SetValue('DisplayName', 'Unreal Development Kit: 2015-02 (Rocket League)', 'String')
            $k.SetValue('InstallLocation', $Dest, 'String')
            $k.SetValue('Publisher', 'Epic Games, Inc.', 'String')
            if ($setupCopy) {
                $k.SetValue('DisplayIcon', "$setupCopy,0", 'String')
                $k.SetValue('UninstallString', "`"$setupCopy`" /uninstall", 'String')
                $k.SetValue('DisplayVersion', $SetupVersion, 'String')
            } else {
                $k.SetValue('DisplayIcon', "$Dest\Binaries\InstallData\Uninstall.ico", 'String')
                $k.SetValue('UninstallString', "$Dest\Binaries\UnSetup.exe /uninstall", 'String')
            }
            $k.SetValue('NoModify', 1, 'DWord'); $k.SetValue('NoRepair', 1, 'DWord')
            $k.SetValue('EULAAccepted', 1, 'DWord')
            if ($view -eq 'Registry64') { $k.SetValue('SystemComponent', 1, 'DWord') }
            $k.Close(); $base.Close()
        }
        return $guid
    }

    function Install-Prerequisites([string]$Dest) {
        # Epic's UE3Redist.exe holds the same runtimes the official installer installs (the AMD CPU driver it also
        # bundles is only for Windows XP and is skipped).
        $redist = Join-Path $Dest 'Binaries\Redist\UE3Redist.exe'
        $work = Join-Path $env:TEMP ('RLMM-Redist-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $zip = New-Object RLMMZip($redist)
        try { foreach ($e in $zip.Entries) { if (-not $e.IsDirectory) { [void]$zip.Extract($e, (Join-Path $work $e.Name.Replace('/', '\'))) } } } finally { $zip.Dispose() }
        $jobs = @(
            @{ Name = 'Visual C++ 2010 runtime (x86)'; Exe = 'vcredist_x86_vs2010sp1.exe'; Args = '/q /norestart' },
            @{ Name = 'Visual C++ 2010 runtime (x64)'; Exe = 'vcredist_x64_vs2010sp1.exe'; Args = '/q /norestart' },
            @{ Name = 'DirectX 9 runtime (June 2010)'; Exe = 'DXRedistCutdown\DXSETUP.exe'; Args = '/silent' }
        )
        foreach ($j in $jobs) {
            $exe = Join-Path $work $j.Exe
            if (-not (Test-Path -LiteralPath $exe)) { Warn "$($j.Name): not found in UE3Redist.exe"; continue }
            Status "Installing $($j.Name)..."
            $p = Start-Process -FilePath $exe -ArgumentList $j.Args -WorkingDirectory (Split-Path -Parent $exe) -Wait -PassThru -WindowStyle Hidden
            EndStatus
            # 1638: a newer version is already installed. 3010: installed, a reboot is suggested.
            if ($p.ExitCode -in 0, 1638, 3010) { Good $j.Name } else { Warn "$($j.Name) installer returned $($p.ExitCode)" }
        }
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    # --------------------------------------------------------------------------------------------------------
    # Running UDK: commandlets without a console window, script compile, Content Browser index
    # --------------------------------------------------------------------------------------------------------
    function Invoke-UdkProcess([string]$Dest, [string]$Exe, [string[]]$Arguments, [string]$LogName, [int]$TimeoutMinutes) {
        $log = Join-Path $Dest "RLMM-Setup\logs\$LogName.log"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $log) | Out-Null
        $exePath = Join-Path $Dest $Exe
        # Through cmd.exe with CreateNoWindow: UDK.com is a console program, and Start-Process would give it a console
        # window of its own (the wizard runs this script without one). cmd writes its output to the log files.
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
        $psi.Arguments = '/d /s /c ""{0}" {1} >"{2}" 2>"{2}.err""' -f $exePath, ($Arguments -join ' '), $log
        $psi.WorkingDirectory = Split-Path -Parent $exePath
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $p = [System.Diagnostics.Process]::Start($psi)
        if (-not $p.WaitForExit($TimeoutMinutes * 60000)) {
            & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /T /F /PID $p.Id 2>&1 | Out-Null
            throw "UDK $($Arguments[0]) did not finish within $TimeoutMinutes minutes (log: $log)"
        }
        $text = ''
        if (Test-Path -LiteralPath $log) { $text = [IO.File]::ReadAllText($log) }
        return @{ Exit = $p.ExitCode; Log = $log; Text = $text }
    }

    function Invoke-FirstRun([string]$Dest) {
        # Epic's installer runs the engine once with -firstinstall to generate the per-user UDK*.ini files.
        Status 'Preparing UDK configuration (first run)...'
        $r = Invoke-UdkProcess $Dest 'Binaries\Win32\UDK.exe' @('-firstinstall', '-LanguageForCooking=INT') 'firstinstall' 10
        EndStatus
        if (Test-Path -LiteralPath (Join-Path $Dest 'UDKGame\Config\UDKEngine.ini')) { Good 'Configuration generated' }
        else { Info 'Configuration will be generated during the script compile' }
    }

    function Invoke-Make([string]$Dest) {
        # Recompiles every script package (-full: make otherwise trusts file timestamps). Adds Ok and Summary.
        $r = Invoke-UdkProcess $Dest 'Binaries\Win64\UDK.com' @('make', '-full', '-unattended', '-nopause', '-nopauseonsuccess') 'make' 30
        $m = [regex]::Match($r.Text, 'Success - (\d+) error\(s\), (\d+) warning\(s\)')
        $r.Ok = $m.Success -and $m.Groups[1].Value -eq '0'
        $r.Summary = if ($r.Ok) { 'Scripts compiled (0 errors, {0} warnings; the warnings are normal for the dummy classes)' -f $m.Groups[2].Value } else { '' }
        return $r
    }

    function Invoke-ScriptCompile([string]$Dest) {
        Status 'Compiling UnrealScript (make -full), about a minute...'
        $r = Invoke-Make $Dest
        EndStatus
        if (-not $r.Ok) {
            $errs = @([regex]::Matches($r.Text, '(?m)^.*(Error|error ).*$') | Select-Object -First 8 | ForEach-Object { $_.Value.Trim() })
            throw ("Script compile failed. First errors:`n        " + ($errs -join "`n        ") + "`n      Full log: $($r.Log)")
        }
        Good $r.Summary
    }

    function Update-AssetDatabase([string]$Dest) {
        # Epic's installer ends with this commandlet: it indexes every package for the Content Browser. Without the
        # index, the editor rebuilds it at every start ("Game asset database maintenance"), which takes minutes with
        # the ~8,500 Rocket League packages.
        Status 'Indexing assets for the Content Browser (a few minutes)...'
        $r = Invoke-UdkProcess $Dest 'Binaries\Win64\UDK.com' @('CheckpointGameAssetDatabase', '-unattended', '-nopause') 'assetdatabase' 30
        EndStatus
        if ($r.Text -match 'Success - 0 error') { Good 'Content Browser index built' }
        else { Warn "The Content Browser index could not be built (log: $($r.Log)); the editor will build it itself, which makes its first starts slow." }
    }

    function Set-SurveyFix([string]$Dest) {
        # UDK uploads a hardware survey at launch, which makes the editor slow to start; push the date far ahead.
        $f = Join-Path $Dest 'UDKGame\Config\UDKEngine.ini'
        if (-not (Test-Path -LiteralPath $f)) { return }
        $text = [IO.File]::ReadAllText($f)
        $new = [regex]::Replace($text, '(?m)^LastSurveyDate=.*$', 'LastSurveyDate=21501221')
        if ($new -ne $text) { [IO.File]::WriteAllText($f, $new) }
    }

    # --------------------------------------------------------------------------------------------------------
    # Dummy classes
    # --------------------------------------------------------------------------------------------------------
    function Set-EditPackages([string]$Dest) {
        $f = Join-Path $Dest 'UDKGame\Config\DefaultEngine.ini'
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.AddRange([string[]][IO.File]::ReadAllLines($f))
        $want = '+EditPackages=AKAudio', '+EditPackages=ProjectX', '+EditPackages=TAGame'
        $sec = -1
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq '[UnrealEd.EditorEngine]') { $sec = $i; break } }
        if ($sec -lt 0) { $lines.Add('[UnrealEd.EditorEngine]'); $sec = $lines.Count - 1 }
        $end = $lines.Count
        for ($i = $sec + 1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim().StartsWith('[')) { $end = $i; break } }
        $present = @{}; $lastEdit = $sec
        for ($i = $sec + 1; $i -lt $end; $i++) {
            $t = $lines[$i].Trim()
            if ($t -like '+EditPackages=*') { $lastEdit = $i; $present[$t.ToLowerInvariant()] = $true }
        }
        $missing = @($want | Where-Object { -not $present.ContainsKey($_.ToLowerInvariant()) })
        if ($missing.Count -eq 0) { return $false }
        $lines.InsertRange($lastEdit + 1, [string[]]$missing)
        [IO.File]::WriteAllLines($f, $lines.ToArray())
        return $true
    }

    # Where the community class (RL-Dummy-Classes) and the generated one (RL-dummy-classes2) can't both win. Found by
    # compiling the merge (2026-11-05); Install-DummyClasses re-checks with the compiler, so upstream changes are
    # handled at install time and these only save compile rounds.
    $ClassesFromGenerated = @('Core\Classes\_Types_Core.uc', 'ProjectX\Classes\_Types_X.uc', 'ProjectX\Classes\ActorComponent_X.uc',
        'TAGame\Classes\_Types_TA.uc', 'TAGame\Classes\Car_TA.uc', 'TAGame\Classes\GameEvent_Soccar_TA.uc', 'TAGame\Classes\PRI_TA.uc',
        'TAGame\Classes\ProductAsset_Body_TA.uc', 'TAGame\Classes\ProductAsset_Bot_TA.uc', 'TAGame\Classes\ProductSlot_TA.uc',
        'TAGame\Classes\Replay_TA.uc', 'TAGame\Classes\SaveData_TA.uc', 'TAGame\Classes\TutorialSave_TA.uc', 'TAGame\Classes\Vehicle_TA.uc')
    # community-only classes that Rocket League no longer has and that clash with the generated types
    $ClassesDropped = @('TAGame\Classes\PlayerTitle_TA.uc', 'TAGame\Classes\ProductReference_TA.uc', 'TAGame\Classes\ProductReferenceArray_TA.uc')

    function Get-ClassFileNames([string]$Root) {
        # 'Pkg\Classes\File.uc' -> full path, for one extracted classes repo
        $m = @{}
        if (Test-Path -LiteralPath $Root) {
            foreach ($f in Get-ChildItem -LiteralPath $Root -Recurse -Filter *.uc) { $m[(Get-Rel $Root $f.FullName)] = $f.FullName }
        }
        return $m
    }

    function Write-MergedClasses([string]$Src, $Plan) {
        # Copies each file's chosen version into Development\Src with a fresh timestamp (make compares timestamps).
        # The generated repo declares placeholder structs in __Automated_*.uc for types it doesn't generate; any that
        # the community classes define as real classes are removed, or the two clash.
        $now = Get-Date
        $realClasses = @{}
        foreach ($rel in $Plan.Choice.Keys) { if ($Plan.Choice[$rel] -eq 'base') { $realClasses[[IO.Path]::GetFileNameWithoutExtension($rel)] = $true } }
        $written = New-Object System.Collections.Generic.List[string]
        foreach ($rel in $Plan.Choice.Keys) {
            $dest = Join-Path $Src $rel
            $choice = $Plan.Choice[$rel]
            if ($choice -eq 'drop') { if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }; continue }
            $from = if ($choice -eq 'base') { $Plan.Base[$rel] } else { $Plan.Gen[$rel] }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
            if ([IO.Path]::GetFileName($rel) -like '__Automated*') {
                $txt = [IO.File]::ReadAllText($from)
                $txt = [regex]::Replace($txt, '(?m)^\s*struct\s+(\w+)\s*\{\s*\};[ \t]*\r?\n', { param($m) if ($realClasses.ContainsKey($m.Groups[1].Value)) { '' } else { $m.Value } })
                [IO.File]::WriteAllText($dest, $txt)
            } else { Copy-Item -LiteralPath $from -Destination $dest -Force }
            (Get-Item -LiteralPath $dest).LastWriteTime = $now
            $written.Add($dest)
        }
        return ,$written
    }

    function Resolve-ClassErrors([string]$Src, $Plan, [string]$MakeText) {
        # One step of the merge repair: for each compile error, give way to the generated version of the community
        # file that causes it (the one defining the missing type or parent template), or drop a community-only class
        # that no longer fits. Returns the number of decisions changed.
        if (-not $Plan.Defs) {
            $Plan.Defs = @{}
            foreach ($rel in $Plan.Choice.Keys) {
                if (-not $Plan.Gen.ContainsKey($rel) -or -not $Plan.Base.ContainsKey($rel)) { continue }
                $txt = [IO.File]::ReadAllText($Plan.Gen[$rel])
                $names = @([IO.Path]::GetFileNameWithoutExtension($rel))
                $names += [regex]::Matches($txt, '(?im)^\s*(?:enum|struct(?:\s+(?:native|transient|immutable|immutablewhencooked|atomic|atomicwhencooked|strictconfig|export|init))*)\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
                $names += [regex]::Matches($txt, '(?im)^\s*(?:var|function|event|delegate|const)\b[^;{(]*?\b(\w+)\s*(?:[;(=\[]|$)') | ForEach-Object { $_.Groups[1].Value }
                foreach ($n in $names) { if (-not $Plan.Defs.ContainsKey($n)) { $Plan.Defs[$n] = New-Object System.Collections.Generic.List[string] }; if (-not $Plan.Defs[$n].Contains($rel)) { $Plan.Defs[$n].Add($rel) } }
            }
        }
        $changed = 0
        $seen = @{}
        foreach ($m in [regex]::Matches($MakeText, '([A-Za-z]:\\[^\r\n:]+?\.uc)\((\d+)\) : Error, ([^\r\n]+)')) {
            $file = $m.Groups[1].Value; $msg = $m.Groups[3].Value
            if ($seen.ContainsKey("$file|$msg")) { continue }; $seen["$file|$msg"] = $true
            try { $file = [IO.Path]::GetFullPath($file) } catch { }
            $rel = Get-Rel $Src $file
            $names = @([regex]::Matches($msg, "'(\w+)'") | ForEach-Object { $_.Groups[1].Value })
            if ($msg -match 'parent class (\w+)') { $names += $Matches[1] }
            if ($msg -match 'cannot expand' -and (Test-Path -LiteralPath $file) -and ([IO.File]::ReadAllText($file) -match '(?i)\bclass\s+\w+\s+extends\s+(\w+)')) { $names += $Matches[1] }
            $done = $false
            foreach ($n in $names) {
                if (-not $Plan.Defs.ContainsKey($n)) { continue }
                foreach ($r in $Plan.Defs[$n]) { if ($Plan.Choice[$r] -eq 'base') { $Plan.Choice[$r] = 'gen'; $changed++; $done = $true } }
            }
            if ($done -or -not $Plan.Choice.ContainsKey($rel) -or $Plan.Choice[$rel] -ne 'base') { continue }
            $Plan.Choice[$rel] = if ($Plan.Gen.ContainsKey($rel)) { 'gen' } else { 'drop' }
            $changed++
        }
        return $changed
    }

    function Install-DummyClasses([string]$Dest, [string]$BaseZip, [string]$GenZip, $Old) {
        $src = Join-Path $Dest 'Development\Src'
        $work = Join-Path $Dest 'RLMM-Setup\classes-merge'
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
        # base = community classes, gen = generated classes; each extracted to its own folder
        foreach ($side in 'base', 'gen') {
            $into = Join-Path $work $side
            $zipPath = if ($side -eq 'base') { $BaseZip } else { $GenZip }
            [void](Expand-Archive2 $zipPath {
                param($inner)
                if ($inner -like 'Src/*') { $inner = $inner.Substring(4) }          # repos that keep classes under Src/
                if ($inner -notmatch '^[^/]+/Classes/[^/]+\.uc$') { return $null }   # only <Package>/Classes/*.uc (no README, CI...)
                return Join-Path $into $inner.Replace('/', '\')
            })
        }
        $plan = @{ Base = (Get-ClassFileNames (Join-Path $work 'base')); Gen = (Get-ClassFileNames (Join-Path $work 'gen')); Choice = @{}; Defs = $null }
        if ($plan.Base.Count -eq 0 -or $plan.Gen.Count -eq 0) { throw 'A dummy classes download contained no classes.' }
        foreach ($rel in $plan.Gen.Keys) { $plan.Choice[$rel] = 'gen' }
        foreach ($rel in $plan.Base.Keys) { $plan.Choice[$rel] = 'base' }
        foreach ($rel in $ClassesFromGenerated) { if ($plan.Gen.ContainsKey($rel) -and $plan.Base.ContainsKey($rel)) { $plan.Choice[$rel] = 'gen' } }
        foreach ($rel in $ClassesDropped) { if ($plan.Base.ContainsKey($rel) -and -not $plan.Gen.ContainsKey($rel)) { $plan.Choice[$rel] = 'drop' } }

        $written = Write-MergedClasses $src $plan
        # Files upstream removed are deleted only from the Rocket League packages; Core, Engine and GFxUI files
        # overlay stock UDK files and are left alone.
        $removed = 0
        if ($Old -and $Old.ContainsKey('Files')) {
            foreach ($pkg in 'AKAudio', 'ProjectX', 'TAGame') { $removed += Remove-Obsolete $Dest $Old.Files $written (Join-Path $src $pkg) }
        }
        if (Set-EditPackages $Dest) { Info 'Registered AKAudio, ProjectX and TAGame in DefaultEngine.ini' }

        # Compile now: the merge is only right once the compiler agrees. Repair rounds, then the generated set alone.
        $ok = $false
        for ($round = 1; $round -le 8; $round++) {
            Status ('Compiling the merged dummy classes{0}...' -f $(if ($round -gt 1) { " (round $round)" } else { '' }))
            $r = Invoke-Make $Dest
            EndStatus
            if ($r.Ok) { $ok = $true; break }
            if ((Resolve-ClassErrors $src $plan $r.Text) -eq 0) { break }
            $written = Write-MergedClasses $src $plan
        }
        $fromGen = @($plan.Choice.Keys | Where-Object { $plan.Choice[$_] -eq 'gen' -and $plan.Base.ContainsKey($_) }).Count
        $dropped = @($plan.Choice.Keys | Where-Object { $plan.Choice[$_] -eq 'drop' }).Count
        if ($ok) {
            $script:ClassesCompiled = $true
            Good $r.Summary
        } else {
            Warn 'The two dummy class sets could not be merged; installing the generated classes alone (spawn and boost pad icons may be missing in the editor).'
            foreach ($rel in @($plan.Choice.Keys)) { $plan.Choice[$rel] = if ($plan.Gen.ContainsKey($rel)) { 'gen' } else { 'drop' } }
            $written = Write-MergedClasses $src $plan
            Invoke-ScriptCompile $Dest
            $script:ClassesCompiled = $true
        }
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($c in @(
                @{ File = 'Engine\Classes\PrimitiveComponent.uc'; Pattern = 'RBCC_BallBlocker'; Text = 'RBCC_BallBlocker' },
                @{ File = 'Engine\Classes\Actor.uc'; Pattern = 'var\(\)\s+const\s+bool\s+bNoDelete'; Text = 'var() const bool bNoDelete' },
                @{ File = 'Engine\Classes\StaticMeshActor.uc'; Pattern = 'bDisableAllRigidBody'; Text = 'bDisableAllRigidBody' })) {
            $p = Join-Path $src $c.File
            if (-not (Test-Path -LiteralPath $p) -or -not (Select-String -LiteralPath $p -Pattern $c.Pattern -Quiet)) {
                Warn "Expected Rocket League change missing in $($c.File) ($($c.Text)); the dummy classes may have changed upstream."
            }
        }
        $extra = if ($removed) { ", $removed obsolete removed" } else { '' }
        $mix = if ($ok) { ('{0} community + {1} generated; {2} community classes replaced, {3} dropped' -f @($plan.Choice.Values | Where-Object { $_ -eq 'base' }).Count, @($plan.Choice.Values | Where-Object { $_ -eq 'gen' }).Count, $fromGen, $dropped) } else { 'generated only' }
        Good ("Dummy classes installed ({0} files: {1}{2})" -f $written.Count, $mix, $extra)
        return $written
    }

    # --------------------------------------------------------------------------------------------------------
    # Content packages: Not So Dummy Assets, dummy assets, Misc
    # --------------------------------------------------------------------------------------------------------
    function Get-PackageNames([string]$Dest, [string]$ExceptUnder) {
        $names = @{}
        foreach ($dir in (Join-Path $Dest 'UDKGame\Content'), (Join-Path $Dest 'Engine\Content')) {
            if (-not (Test-Path -LiteralPath $dir)) { continue }
            foreach ($f in [IO.Directory]::EnumerateFiles($dir, '*.*', 'AllDirectories')) {
                if ($ExceptUnder -and $f.StartsWith($ExceptUnder + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
                if ($f -match '\.(upk|udk|umap|u)$') { $names[[IO.Path]::GetFileNameWithoutExtension($f).ToLowerInvariant()] = $true }
            }
        }
        return $names
    }

    function Test-LfsPointerZip([string]$ZipPath) {
        # GitHub archives of LFS repos normally contain the real files; if they ever contain 130-byte pointers instead,
        # the website copy is used.
        $zip = New-Object RLMMZip($ZipPath)
        try {
            $e = $zip.Entries | Where-Object { $_.Name -match '\.upk$' } | Select-Object -First 1
            if (-not $e -or $e.Size -gt 1024) { return $false }
            return $zip.ReadText($e).StartsWith('version https://git-lfs')
        } finally { $zip.Dispose() }
    }

    function Install-ContentRepo([string]$Dest, [string]$ZipPath, $Old, [string]$Label, [string]$SubFolder, [bool]$GapFill) {
        # Packages go to UDKGame\Content\DummyAssets[\SubFolder]. With $GapFill, packages whose name already exists in
        # any content folder are skipped, so nothing is ever ambiguous.
        $root = Join-Path $Dest 'UDKGame\Content\DummyAssets'
        if ($SubFolder) { $root = Join-Path $root $SubFolder }
        $existing = if ($GapFill) { Get-PackageNames $Dest $root } else { @{} }
        $script:GapSkipped = 0
        $written = Expand-Archive2 $ZipPath {
            param($inner)
            if ($inner -match '(^|/)\.git') { return $null }
            if ($inner.IndexOf('/') -lt 0 -and $inner -notmatch '\.(upk|udk|u)$') { return $null }   # README, .gitattributes...
            if ($GapFill -and $inner -match '\.(upk|udk|u)$' -and $existing.ContainsKey([IO.Path]::GetFileNameWithoutExtension($inner).ToLowerInvariant())) {
                $script:GapSkipped++; return $null
            }
            return Join-Path $root $inner.Replace('/', '\')
        }
        $removed = 0
        if ($Old -and $Old.ContainsKey('Files')) { $removed = Remove-Obsolete $Dest $Old.Files $written $root }
        $extra = if ($removed) { ", $removed obsolete removed" } else { '' }
        if ($GapFill) { $extra += ", $($script:GapSkipped) already provided by newer assets" }
        Good ("{0} installed ({1:N0} files{2})" -f $Label, $written.Count, $extra)
        return $written
    }

    # --------------------------------------------------------------------------------------------------------
    # Not So Dummy Assets, the fast way. The repo keeps its packages in Git LFS, and GitHub serves LFS files from
    # media.githubusercontent.com: fetched 16 at a time that is several times faster than the 3.3 GB archive (which
    # GitHub builds on the fly, streams over one connection and can't resume). Updates fetch only the files whose
    # Git blob changed between the installed and the latest commit, plus any that are missing or were modified
    # locally (the sizes of installed files are recorded for that).
    # --------------------------------------------------------------------------------------------------------
    function Get-CurlVersion {
        if (-not $script:Curl) { return [version]'0.0' }
        try { if (((& $script:Curl --version) | Select-Object -First 1) -match '^curl (\d+)\.(\d+)') { return [version]"$($Matches[1]).$($Matches[2])" } } catch { }
        return [version]'0.0'
    }

    function Get-RepoTree([string]$Repo, [string]$Sha) {
        # path -> blob sha for every file of a commit (one GitHub API call).
        try {
            $t = Invoke-RestMethod -UseBasicParsing -Uri "https://api.github.com/repos/$Repo/git/trees/$Sha`?recursive=1" -TimeoutSec 60 `
                -Headers @{ 'User-Agent' = 'RLMM-Setup'; 'Accept' = 'application/vnd.github+json' }
            if ($t.truncated) { return $null }
            $m = @{}
            foreach ($e in $t.tree) { if ($e.type -eq 'blob') { $m[[string]$e.path] = [string]$e.sha } }
            return $m
        } catch { return $null }
    }

    function Test-ContentRepoPath([string]$Path) {
        # Same selection as Install-ContentRepo: package folders, plus packages at the top level; no README, .git*.
        if ($Path -match '(^|/)\.git') { return $false }
        return ($Path.IndexOf('/') -ge 0 -or $Path -match '\.(upk|udk|u)$')
    }

    function Get-BadContentFiles([string]$Dest, $Entry) {
        # Installed files that are missing or changed size since setup wrote them (e.g. a dummy package resaved by UDK).
        if (-not $Entry -or -not $Entry.ContainsKey('Sizes') -or -not $Entry.Sizes) { return 0 }
        $root = Join-Path $Dest 'UDKGame\Content\DummyAssets'
        $disabled = Join-Path $Dest 'RLMM-Setup\disabled-content'
        $bad = 0
        foreach ($p in @($Entry.Sizes.Keys)) {
            $fi = New-Object IO.FileInfo((Join-Path $root $p.Replace('/', '\')))
            if ($fi.Exists -and $fi.Length -eq [long]$Entry.Sizes[$p]) { continue }
            if (-not $fi.Exists -and (Test-Path -LiteralPath (Join-Path $disabled $fi.Name))) { continue }   # moved aside on purpose
            $bad++
        }
        return $bad
    }

    function Install-LfsRepo([string]$Dest, [string]$Repo, [string]$Sha, $Old, [string]$Label, [string]$Cache, [long]$Approx) {
        $root = Join-Path $Dest 'UDKGame\Content\DummyAssets'
        $tree = Get-RepoTree $Repo $Sha
        if (-not $tree) { throw 'GitHub did not return the file list' }
        $oldTree = $null
        if ($Old -and $Old.Version -and $Old.Version -ne $Sha) { $oldTree = Get-RepoTree $Repo ([string]$Old.Version) }
        $oldSizes = if ($Old -and $Old.ContainsKey('Sizes') -and $Old.Sizes) { $Old.Sizes } else { @{} }

        $files = @($tree.Keys | Where-Object { Test-ContentRepoPath $_ } | Sort-Object)
        $need = New-Object System.Collections.Generic.List[string]
        foreach ($p in $files) {
            $fi = New-Object IO.FileInfo((Join-Path $root $p.Replace('/', '\')))
            $ok = $fi.Exists -and $null -ne $Old
            if ($ok -and $Old.Version -ne $Sha) { $ok = $null -ne $oldTree -and $oldTree.ContainsKey($p) -and $oldTree[$p] -eq $tree[$p] }
            if ($ok -and $oldSizes.ContainsKey($p)) { $ok = $fi.Length -eq [long]$oldSizes[$p] }
            if (-not $ok) { $need.Add($p) }
        }
        if ($need.Count -lt $files.Count) { Info ('{0:N0} of {1:N0} files are new or changed' -f $need.Count, $files.Count) }

        # Download into a staging folder (kept between runs, so an interrupted download resumes where it stopped).
        $stage = Join-Path $Cache ('NotSoDummy-' + $Sha.Substring(0, 7))
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        $doneFile = Join-Path $stage '.done'
        $done = @{}
        if (Test-Path -LiteralPath $doneFile) { foreach ($l in [IO.File]::ReadAllLines($doneFile)) { $done[$l] = $true } }
        $todo = @($need | Where-Object { -not ($done.ContainsKey($_) -and (Test-Path -LiteralPath (Join-Path $stage $_.Replace('/', '\')))) })
        $est = if ($files.Count -gt 0) { [long]($Approx * $need.Count / $files.Count) } else { [long]0 }
        if ($todo.Count -gt 0) { Info ('Downloading {0:N0} files (about {1}), 16 at a time' -f $todo.Count, (Format-Size ($Approx * $todo.Count / [Math]::Max(1, $files.Count)))) }
        $base = "https://media.githubusercontent.com/media/$Repo/$Sha/"
        for ($pass = 1; $pass -le 3 -and $todo.Count -gt 0; $pass++) {
            $cfg = Join-Path $stage '.curl.cfg'
            $sb = New-Object Text.StringBuilder
            $byOut = @{}
            foreach ($p in $todo) {
                $out = (Join-Path $stage $p.Replace('/', '\')).Replace('\', '/')
                $byOut[$out.ToLowerInvariant()] = $p
                [void]$sb.Append('url = "').Append($base + (($p.Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/')).Append("`"`n")
                [void]$sb.Append('output = "').Append($out.Replace('"', '\"')).Append("`"`n")
            }
            [IO.File]::WriteAllText($cfg, $sb.ToString())
            $curlArgs = @('-L', '--fail', '--create-dirs', '--retry', '3', '--retry-delay', '3', '--connect-timeout', '30',
                '--speed-limit', '1024', '--speed-time', '60', '-A', 'RLMM-Setup', '--parallel', '--parallel-max', '16',
                '-w', '%{exitcode} %{filename_effective}\n', '-K', $cfg)
            if ($script:Wiz) { $curlArgs = @('-sS') + $curlArgs; Emit 'DL' ('{0}|1|{1}|{2}' -f $est, $stage, $Label) }
            $results = & $script:Curl @curlArgs
            if ($script:Wiz) { Emit 'DL' }
            $ok = @{}
            foreach ($line in @($results)) { if ([string]$line -match '^0 (.+)$') { $ok[$Matches[1].Trim().Replace('\', '/').ToLowerInvariant()] = $true } }
            $next = New-Object System.Collections.Generic.List[string]
            $newlyDone = New-Object System.Collections.Generic.List[string]
            foreach ($o in $byOut.Keys) {
                if ($ok.ContainsKey($o)) { $newlyDone.Add($byOut[$o]) }
                else { $next.Add($byOut[$o]); Remove-Item -LiteralPath $o.Replace('/', '\') -Force -ErrorAction SilentlyContinue }
            }
            if ($newlyDone.Count -gt 0) { [IO.File]::AppendAllLines($doneFile, [string[]]$newlyDone) }
            Remove-Item -LiteralPath $cfg -Force -ErrorAction SilentlyContinue
            $todo = @($next)
            if ($todo.Count -gt 0 -and $pass -lt 3) { Info ('{0:N0} files did not download; retrying them...' -f $todo.Count) }
        }
        if ($todo.Count -gt 0) { throw ('{0:N0} files could not be downloaded from GitHub' -f $todo.Count) }

        # Move into place, record sizes, drop what upstream removed.
        $written = New-Object System.Collections.Generic.List[string]
        $sizes = @{}
        foreach ($p in $files) {
            $abs = Join-Path $root $p.Replace('/', '\')
            $staged = Join-Path $stage $p.Replace('/', '\')
            if ([IO.File]::Exists($staged)) {
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($abs))
                if ([IO.File]::Exists($abs)) { [IO.File]::SetAttributes($abs, 'Normal'); [IO.File]::Delete($abs) }
                [IO.File]::Move($staged, $abs)
            }
            $written.Add($abs)
            $fi = New-Object IO.FileInfo($abs)
            if ($fi.Exists) { $sizes[$p] = $fi.Length }
        }
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        $removed = 0
        if ($Old -and $Old.ContainsKey('Files')) { $removed = Remove-Obsolete $Dest $Old.Files $written $root }
        $extra = if ($removed) { ", $removed obsolete removed" } else { '' }
        Good ('{0} installed ({1:N0} files, {2:N0} downloaded{3})' -f $Label, $written.Count, $need.Count, $extra)
        $script:LastSizes = $sizes
        return $written
    }

    function Resolve-PackageClashes([string]$Dest) {
        # Package names must be unique across all content folders, or UDK logs "Ambiguous package name" and picks one.
        # Precedence: stock UDK content, then Misc (newest PhysicalMaterials), then Not So Dummy Assets, then the
        # classic dummy assets; the larger copy breaks any remaining tie. Losers move to RLMM-Setup\disabled-content.
        $disabled = Join-Path $Dest 'RLMM-Setup\disabled-content'
        $rank = {
            $p = $_.FullName
            if ($_.Name -ieq 'Park_P.upk' -and $_.Length -eq 237386683) { 9 }   # the old Google Drive Park_P: outdated, maps break with it
            elseif ($p -notlike '*\DummyAssets\*') { 0 } elseif ($p -like '*\DummyAssets\Misc\*') { 1 } elseif ($p -like '*\DummyAssets\RL_DummyAssets\*') { 3 } else { 2 }
        }
        $all = @(Get-ChildItem -LiteralPath (Join-Path $Dest 'UDKGame\Content'), (Join-Path $Dest 'Engine\Content') -Recurse -File -Include *.upk, *.udk, *.umap, *.u -ErrorAction SilentlyContinue)
        foreach ($g in ($all | Group-Object { $_.BaseName.ToLowerInvariant() } | Where-Object { $_.Count -gt 1 })) {
            $ranked = @($g.Group | Sort-Object @{ Expression = $rank }, @{ Expression = 'Length'; Descending = $true })
            foreach ($loser in ($ranked | Select-Object -Skip 1)) {
                $rel = Get-Rel $Dest $loser.FullName
                $target = Join-Path $disabled $rel
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
                Move-Item -LiteralPath $loser.FullName -Destination $target -Force
                Info "Duplicate package name $($loser.Name): moved $rel to RLMM-Setup\disabled-content"
            }
        }
    }

    # --------------------------------------------------------------------------------------------------------
    # Map templates
    # --------------------------------------------------------------------------------------------------------
    function Install-MapTemplates([string]$Dest, [string]$ZipPath) {
        $tplDir = Join-Path $Dest 'Engine\Content\Maps\Templates'
        $int = Join-Path $Dest 'Engine\Localization\INT\EditorMapTemplates.int'
        $index = Join-Path $Dest 'Engine\Content\MapTemplateIndex.upk'
        New-Item -ItemType Directory -Force -Path $tplDir | Out-Null
        $written = Expand-Archive2 $ZipPath {
            param($inner)
            $to = if ($inner -match '^Template_\w+\.umap$') { Join-Path $tplDir $inner }
                  elseif ($inner -eq 'EditorMapTemplates.int') { $int } elseif ($inner -eq 'MapTemplateIndex.upk') { $index } else { $null }
            # keep the file it replaces the first time (UDK's own, or what an earlier setup installed)
            if ($to -and (Test-Path -LiteralPath $to) -and -not (Test-Path -LiteralPath "$to.bak")) { Copy-Item -LiteralPath $to -Destination "$to.bak" }
            return $to
        } $false
        $names = @($written | Where-Object { $_ -like '*.umap' } | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_).Substring(9) })
        if ($names.Count -eq 0) { throw 'The template pack contained no maps.' }
        Good ('File > New Level now offers: {0}' -f ($names -join ', '))
        return $written
    }

    # --------------------------------------------------------------------------------------------------------
    # Rocket League testing and shortcuts
    # --------------------------------------------------------------------------------------------------------
    function Find-RocketLeague {
        $hits = New-Object System.Collections.Generic.List[object]
        try {
            $steam = [string](Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
            $libs = New-Object System.Collections.Generic.List[string]; $libs.Add($steam)
            $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
            if (Test-Path -LiteralPath $vdf) { foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) { $libs.Add($m.Groups[1].Value.Replace('\\', '\')) } }
            foreach ($l in ($libs | Select-Object -Unique)) {
                $p = Join-Path $l 'steamapps\common\rocketleague'
                if (Test-Path -LiteralPath (Join-Path $p 'TAGame\CookedPCConsole')) { $hits.Add(@{ Store = 'Steam'; Path = (Resolve-Path -LiteralPath $p).Path }) }
            }
        } catch { }
        try {
            $dat = Join-Path $env:ProgramData 'Epic\UnrealEngineLauncher\LauncherInstalled.dat'
            if (Test-Path -LiteralPath $dat) {
                foreach ($a in ([IO.File]::ReadAllText($dat) | ConvertFrom-Json).InstallationList) {
                    if ($a.AppName -eq 'Sugar' -and (Test-Path -LiteralPath (Join-Path $a.InstallLocation 'TAGame\CookedPCConsole'))) { $hits.Add(@{ Store = 'Epic'; Path = [string]$a.InstallLocation }) }
                }
            }
        } catch { }
        return ,$hits
    }

    function Set-RocketLeagueTools([string]$Dest) {
        $rls = Find-RocketLeague
        $tools = Join-Path $Dest 'RLMM-Setup'
        $maps = Join-Path $Dest 'UDKGame\Content\Maps'
        New-Item -ItemType Directory -Force -Path $maps, $tools | Out-Null
        if ($rls.Count -eq 0) { Warn 'Rocket League not found (Steam or Epic). Map testing tools were skipped; run the command again after installing it.'; return }
        $rl = $rls[0]
        $cooked = Join-Path $rl.Path 'TAGame\CookedPCConsole'
        Info "Rocket League ($($rl.Store)): $($rl.Path)"
        New-Item -ItemType Directory -Force -Path (Join-Path $cooked 'mods') | Out-Null
        $utopia = Join-Path $cooked 'Labs_Utopia_P.upk'
        $backup = Join-Path $tools 'Labs_Utopia_P.original.upk'
        if (-not (Test-Path -LiteralPath $backup) -and (Test-Path -LiteralPath $utopia)) { Copy-Item -LiteralPath $utopia -Destination $backup; Info 'Backed up Labs_Utopia_P.upk (Utopia Retro, the map used for testing)' }
        # Rocket League's folder often needs admin rights to write to; the helper asks for them only when a plain copy fails.
        $helper = Join-Path $tools 'Copy-ToRocketLeague.ps1'
        [IO.File]::WriteAllText($helper, @'
param([string]$Source, [string]$Target, [string]$Done, [switch]$Elevated)
try {
    Copy-Item -LiteralPath $Source -Destination $Target -Force -ErrorAction Stop
    Write-Host $Done -ForegroundColor Green
} catch {
    if ($Elevated) { Write-Host "Copy failed: $($_.Exception.Message)" -ForegroundColor Red; Read-Host 'Press Enter'; exit 1 }
    Start-Process powershell -Verb RunAs -Wait -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
        '-Source', "`"$Source`"", '-Target', "`"$Target`"", '-Done', "`"$Done`"", '-Elevated')
}
'@)
        $run = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$helper`""
        $test = "@echo off`r`nrem Drag a saved .udk map onto this file to play it in Rocket League as Utopia Retro.`r`n" +
            "if `"%~1`"==`"`" ( echo Drag a saved .udk map file onto this script. & pause & exit /b 1 )`r`n" +
            "$run -Source `"%~1`" -Target `"$utopia`" -Done `"%~nx1 is now Utopia Retro. In Rocket League: Free Play, Utopia Retro (no restart needed).`"`r`npause`r`n"
        $restore = "@echo off`r`n$run -Source `"$backup`" -Target `"$utopia`" -Done `"Utopia Retro restored.`"`r`npause`r`n"
        [IO.File]::WriteAllText((Join-Path $maps 'Test map in Rocket League.bat'), $test)
        [IO.File]::WriteAllText((Join-Path $tools 'Restore Utopia Retro.bat'), $restore)
        Good 'To test a map, drag the saved .udk onto "Test map in Rocket League.bat" in the Maps folder'
    }

    function New-Shortcut([string]$Path, [string]$Target, [string]$Arguments = '', [string]$WorkDir = '', [string]$Icon = '') {
        $sh = New-Object -ComObject WScript.Shell
        $s = $sh.CreateShortcut($Path)
        $s.TargetPath = $Target; $s.Arguments = $Arguments
        if ($WorkDir) { $s.WorkingDirectory = $WorkDir }
        if ($Icon) { $s.IconLocation = $Icon }
        $s.Save()
    }

    function Set-Shortcuts([string]$Dest) {
        $editor = Join-Path $Dest 'Binaries\Win64\UDK.exe'
        $menu = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'RLMM'
        New-Item -ItemType Directory -Force -Path $menu | Out-Null
        $desktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
        New-Shortcut (Join-Path $desktop 'UDK - Rocket League.lnk') $editor 'editor' (Split-Path -Parent $editor) "$editor,0"
        New-Shortcut (Join-Path $menu 'UDK - Rocket League.lnk') $editor 'editor' (Split-Path -Parent $editor) "$editor,0"
        New-Shortcut (Join-Path $menu 'Maps folder.lnk') (Join-Path $Dest 'UDKGame\Content\Maps')
        # Update = the newest published setup script (falls back to the local copy when offline).
        $update = Join-Path $Dest 'RLMM-Setup\Update RLMM.cmd'
        $cmd = '@echo off' + "`r`n" +
            ('powershell -NoProfile -ExecutionPolicy Bypass -Command "try {{ $s = Invoke-RestMethod -UseBasicParsing ''{0}/install.ps1'' }} catch {{ $s = $null }}; ' -f $RepoRaw) +
            ('if ($s) {{ & ([scriptblock]::Create($s)) -InstallDir ''{0}'' }} else {{ & ''{0}\RLMM-Setup\install.ps1'' -InstallDir ''{0}'' }}"' -f $Dest) + "`r`n"
        [IO.File]::WriteAllText($update, $cmd)
        $setupCopy = Get-SetupExeCopy $Dest
        if ($setupCopy) {
            New-Shortcut (Join-Path $menu 'Update RLMM (classes, assets, templates).lnk') $setupCopy '' (Split-Path -Parent $setupCopy) "$setupCopy,0"
            New-Shortcut (Join-Path $menu 'Uninstall RLMM.lnk') $setupCopy '/uninstall' (Split-Path -Parent $setupCopy) "$setupCopy,0"
            # Apps & features: uninstall through RLMM Setup (it also removes shortcuts and restores Utopia Retro).
            foreach ($view in 'Registry32', 'Registry64') {
                $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view)
                $un = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', $true)
                if ($un) {
                    foreach ($name in $un.GetSubKeyNames()) {
                        if (-not $name.StartsWith('UDK-')) { continue }
                        $k = $un.OpenSubKey($name, $true)
                        if ($k -and [string]$k.GetValue('InstallLocation') -ieq $Dest) {
                            $k.SetValue('UninstallString', "`"$setupCopy`" /uninstall", 'String')
                            $k.SetValue('DisplayIcon', "$setupCopy,0", 'String')
                            $k.SetValue('DisplayVersion', $SetupVersion, 'String')
                        }
                        if ($k) { $k.Close() }
                    }
                    $un.Close()
                }
                $base.Close()
            }
        }
        else { New-Shortcut (Join-Path $menu 'Update RLMM (classes, assets, templates).lnk') $update '' (Split-Path -Parent $update) }
        $restore = Join-Path $Dest 'RLMM-Setup\Restore Utopia Retro.bat'
        if (Test-Path -LiteralPath $restore) { New-Shortcut (Join-Path $menu 'Restore Utopia Retro.lnk') $restore }
        Good 'Shortcuts: "UDK - Rocket League" on the desktop, and Start menu > RLMM (editor, maps, update)'
    }

    # --------------------------------------------------------------------------------------------------------
    # EULA
    # --------------------------------------------------------------------------------------------------------
    function Get-EulaRtf {
        $u = $UdkInstaller
        $chunk = $null
        foreach ($url in $u.Urls) { $chunk = Get-UrlRange $url $u.EulaOffset ($u.EulaOffset + 30 + 256 + $u.EulaCompressed); if ($chunk) { break } }
        if (-not $chunk) { return $null }
        try {
            $crc = [uint32]0
            $bytes = [RLMMZip]::InflateLocalEntry($chunk, [ref]$crc)
            if ($crc -ne $u.EulaCrc) { return $null }
            return ,$bytes
        } catch { return $null }
    }

    function Get-EulaText {
        $bytes = Get-EulaRtf
        if (-not $bytes) { return $null }
        try {
            $rtf = [Text.Encoding]::GetEncoding(1252).GetString($bytes)
            try {
                Add-Type -AssemblyName System.Windows.Forms
                $box = New-Object System.Windows.Forms.RichTextBox
                $box.Rtf = $rtf
                return $box.Text
            } catch {
                $t = [regex]::Replace($rtf, '\\par[d]?', "`r`n")
                $t = [regex]::Replace($t, "\\'([0-9a-fA-F]{2})", { param($m) [char][Convert]::ToInt32($m.Groups[1].Value, 16) })
                $t = [regex]::Replace($t, '\{\\\*[^{}]*\}|\\[a-zA-Z]+-?\d* ?|[{}]', '')
                return $t
            }
        } catch { return $null }
    }

    function Confirm-Eula {
        Say ''
        Say '  UDK (Unreal Development Kit) is made by Epic Games and licensed under the UDK End User License' White
        Say '  Agreement. You need to accept it to install UDK.' White
        if ($AcceptEula) { Good 'UDK EULA accepted (-AcceptEula)'; return }
        while ($true) {
            $a = (Read-Host '      Type V to read the EULA, Y to accept it, N to decline').Trim().ToLower()
            if ($a -eq 'v') {
                Status 'Fetching the EULA from the UDK installer...'
                $text = Get-EulaText
                EndStatus
                if ($text) {
                    $file = Join-Path $env:TEMP 'UDK-EULA.txt'
                    [IO.File]::WriteAllText($file, $text)
                    Start-Process notepad.exe -ArgumentList "`"$file`""
                    Info 'The EULA is open in Notepad.'
                } else {
                    Info 'Could not fetch it right now. It is also in Epic''s installer (Binaries\InstallData\EULA.INT.rtf).'
                }
            }
            elseif ($a -in 'y', 'yes') { Good 'UDK EULA accepted'; return }
            elseif ($a -in 'n', 'no') { throw 'The UDK EULA was declined; nothing was installed.' }
        }
    }

    # --------------------------------------------------------------------------------------------------------
    # Versions: installed vs available
    # --------------------------------------------------------------------------------------------------------
    function Get-Latest([string]$Key) {
        $c = $Components[$Key]
        if ($c.Kind -eq 'github') {
            $h = Get-GitHubHead $c.Repo
            if (-not $h) { return $null }
            return @{ Version = $h.Sha; Label = ('{0} ({1})' -f $h.Sha.Substring(0, 7), $h.Date); Url = "https://codeload.github.com/$($c.Repo)/zip/$($h.Sha)" }
        }
        if ($c.Kind -eq 'classes') {
            $a = Get-GitHubHead $c.Repo; $b = Get-GitHubHead $c.Generated
            if (-not $a -or -not $b) { return $null }
            return @{ Version = ('m{0}:{1}+{2}' -f $c.Merge, $a.Sha, $b.Sha); Label = ('{0} + {1}' -f $a.Sha.Substring(0, 7), $b.Sha.Substring(0, 7))
                      ShaA = $a.Sha; ShaB = $b.Sha
                      Url = "https://codeload.github.com/$($c.Repo)/zip/$($a.Sha)"; Url2 = "https://codeload.github.com/$($c.Generated)/zip/$($b.Sha)" }
        }
        if (-not $c.Url) { return $null }
        $label = if ($c.ContainsKey('Version')) { $c.Version } else { 'current' }
        return @{ Version = $c.Md5; Label = $label; Url = $c.Url }
    }

    # ========================================================================================================
    # Main
    # ========================================================================================================
    try { $Host.UI.RawUI.WindowTitle = 'RLMM Setup' } catch { }
    Say ''
    Say '  ================================================================' DarkCyan
    Say "    RLMM Setup $SetupVersion  -  UDK for Rocket League map making" White
    Say '  ================================================================' DarkCyan

    if ($SaveEula) {
        $rtf = Get-EulaRtf
        if (-not $rtf) { throw 'Could not fetch the UDK EULA (no connection to archive.org or Google Drive).' }
        [IO.File]::WriteAllBytes($SaveEula, $rtf)
        return
    }
    if (-not [Environment]::Is64BitOperatingSystem) { throw 'RLMM Setup needs 64-bit Windows.' }
    if ($ProjectName -notmatch '^[A-Za-z][A-Za-z0-9_]*$') { throw "Project name '$ProjectName' must start with a letter and use only letters, digits and underscores." }
    $isAdmin = Test-Admin

    # ---- install, resume or update?
    $mode = 'install'
    if ($InstallDir) { $InstallDir = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\') }
    else {
        $installs = Find-UdkInstalls
        if ($script:Wiz) { Emit 'INSTALLS' (@($installs) -join '|') }
        if ($installs.Count -gt 0) {
            if ($installs.Count -eq 1 -or $Yes) { $InstallDir = $installs[0] }
            else {
                Say ''; Say '  UDK is installed in more than one place:' White
                for ($i = 0; $i -lt $installs.Count; $i++) { Info ('{0}) {1}' -f ($i + 1), $installs[$i]) }
                $pick = (Read-Host '      Number of the one to update, or N for a new install').Trim()
                if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $installs.Count) { $InstallDir = $installs[[int]$pick - 1] }
            }
        }
    }
    $state = if ($InstallDir) { Read-State $InstallDir } else { @{ Components = @{} } }
    if ($InstallDir -and $state.ContainsKey('BaseInstalled')) { $mode = 'update' }
    elseif ($InstallDir -and $state.ContainsKey('EulaAccepted')) { $mode = 'resume' }
    elseif ($InstallDir -and (Test-UdkDir $InstallDir)) { $mode = 'update' }          # a UDK this script didn't install
    if ($script:Wiz) { Emit 'MODE' ('{0}|{1}' -f $mode, $InstallDir) }

    if ($mode -eq 'update') {
        if ($state.ContainsKey('ProjectName') -and $state.ProjectName) { $ProjectName = [string]$state.ProjectName }
        Say ''; Say "  UDK is installed at $InstallDir" White
        if (-not $state.ContainsKey('BaseInstalled')) { Info 'It was not installed by RLMM Setup, so its component versions are unknown; all of them can be refreshed.' }
    } elseif ($mode -eq 'resume') {
        if ($state.ContainsKey('ProjectName') -and $state.ProjectName) { $ProjectName = [string]$state.ProjectName }
        Say ''; Say "  Resuming the unfinished install at $InstallDir" White
    } else {
        if ($CheckOnly) { Say ''; Say '  UDK is not installed.' White; return }
        Confirm-Eula
        if (-not $InstallDir) {
            $InstallDir = $DefaultInstallDir
            if (-not $Yes) {
                $a = (Read-Host "      Install folder [$DefaultInstallDir] (Enter to accept)").Trim().Trim('"')
                if ($a) { $InstallDir = $a }
            }
            $InstallDir = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
        }
        if ($InstallDir.Contains(' ')) { throw "Choose a folder without spaces (UDK's tools break on them): $InstallDir" }
        if ((Test-Path -LiteralPath $InstallDir) -and @(Get-ChildItem -LiteralPath $InstallDir -Force).Count -gt 0) { throw "$InstallDir is not empty. Choose an empty or new folder." }
        $state = @{ Components = @{}; ProjectName = $ProjectName; EulaAccepted = (Get-Date).ToString('yyyy-MM-dd HH:mm') }
        Save-State $InstallDir $state
    }

    # ---- versions
    Say ''
    Status 'Checking the latest versions...'
    $latest = @{}
    foreach ($k in $Components.Keys) { $latest[$k] = Get-Latest $k }
    EndStatus
    $todo = New-Object System.Collections.Generic.List[string]
    Say ('  {0,-36} {1,-24} {2,-24}' -f 'Component', 'Installed', 'Latest') White
    foreach ($k in $Components.Keys) {
        $c = $Components[$k]; $l = $latest[$k]
        $have = if ($state.Components.ContainsKey($k)) { $state.Components[$k] } else { $null }
        $haveLabel = if ($have) { [string]$have.Label } else { '-' }
        $latLabel = if ($l) { $l.Label } elseif ($c.Kind -in 'github', 'classes') { '(GitHub unreachable)' } else { '(no download source)' }
        $needs = $false
        if ($l) { $needs = (-not $have) -or ([string]$have.Version -ne [string]$l.Version) }
        $flag = if (-not $needs) { 'ok' } elseif ($have) { 'update' } else { 'install' }
        # Same version, but packages missing or changed on disk (UDK resaved one, or it was deleted): repair them.
        if ($l -and -not $needs -and $have -and $have.ContainsKey('Sizes')) {
            $bad = Get-BadContentFiles $InstallDir $have
            if ($bad -gt 0) { $needs = $true; $flag = 'repair'; $latLabel = "$latLabel ($bad files)" }
        }
        $color = if ($needs) { 'Yellow' } else { 'Gray' }
        if ($script:Wiz) { Emit 'COMP' ('{0}|{1}|{2}|{3}|{4}' -f $k, $c.Title, $haveLabel, $latLabel, $flag) }
        else { Say ('  {0,-36} {1,-24} {2,-24} {3}' -f $c.Title, $haveLabel, $latLabel, $flag) $color }
        if ($needs) { $todo.Add($k) }
    }
    if ($CheckOnly) { return }
    if (-not $CacheDir) { $CacheDir = Join-Path $InstallDir 'RLMM-Setup\downloads' }
    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    New-Item -Path 'HKCU:\Software\RLMM-Setup' -Force | Out-Null
    Set-ItemProperty -Path 'HKCU:\Software\RLMM-Setup' -Name 'InstallDir' -Value $InstallDir

    if ($mode -eq 'update') {
        if ($todo.Count -eq 0) { Say ''; Good 'Everything is up to date.'; return }
        Say ''
        if (-not (Ask ('Update {0} component(s) now?' -f $todo.Count) 'y')) { Say '  Nothing changed.'; return }
    }
    Wait-UdkClosed $InstallDir
    if (-not $isAdmin) { Warn 'Not running as administrator: the EULA record, runtimes, Rocket League folder and shortcuts are skipped.' }

    # ---- disk space (download + extracted copies)
    $baseNeeded = $mode -ne 'update' -and -not $state.ContainsKey('BaseInstalled')
    $need = [long]1GB
    if ($baseNeeded) { $need += 7GB }                         # 1.9 GB installer + UDK
    if ($todo.Contains('NotSoDummy')) { $need += 7GB }       # 3.3 GB zip + 3.4 GB extracted
    if ($todo.Contains('DummyAssets')) { $need += 1GB }
    $free = Get-FreeSpace $InstallDir
    if ($free -lt $need) { throw ('Not enough disk space on {0}: {1} free, about {2} needed.' -f [IO.Path]::GetPathRoot($InstallDir), (Format-Size $free), (Format-Size $need)) }

    $script:StepTotal = $todo.Count + 2 + $(if ($baseNeeded) { 3 } else { 0 })
    $classesChanged = $false
    $script:ClassesCompiled = $false

    if ($baseNeeded) {
        Step 'Downloading UDK 2015 (from Epic, archived copy)'
        $inst = Join-Path $CacheDir $UdkInstaller.File
        Get-Download $UdkInstaller.Urls $inst $UdkInstaller.Size $UdkInstaller.Md5 'UDK installer'
        $sig = Get-AuthenticodeSignature -LiteralPath $inst
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notlike '*Epic Games*') { throw 'The UDK installer is not signed by Epic Games; refusing to use it.' }
        Good 'Signed by Epic Games, checksum verified'

        Step "Installing UDK to $InstallDir"
        Install-UdkBase $inst $InstallDir $ProjectName

        Step 'Registering UDK and installing the runtimes it needs'
        if ($isAdmin) {
            $guid = Register-UdkInstall $InstallDir
            Good "EULA acceptance recorded (install id $guid)"
            if ($SkipPrerequisites) { Info 'Runtimes skipped (-SkipPrerequisites)' } else { Install-Prerequisites $InstallDir }
            Invoke-FirstRun $InstallDir
        } else { Warn 'Skipped (needs administrator). UDK will show the EULA itself on first launch.' }
        $state.BaseInstalled = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        Save-State $InstallDir $state
        $classesChanged = $true
        if (-not $KeepDownloads) { Remove-Item -LiteralPath $inst -Force -ErrorAction SilentlyContinue }
    }

    $failed = New-Object System.Collections.Generic.List[string]
    foreach ($k in $todo) {
        $c = $Components[$k]; $l = $latest[$k]
        $old = if ($state.Components.ContainsKey($k)) { $state.Components[$k] } else { $null }
        $short = if ($l.Version.Length -gt 12) { $l.Version.Substring(0, 7) } else { $l.Version }
        Step $c.Title
        $script:SizeHint = if ($c.ContainsKey('Approx')) { [long]$c.Approx } else { [long]0 }
        $written = @()
        $toDelete = @()
        $extraState = $null
        try {
            if ($k -eq 'DummyClasses') {
                $zipA = Join-Path $CacheDir ('RL-Dummy-Classes-{0}.zip' -f $l.ShaA.Substring(0, 7)); $toDelete += $zipA
                $zipB = Join-Path $CacheDir ('RL-dummy-classes2-{0}.zip' -f $l.ShaB.Substring(0, 7)); $toDelete += $zipB
                Get-Download @($l.Url) $zipA 0 '' 'dummy classes (RocketLeagueMapmaking)'
                Get-Download @($l.Url2) $zipB 0 '' 'dummy classes (generated, ghostrider-05)'
                $written = Install-DummyClasses $InstallDir $zipA $zipB $old
                $classesChanged = $true
            }
            elseif ($k -eq 'NotSoDummy') {
                # Fast path: file by file from Git LFS, 16 at a time (needs curl 7.75+, in Windows 10 and 11 for years).
                $fast = $false
                if ((Get-CurlVersion) -ge [version]'7.75') {
                    try {
                        $written = Install-LfsRepo $InstallDir $c.Repo $l.Version $old $c.Title $CacheDir $c.Approx
                        $extraState = @{ Sizes = $script:LastSizes }
                        $fast = $true
                    } catch { Warn "The fast download did not work ($($_.Exception.Message)); downloading the archive instead." }
                }
                if (-not $fast) {
                    $zip = Join-Path $CacheDir "RL_NotSoDummyAssets-$short.zip"; $toDelete += $zip
                    $ok = $false
                    try { Get-Download @($l.Url) $zip 0 '' 'Not So Dummy Assets (GitHub)'; $ok = -not (Test-LfsPointerZip $zip) } catch { Warn $_.Exception.Message }
                    if (-not $ok) {
                        Info 'Using the rocketleaguemapmaking.com copy instead (6.8 GB, resumable).'
                        $zip = Join-Path $CacheDir 'RL_NotSoDummyAssets-main.zip'; $toDelete += $zip
                        Get-Download @($c.Fallback) $zip 0 '' 'Not So Dummy Assets (rocketleaguemapmaking.com)'
                    }
                    $written = Install-ContentRepo $InstallDir $zip $old 'Not So Dummy Assets' '' $false
                }
            }
            elseif ($k -eq 'MiscAssets') {
                $zip = Get-BundledFile $c 'Misc assets'
                $root = Join-Path $InstallDir 'UDKGame\Content\DummyAssets\Misc'
                $written = Expand-Archive2 $zip { param($inner) if ($inner -match '\.upk$') { return Join-Path $root ($inner.Split('/')[-1]) } } $false
                Good ('Misc assets installed ({0} packages: boost pad effects, physical materials incl. goal posts and crossbar)' -f $written.Count)
            }
            elseif ($k -eq 'DummyAssets') {
                $zip = Join-Path $CacheDir "RL_DummyAssets-$short.zip"; $toDelete += $zip
                Get-Download @($l.Url) $zip 0 '' 'dummy assets'
                $written = Install-ContentRepo $InstallDir $zip $old 'Dummy assets' 'RL_DummyAssets' $true
            }
            elseif ($k -eq 'MapTemplates') {
                $zip = Get-BundledFile $c 'map templates'; $toDelete += $zip
                $written = Install-MapTemplates $InstallDir $zip
                # Setup 1.0.0/1.0.1 installed Complexity 1.0.6 (bakkesplugins) as the Soccar template and the rest from
                # UDK_RL_Setup; the pack replaces both (Complexity is its Mannfield template now).
                [void]$state.Components.Remove('Complexity'); [void]$state.Components.Remove('Templates')
            }
            $entry = @{ Version = $l.Version; Label = $l.Label; At = (Get-Date).ToString('yyyy-MM-dd') }
            if (@($written).Count -gt 0) { $entry.Files = @($written | ForEach-Object { Get-Rel $InstallDir $_ }) }
            if ($extraState) { foreach ($x in $extraState.Keys) { $entry[$x] = $extraState[$x] } }
            $state.Components[$k] = $entry
            Save-State $InstallDir $state
            if (-not $KeepDownloads) { foreach ($f in $toDelete) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } }
        } catch {
            Warn "$($c.Title) was not installed: $($_.Exception.Message) It will be retried the next time you run setup."
            $failed.Add($k)
            if ($script:Wiz) { Emit 'FAILED' $c.Title }
        }
    }

    if ($todo.Contains('NotSoDummy') -or $todo.Contains('DummyAssets') -or $todo.Contains('MiscAssets')) { Resolve-PackageClashes $InstallDir }
    if ($failed.Contains('DummyClasses') -and -not (Test-Path -LiteralPath (Join-Path $InstallDir 'Development\Src\TAGame'))) {
        throw 'The dummy classes could not be installed, and UDK cannot be used for Rocket League without them.'
    }

    Step 'Compiling scripts and indexing assets'
    $contentChanged = @($todo | Where-Object { $_ -ne 'DummyClasses' }).Count -gt 0
    if (($classesChanged -and -not $script:ClassesCompiled) -or -not (Test-Path -LiteralPath (Join-Path $InstallDir 'UDKGame\Script\TAGame.u'))) {
        Invoke-ScriptCompile $InstallDir
    } elseif (-not $script:ClassesCompiled) { Good 'Scripts are up to date' }
    Set-SurveyFix $InstallDir
    if ($classesChanged -or $contentChanged -or -not (Test-Path -LiteralPath (Join-Path $InstallDir 'UDKGame\Content\GameAssetDatabase.checkpoint'))) {
        Update-AssetDatabase $InstallDir
    }

    Step 'Rocket League testing and shortcuts'
    if ($SkipRocketLeague) { Info 'Rocket League folder left alone (-SkipRocketLeague)' }
    elseif ($isAdmin) { Set-RocketLeagueTools $InstallDir }
    $self = Join-Path $InstallDir 'RLMM-Setup\install.ps1'
    [IO.File]::WriteAllText($self, (Get-RLMMScriptText), [Text.Encoding]::UTF8)
    if ($isAdmin) { Set-Shortcuts $InstallDir }
    Save-State $InstallDir $state

    Say ''
    Say '  ================================================================' DarkCyan
    if ($failed.Count -gt 0) { Say ('    Finished, but {0} component(s) could not be installed. Run setup again to retry them.' -f $failed.Count) Yellow }
    elseif ($mode -eq 'update') { Say '    Update complete.' Green }
    else { Say '    Done! UDK is ready for Rocket League map making.' Green }
    Say '  ================================================================' DarkCyan
    Info "UDK: $InstallDir"
    Info 'Start "UDK - Rocket League" from the desktop. For a stadium: File > New Level > Soccar Template, or Mannfield Template (Complexity).'
    Info 'Run this command again any time (or Start menu > RLMM > Update) to update classes and assets.'
    if ($script:Warnings.Count -gt 0) { Say ''; Say '  Warnings:' Yellow; foreach ($w in $script:Warnings) { Info $w } }
}

# ------------------------------------------------------------------------------------------------------------
# Bootstrap. Everything above is one function, so the script can always rebuild its complete text, whether it
# runs from a file or via "irm ... | iex": that text is used for the elevated relaunch and for the local copy
# behind the Start menu Update shortcut.
# ------------------------------------------------------------------------------------------------------------
function Get-RLMMScriptText {
    $parts = foreach ($name in 'Invoke-RLMMSetup', 'Get-RLMMScriptText', 'ConvertTo-RLMMArgs', 'Start-RLMMSetup') {
        "function $name {" + (Get-Item "function:$name").ScriptBlock.ToString() + "}`r`n"
    }
    return ('# RLMM Setup (https://github.com/armand0e/rlmm-setup)' + "`r`n" + ($parts -join "`r`n") + "`r`nStart-RLMMSetup (ConvertTo-RLMMArgs `$args)`r`n")
}

function ConvertTo-RLMMArgs {
    param([object[]]$Arguments)   # a param block, not an inline signature: Get-RLMMScriptText copies function bodies
    $h = @{}
    $i = 0
    while ($null -ne $Arguments -and $i -lt $Arguments.Count) {
        $a = [string]$Arguments[$i]
        if ($a -notmatch '^-([A-Za-z]+)(:(.*))?$') { throw "Unexpected argument '$a'" }
        $name = $Matches[1]
        if ($Matches[2]) { $h[$name] = $Matches[3]; $i++; continue }
        $next = if ($i + 1 -lt $Arguments.Count) { [string]$Arguments[$i + 1] } else { $null }
        if ($null -ne $next -and $next -notmatch '^-[A-Za-z]') { $h[$name] = $next; $i += 2 } else { $h[$name] = $true; $i++ }
    }
    return $h
}

function Start-RLMMSetup {
    param([hashtable]$Options)
    # Run from a copy of the repo (install.ps1 or Install-RLMM.bat): use its bundled assets before downloading them.
    if (-not $Options.ContainsKey('LocalAssets') -and $PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'assets'))) {
        $Options['LocalAssets'] = Join-Path $PSScriptRoot 'assets'
    }
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin -and -not $Options.ContainsKey('NoElevate') -and -not $Options.ContainsKey('CheckOnly')) {
        $tmp = Join-Path $env:TEMP 'RLMM-Setup.ps1'
        [IO.File]::WriteAllText($tmp, (Get-RLMMScriptText), [Text.Encoding]::UTF8)
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$tmp`"", '-Elevated')
        foreach ($k in $Options.Keys) {
            if ($Options[$k] -is [bool]) { if ($Options[$k]) { $argList += "-$k" } } else { $argList += "-$k"; $argList += "`"$($Options[$k])`"" }
        }
        Write-Host ''
        Write-Host '  RLMM Setup needs administrator rights to register UDK, install its runtimes and set up Rocket League testing.' -ForegroundColor White
        Write-Host '  Approve the Windows prompt; setup continues in a new window.' -ForegroundColor White
        try { Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -Wait -ArgumentList $argList }
        catch { Write-Host '  Administrator rights were not granted, so nothing was installed.' -ForegroundColor Yellow; return }
        Write-Host '  RLMM Setup finished in the administrator window.'
        return
    }
    $pause = $Options.ContainsKey('Elevated')
    $wizard = $env:RLMM_WIZARD -eq '1'
    if ($wizard) { try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { } }
    $code = 0
    try { Invoke-RLMMSetup @Options }
    catch {
        $code = 1
        if ($wizard) { Write-Host ('@@ERROR|' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }
        else {
            Write-Host ''
            Write-Host ('  Setup stopped: ' + $_.Exception.Message) -ForegroundColor Red
            Write-Host '  Run the same command again to resume; finished steps are skipped.' -ForegroundColor Yellow
        }
    }
    if ($wizard) { exit $code }
    if ($pause) { Write-Host ''; Read-Host '  Press Enter to close this window' | Out-Null }
}

Start-RLMMSetup (ConvertTo-RLMMArgs $args)
