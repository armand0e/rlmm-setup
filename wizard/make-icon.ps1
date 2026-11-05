# Draws the RLMM Setup logo (a ball on a blue/orange split tile, Rocket League's team colours) and writes RLMM.ico
# (16-256 px) and logo.png (128 px) next to this script. Run by build.ps1 when they are missing.
param([string]$OutDir = $PSScriptRoot)
Add-Type -AssemblyName System.Drawing

function New-RoundedRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-Logo([int]$s) {
    $bmp = New-Object Drawing.Bitmap($s, $s, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([Drawing.Color]::Transparent)
    $pad = [Math]::Max(0.5, $s * 0.03)
    $tile = New-RoundedRect $pad $pad ($s - 2 * $pad) ($s - 2 * $pad) ([Math]::Max(1.5, $s * 0.2))
    $g.SetClip($tile)
    $blue = New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.PointF(0, 0)), (New-Object Drawing.PointF($s, $s)),
        [Drawing.Color]::FromArgb(255, 32, 108, 230), [Drawing.Color]::FromArgb(255, 14, 52, 140))
    $g.FillRectangle($blue, 0, 0, $s, $s)
    $orange = New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.PointF(0, 0)), (New-Object Drawing.PointF($s, $s)),
        [Drawing.Color]::FromArgb(255, 255, 160, 60), [Drawing.Color]::FromArgb(255, 230, 100, 20))
    $tri = [Drawing.PointF[]]@((New-Object Drawing.PointF($s, 0)), (New-Object Drawing.PointF($s, $s)), (New-Object Drawing.PointF(0, $s)))
    $g.FillPolygon($orange, $tri)
    $g.ResetClip()
    # ball
    $r = $s * 0.30; $c = $s / 2.0
    $g.FillEllipse((New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(70, 0, 0, 0))), ($c - $r + $s * 0.02), ($c - $r + $s * 0.03), 2 * $r, 2 * $r)
    $g.FillEllipse([Drawing.Brushes]::White, ($c - $r), ($c - $r), 2 * $r, 2 * $r)
    if ($s -ge 32) {
        $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(255, 40, 48, 64), [Math]::Max(1.0, $s * 0.025))
        $pts = for ($i = 0; $i -lt 5; $i++) { $a = -90 + 72 * $i; New-Object Drawing.PointF(($c + $r * 0.42 * [Math]::Cos($a * [Math]::PI / 180)), ($c + $r * 0.42 * [Math]::Sin($a * [Math]::PI / 180))) }
        $g.FillPolygon((New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 40, 48, 64))), [Drawing.PointF[]]$pts)
        foreach ($p in $pts) {
            $dx = $p.X - $c; $dy = $p.Y - $c
            $g.DrawLine($pen, $p.X, $p.Y, ($c + $dx * 2.25), ($c + $dy * 2.25))
        }
        $g.DrawEllipse($pen, ($c - $r), ($c - $r), 2 * $r, 2 * $r)
    } else {
        $g.DrawEllipse((New-Object Drawing.Pen([Drawing.Color]::FromArgb(255, 40, 48, 64), 1)), ($c - $r), ($c - $r), 2 * $r, 2 * $r)
    }
    $g.Dispose()
    return $bmp
}

function Get-DibFrame([Drawing.Bitmap]$bmp) {
    # 32-bit BMP frame for an .ico: BITMAPINFOHEADER (double height), bottom-up BGRA pixels, AND mask.
    $s = $bmp.Width
    $ms = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter($ms)
    $maskStride = [int]([Math]::Ceiling($s / 32.0) * 4)
    $w.Write([int]40); $w.Write([int]$s); $w.Write([int]($s * 2)); $w.Write([int16]1); $w.Write([int16]32)
    $w.Write([int]0); $w.Write([int]($s * $s * 4 + $maskStride * $s)); $w.Write([int]0); $w.Write([int]0); $w.Write([int]0); $w.Write([int]0)
    for ($y = $s - 1; $y -ge 0; $y--) { for ($x = 0; $x -lt $s; $x++) { $c = $bmp.GetPixel($x, $y); $w.Write([byte]$c.B); $w.Write([byte]$c.G); $w.Write([byte]$c.R); $w.Write([byte]$c.A) } }
    $w.Write((New-Object byte[] ($maskStride * $s)))
    $w.Flush()
    return ,$ms.ToArray()
}

$sizes = 16, 20, 24, 32, 40, 48, 64, 256
$frames = foreach ($s in $sizes) {
    $bmp = New-Logo $s
    if ($s -ge 256) { $ms = New-Object IO.MemoryStream; $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); ,@($s, $ms.ToArray()) }
    else { ,@($s, (Get-DibFrame $bmp)) }
    $bmp.Dispose()
}
$out = New-Object IO.MemoryStream
$w = New-Object IO.BinaryWriter($out)
$w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$frames.Count)
$offset = 6 + 16 * $frames.Count
foreach ($f in $frames) {
    $s = $f[0]; $data = $f[1]
    $w.Write([byte]($s % 256)); $w.Write([byte]($s % 256)); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([int16]1); $w.Write([int16]32); $w.Write([int]$data.Length); $w.Write([int]$offset)
    $offset += $data.Length
}
foreach ($f in $frames) { $w.Write([byte[]]$f[1]) }
$w.Flush()
[IO.File]::WriteAllBytes((Join-Path $OutDir 'RLMM.ico'), $out.ToArray())
$logo = New-Logo 128
$logo.Save((Join-Path $OutDir 'logo.png'), [Drawing.Imaging.ImageFormat]::Png)
$logo.Dispose()
Write-Host "Wrote RLMM.ico and logo.png to $OutDir"
