# ProRes プラグインのインストーラー（配布用 zip に入れて使う）。
# この zip の c4d_prores フォルダを、対応するバージョンの Cinema 4D の plugins フォルダにコピーする。
param([string]$Version = "__C4D_VERSION__")

$ErrorActionPreference = "Stop"
$src = Join-Path $PSScriptRoot "c4d_prores"
$c4d = "C:\Program Files\Maxon Cinema 4D $Version"
$dst = Join-Path $c4d "plugins\c4d_prores"

try {
	if (-not (Test-Path (Join-Path $src "c4d_prores.xdl64"))) { throw "c4d_prores フォルダが見つかりません。zip を全部展開してから実行してください。" }
	if (-not (Test-Path $c4d)) { throw "Cinema 4D $Version が見つかりません: $c4d`n別の場所にある場合は、c4d_prores フォルダを手で plugins フォルダにコピーしてください。" }
	if (Get-Process "Cinema 4D*" -ErrorAction SilentlyContinue) { throw "Cinema 4D が起動しています。閉じてからもう一度実行してください。" }

	# Program Files への書き込みには管理者権限が要るので、コピーだけ昇格して行う。
	$copy = "New-Item -ItemType Directory -Force '$dst' | Out-Null; Copy-Item -Recurse -Force '$src\*' '$dst'"
	$p = Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait -PassThru `
		-ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $copy
	if ($p.ExitCode -ne 0 -or -not (Test-Path (Join-Path $dst "c4d_prores.xdl64"))) { throw "コピーに失敗しました。" }

	Write-Host "インストールしました: $dst"
	Write-Host "Cinema 4D $Version を起動し、レンダー設定 → 保存 → フォーマットで「ProRes ... (FFmpeg)」を選んでください。"
}
catch {
	Write-Host "エラー: $($_.Exception.Message)" -ForegroundColor Red
	exit 1
}
