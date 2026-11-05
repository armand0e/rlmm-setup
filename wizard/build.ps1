# Builds dist\RLMM-Setup.exe (the setup wizard). install.ps1 and assets\Misc.zip are embedded, so rebuild after
# changing either. Needs the .NET SDK (any recent version); the exe itself only needs .NET Framework 4.8.
#   powershell -ExecutionPolicy Bypass -File wizard\build.ps1            release build (asks for admin when run)
#   powershell -ExecutionPolicy Bypass -File wizard\build.ps1 -Test      test build that runs without admin
param([switch]$Test)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if (-not (Test-Path (Join-Path $here 'RLMM.ico')) -or -not (Test-Path (Join-Path $here 'logo.png'))) {
    python -I (Join-Path $here 'logo\make-logo.py')      # needs Python with Pillow
}
$dist = Join-Path (Split-Path -Parent $here) 'dist'
$obj = Join-Path $here 'obj'
$props = @('-c', 'Release', '-nologo', '-v', 'minimal')
if ($Test) { $props += '-p:TestBuild=true'; $out = Join-Path $here 'bin\test' } else { $out = Join-Path $here 'bin\release' }
if (Test-Path $obj) { Remove-Item -Recurse -Force $obj }     # the two builds share obj\; never mix them
dotnet build (Join-Path $here 'RLMMSetup.csproj') @props -o $out
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$name = if ($Test) { 'RLMM-Setup-Test.exe' } else { 'RLMM-Setup.exe' }
Copy-Item (Join-Path $out $name) (Join-Path $dist $name) -Force
$f = Get-Item (Join-Path $dist $name)
Write-Host ("Built {0} ({1:N0} KB)" -f $f.FullName, ($f.Length / 1KB))
