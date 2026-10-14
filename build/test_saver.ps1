# Runs a quick encode test of the built plugin inside c4dpy.
#   .\test_saver.ps1 -Version 2026
param([ValidateSet("2024", "2026")][string]$Version = "2026")
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dist = Join-Path (Split-Path -Parent $here) "dist\$Version"
$t = Join-Path $env:TEMP "c4dpr\test$Version"
New-Item -ItemType Directory -Force $t | Out-Null
Copy-Item (Join-Path $here "test_saver.py") $t -Force
& "C:\Program Files\Maxon Cinema 4D $Version\c4dpy.exe" "g_additionalModulePath=$dist" (Join-Path $t "test_saver.py") $t *>&1 | Tee-Object (Join-Path $t "out.txt")
Get-ChildItem $t *.mov | Select-Object Name, Length
