# Builds the ProRes saver for Cinema 4D 2024 and/or 2026.
#
#   .\build.ps1 -Version 2026
#   .\build.ps1 -Version 2024 -ProjectTool "C:\tools\c4d_project_tool_2024\kernel_app_64bit.exe"
#
# Output: dist\<version>\c4d_prores\  (copy this folder into Cinema 4D's plugins folder)

param(
	[Parameter(Mandatory = $true)][ValidateSet("2024", "2026")][string]$Version,
	[string]$C4DRoot = "",
	[string]$ProjectTool = "",
	[string]$Ffmpeg = "",
	[string]$CMake = "cmake"
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$pluginSrc = Split-Path -Parent $here
# Short work path: the Project Tool and MSBuild fail on long paths.
$work = Join-Path $env:TEMP "c4dpr\sdk$Version"
$dist = Join-Path $pluginSrc "dist\$Version\c4d_prores"

if (-not $C4DRoot) { $C4DRoot = "C:\Program Files\Maxon Cinema 4D $Version" }
$sdkZip = Join-Path $C4DRoot "sdk.zip"
if (-not (Test-Path $sdkZip)) { throw "sdk.zip not found: $sdkZip" }

# 1. Fresh SDK copy with only our module in plugins/.
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force $work | Out-Null
Expand-Archive -Path $sdkZip -DestinationPath $work
Get-ChildItem (Join-Path $work "plugins") -Directory | Where-Object { $_.Name -like "example.*" } | Remove-Item -Recurse -Force

$mod = Join-Path $work "plugins\c4d_prores"
New-Item -ItemType Directory -Force (Join-Path $mod "project") | Out-Null
Copy-Item -Recurse (Join-Path $pluginSrc "source") $mod
Copy-Item (Join-Path $here "projectdefinition_$Version.txt") (Join-Path $mod "project\projectdefinition.txt")

# 2. Build.
if ($Version -eq "2026") {
	Push-Location $work
	# Not using the SDK preset: it pins Windows SDK 10.0.20348, use whatever SDK is installed instead.
	& $CMake -S . -B _build_x64_v143 -G "Visual Studio 17 2022" -A x64 -T v143
	if ($LASTEXITCODE) { throw "cmake configure failed" }
	& $CMake --build _build_x64_v143 --config Release
	if ($LASTEXITCODE) { throw "cmake build failed" }
	Pop-Location
	$built = Get-ChildItem -Recurse (Join-Path $work "_build_x64_v143\bin\Release\plugins") -Filter "c4d_prores.xdl64" | Select-Object -First 1
}
else {
	if (-not $ProjectTool -or -not (Test-Path $ProjectTool)) { throw "Pass -ProjectTool <path to kernel_app_64bit.exe> (Maxon Project Tool for 2024)" }
	# The Project Tool needs Intel's libmmd.dll, which ships with Cinema 4D.
	$ptDir = Split-Path -Parent $ProjectTool
	if (-not (Test-Path (Join-Path $ptDir "libmmd.dll"))) {
		Copy-Item (Join-Path $C4DRoot "resource\libs\win64\libmmd.dll") $ptDir
	}
	# Solution definition that only contains our module.
	Set-Content -Encoding ascii (Join-Path $work "plugins\project\projectdefinition.txt") "Platform=Win64`r`nType=Solution`r`nSolution=plugins/c4d_prores"
	$ptLog = Join-Path (Split-Path -Parent $work) "projecttool_$Version.log"
	$p = Start-Process $ProjectTool -ArgumentList "g_updateproject=$work" -Wait -PassThru -NoNewWindow `
		-RedirectStandardOutput $ptLog -RedirectStandardError "$ptLog.err"
	if ($p.ExitCode) { throw "Project Tool failed, see $ptLog" }
	$sln = Get-ChildItem -Recurse (Join-Path $work "plugins") -Filter "*.sln" | Select-Object -First 1
	if (-not $sln) { throw "Project Tool did not create a solution" }
	$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
	$msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
	# The 2024 SDK targets v142 (VS 2019). Fall back to v143, which is binary compatible, when v142 is not installed.
	$vsRoot = & $vswhere -latest -products * -property installationPath
	$extra = @()
	if (-not (Test-Path (Join-Path $vsRoot "MSBuild\Microsoft\VC\v170\Platforms\x64\PlatformToolsets\v142"))) {
		Write-Host "v142 toolset not found, building with v143"
		$extra = @("/p:PlatformToolset=v143", "/p:WindowsTargetPlatformVersion=10.0")
	}
	# Build only our project (and the frameworks it references), not every framework in the solution.
	$proj = Join-Path $mod "project\c4d_prores.vcxproj"
	& $msbuild $proj /m /p:Configuration=Release /p:Platform=x64 /v:minimal "/p:SolutionDir=$(Split-Path -Parent $sln.FullName)\" @extra
	if ($LASTEXITCODE) { throw "msbuild failed" }
	$built = Get-ChildItem -Recurse $mod -Filter "c4d_prores.xdl64" | Select-Object -First 1
}

if (-not $built) { throw "c4d_prores.xdl64 not found after build" }

# 3. Package.
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Force $dist | Out-Null
Copy-Item $built.FullName $dist
if ($Ffmpeg -and (Test-Path $Ffmpeg)) {
	New-Item -ItemType Directory -Force (Join-Path $dist "ffmpeg") | Out-Null
	Copy-Item $Ffmpeg (Join-Path $dist "ffmpeg\ffmpeg.exe")
}
Write-Host "Done: $dist"
