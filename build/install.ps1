# Copies dist\<version>\c4d_prores into Cinema 4D's plugins folder (asks for admin rights).
#   .\install.ps1                 # 2024 and 2026
#   .\install.ps1 -Version 2026
param([string[]]$Version = @("2024", "2026"))

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

if (Get-Process "Cinema 4D*" -ErrorAction SilentlyContinue) { throw "Close Cinema 4D first (the plugin files are locked while it runs)." }

$lines = foreach ($v in $Version) {
	$src = Join-Path $root "dist\$v\c4d_prores"
	if (-not (Test-Path $src)) { throw "Not built: $src" }
	$dst = "C:\Program Files\Maxon Cinema 4D $v\plugins\c4d_prores"
	"New-Item -ItemType Directory -Force '$dst' | Out-Null; Copy-Item -Recurse -Force '$src\*' '$dst'"
}
$script = Join-Path ([IO.Path]::GetTempPath()) "c4d_prores_install.ps1"
Set-Content -Encoding utf8 $script ($lines -join "`r`n")
$p = Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script -Wait -PassThru -WindowStyle Hidden
if ($p.ExitCode) { throw "Copy failed ($($p.ExitCode))" }
foreach ($v in $Version) { Write-Host "Installed: C:\Program Files\Maxon Cinema 4D $v\plugins\c4d_prores" }
