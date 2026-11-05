; Inno Setup script for the ProRes plugin (Cinema 4D 2024 / 2026). Built by build\package.ps1:
;   ISCC.exe /DAppVersion=0.2.0 /DDist=<repo>\dist /DFfmpegDir=<gyan ffmpeg folder> build\installer.iss
; Installs into "<C4D>\plugins\c4d_prores" of every Cinema 4D the user picks (needs admin: Program Files).
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef Dist
  #define Dist "..\dist"
#endif
#ifndef FfmpegDir
  #error Pass /DFfmpegDir=<folder with bin\ffmpeg.exe, LICENSE, README.txt>
#endif

[Setup]
AppId={{B3E1C2A4-7D59-4E0F-A6B8-2F4C9D1E7A35}
AppName=ProRes for Cinema 4D
AppVersion={#AppVersion}
AppVerName=ProRes for Cinema 4D {#AppVersion}
AppPublisher=yama203
AppPublisherURL=https://github.com/yama203/c4d-prores
VersionInfoVersion={#AppVersion}
; Only the uninstaller lives here; the plugin goes into each Cinema 4D's plugins folder.
DefaultDirName={commonpf64}\ProRes for Cinema 4D
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#Dist}
OutputBaseFilename=c4d_prores-{#AppVersion}-setup
UninstallDisplayName=ProRes for Cinema 4D
WizardStyle=modern dynamic
Compression=lzma2/max
SolidCompression=yes
; Cinema 4D is checked in InitializeSetup instead: closing it automatically could lose unsaved work.
CloseApplications=no

[Languages]
Name: "ja"; MessagesFile: "compiler:Languages\Japanese.isl"

[Types]
Name: "custom"; Description: "custom"; Flags: iscustom

[Components]
Name: "c4d2024"; Description: "Cinema 4D 2024"; Types: custom; Check: HasC4D('2024')
Name: "c4d2026"; Description: "Cinema 4D 2026"; Types: custom; Check: HasC4D('2026')

[Files]
; The same ffmpeg source files are referenced for both versions, so the installer stores them once.
Source: "{#Dist}\2024\c4d_prores\c4d_prores.xdl64"; DestDir: "{code:PluginDir|2024}"; Components: c4d2024; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{code:PluginDir|2024}"; Components: c4d2024; Flags: ignoreversion
Source: "{#FfmpegDir}\bin\ffmpeg.exe"; DestDir: "{code:PluginDir|2024}\ffmpeg"; Components: c4d2024; Flags: ignoreversion
Source: "{#FfmpegDir}\LICENSE"; DestDir: "{code:PluginDir|2024}\ffmpeg"; Components: c4d2024; Flags: ignoreversion
Source: "{#FfmpegDir}\README.txt"; DestDir: "{code:PluginDir|2024}\ffmpeg"; Components: c4d2024; Flags: ignoreversion
Source: "{#Dist}\2026\c4d_prores\c4d_prores.xdl64"; DestDir: "{code:PluginDir|2026}"; Components: c4d2026; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{code:PluginDir|2026}"; Components: c4d2026; Flags: ignoreversion
Source: "{#FfmpegDir}\bin\ffmpeg.exe"; DestDir: "{code:PluginDir|2026}\ffmpeg"; Components: c4d2026; Flags: ignoreversion
Source: "{#FfmpegDir}\LICENSE"; DestDir: "{code:PluginDir|2026}\ffmpeg"; Components: c4d2026; Flags: ignoreversion
Source: "{#FfmpegDir}\README.txt"; DestDir: "{code:PluginDir|2026}\ffmpeg"; Components: c4d2026; Flags: ignoreversion

[UninstallDelete]
; The folders may predate this installer (zip install), so remove them explicitly once empty.
Type: dirifempty; Name: "{code:PluginDir|2024}\ffmpeg"; Components: c4d2024
Type: dirifempty; Name: "{code:PluginDir|2024}"; Components: c4d2024
Type: dirifempty; Name: "{code:PluginDir|2026}\ffmpeg"; Components: c4d2026
Type: dirifempty; Name: "{code:PluginDir|2026}"; Components: c4d2026

[Messages]
ja.SelectComponentsDesc=プラグインを入れる Cinema 4D を選んでください。
ja.SelectComponentsLabel2=この PC で見つかった Cinema 4D です。入れたいバージョンにチェックを付けて「次へ」を押してください。
ja.FinishedLabel=インストールしました。%n%nCinema 4D を起動し、レンダー設定 → 保存 → フォーマットで「ProRes 422 HQ (FFmpeg)」などを選んでください。アルファ付きにするときは「ProRes 4444 (FFmpeg)」を選び、「アルファチャンネル」をオンにします。

[Code]
const
  UninstallKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';

{ Install folder of "Maxon Cinema 4D <version>", from its uninstall entry or the default location. }
function FindC4D(Version: String): String;
var
  Keys: TArrayOfString;
  I: Integer;
  Name, Loc: String;
begin
  Result := '';
  if RegGetSubkeyNames(HKLM64, UninstallKey, Keys) then
    for I := 0 to GetArrayLength(Keys) - 1 do
      if RegQueryStringValue(HKLM64, UninstallKey + '\' + Keys[I], 'DisplayName', Name) and
         (Name = 'Maxon Cinema 4D ' + Version) and
         RegQueryStringValue(HKLM64, UninstallKey + '\' + Keys[I], 'InstallLocation', Loc) and
         DirExists(Loc) then
      begin
        Result := RemoveBackslashUnlessRoot(Loc);
        Exit;
      end;
  Loc := ExpandConstant('{commonpf64}\Maxon Cinema 4D ') + Version;
  if DirExists(Loc) then
    Result := Loc;
end;

function HasC4D(Version: String): Boolean;
begin
  Result := FindC4D(Version) <> '';
end;

function PluginDir(Version: String): String;
begin
  Result := FindC4D(Version) + '\plugins\c4d_prores';
end;

function C4DRunning(): Boolean;
var
  Wmi, Procs: Variant;
begin
  Result := False;
  try
    Wmi := CreateOleObject('WbemScripting.SWbemLocator');
    Procs := Wmi.ConnectServer('.', 'root\CIMV2').ExecQuery('SELECT ProcessId FROM Win32_Process WHERE Name LIKE ''Cinema 4D%''');
    Result := Procs.Count > 0;
  except
  end;
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  if not (HasC4D('2024') or HasC4D('2026')) then
  begin
    MsgBox('Cinema 4D 2024 / 2026 が見つかりませんでした。' + #13#10#13#10 +
      'このプラグインは Cinema 4D 2024 と 2026（Windows）用です。', mbError, MB_OK);
    Result := False;
    Exit;
  end;
  while C4DRunning() do
    if MsgBox('Cinema 4D が起動しています。' + #13#10 +
      '作業を保存して Cinema 4D を閉じてから「再試行」を押してください。', mbInformation, MB_RETRYCANCEL) = IDCANCEL then
    begin
      Result := False;
      Exit;
    end;
end;

function InitializeUninstall(): Boolean;
begin
  Result := True;
  while C4DRunning() do
    if MsgBox('Cinema 4D が起動しています。閉じてから「再試行」を押してください。', mbInformation, MB_RETRYCANCEL) = IDCANCEL then
    begin
      Result := False;
      Exit;
    end;
end;
