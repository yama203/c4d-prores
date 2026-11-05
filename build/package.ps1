# Builds the installer from dist\2024 and dist\2026 (run build.ps1 for both first):
#   dist\c4d_prores-<version>-setup.exe  (both plugin builds + one ffmpeg, installs into each C4D found)
#   .\package.ps1 -AppVersion 0.2.0
#   .\package.ps1 -AppVersion 0.2.0 -FfmpegDir <gyan ffmpeg folder with bin\ffmpeg.exe, LICENSE, README.txt>
# Needs Inno Setup 6: winget install JRSoftware.InnoSetup
param(
	[Parameter(Mandatory)][string]$AppVersion,
	[string]$FfmpegDir = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$dist = Join-Path $root "dist"
if (-not $FfmpegDir) {
	$exe = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue |
		Where-Object { $_.FullName -match "Gyan\.FFmpeg" } | Select-Object -First 1
	if ($exe) { $FfmpegDir = Split-Path -Parent (Split-Path -Parent $exe.FullName) }
}
foreach ($f in "bin\ffmpeg.exe", "LICENSE", "README.txt") {
	if (-not (Test-Path (Join-Path $FfmpegDir $f))) { throw "FFmpeg $f not found in '$FfmpegDir' (pass -FfmpegDir)" }
}
foreach ($v in "2024", "2026") {
	if (-not (Test-Path (Join-Path $dist "$v\c4d_prores\c4d_prores.xdl64"))) { throw "Not built: dist\$v (run build.ps1 -Version $v)" }
}

$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") |
	Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw "Inno Setup 6 is required: winget install JRSoftware.InnoSetup" }

& $iscc /Q "/DAppVersion=$AppVersion" "/DDist=$dist" "/DFfmpegDir=$FfmpegDir" (Join-Path $root "build\installer.iss")
if ($LASTEXITCODE) { throw "ISCC failed" }
$setup = Join-Path $dist "c4d_prores-$AppVersion-setup.exe"
Write-Host ("Done: {0} ({1:0} MB)" -f $setup, ((Get-Item $setup).Length / 1MB))
