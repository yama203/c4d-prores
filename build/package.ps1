# Builds the distributable zips from dist\<version>\c4d_prores:
#   dist\c4d_prores-c4d<version>-win-x64.zip  (plugin + ffmpeg + its license, installer, read-me)
#   .\package.ps1                       # 2024 and 2026
#   .\package.ps1 -Version 2026 -FfmpegDir <gyan ffmpeg folder with LICENSE / README.txt>
param(
	[string[]]$Version = @("2024", "2026"),
	[string]$FfmpegDir = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$pkg = Join-Path $root "build\package"
if (-not $FfmpegDir) {
	$exe = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($exe) { $FfmpegDir = Split-Path -Parent (Split-Path -Parent $exe.FullName) }
}

[AppContext]::SetSwitch("Switch.System.IO.Compression.ZipFile.UseBackslash", $false)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$utf8Bom = New-Object System.Text.UTF8Encoding $true

foreach ($v in $Version) {
	$built = Join-Path $root "dist\$v\c4d_prores"
	if (-not (Test-Path (Join-Path $built "c4d_prores.xdl64"))) { throw "Not built: $built (run build.ps1 -Version $v -Ffmpeg ...)" }
	if (-not (Test-Path (Join-Path $built "ffmpeg\ffmpeg.exe"))) { throw "ffmpeg.exe missing in $built\ffmpeg" }

	$stage = Join-Path $root "dist\package\$v\c4d_prores-c4d$v"
	if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
	New-Item -ItemType Directory -Force $stage | Out-Null
	Copy-Item -Recurse $built (Join-Path $stage "c4d_prores")

	# FFmpeg is GPL: ship its license and build notes next to the binary.
	foreach ($f in "LICENSE", "README.txt") {
		$p = Join-Path $FfmpegDir $f
		if (-not (Test-Path $p)) { throw "FFmpeg $f not found in '$FfmpegDir' (pass -FfmpegDir)" }
		Copy-Item $p (Join-Path $stage "c4d_prores\ffmpeg\$f")
	}

	foreach ($f in Get-ChildItem $pkg -File) {
		$text = ([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) -replace "`r?`n", "`r`n").Replace("__C4D_VERSION__", $v)
		$dst = Join-Path $stage $f.Name
		if ($f.Extension -eq ".cmd") { [IO.File]::WriteAllText($dst, $text, [Text.Encoding]::ASCII) }
		else { [IO.File]::WriteAllText($dst, $text, $utf8Bom) }   # Windows PowerShell 5.1 needs the BOM for Japanese
	}

	$zip = Join-Path $root "dist\c4d_prores-c4d$v-win-x64.zip"
	if (Test-Path $zip) { Remove-Item $zip }
	[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $true, [Text.Encoding]::UTF8)
	Write-Host ("Done: {0} ({1:0} MB)" -f $zip, ((Get-Item $zip).Length / 1MB))
}
