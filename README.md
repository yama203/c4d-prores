# ProRes (FFmpeg) — Cinema 4D 用 ProRes 書き出しプラグイン（Windows）

レンダー設定 → 保存 → フォーマットに ProRes の各プロファイルを追加します。
レンダリングしたフレームを 16bit RGB(A) のまま `ffmpeg.exe` に渡し、`prores_ks` で .mov にエンコードします。

対応：Cinema 4D 2024.5 / 2026.x（ソースは共通。バージョンごとにビルドが必要）

## 使い方

1. レンダー設定 → 保存 → フォーマットで、次のどれかを選ぶ
   - ProRes 422 Proxy / 422 LT / 422 / **422 HQ** （FFmpeg）
   - **ProRes 4444** / ProRes 4444 XQ（FFmpeg） … アルファ付きにできる
2. アルファ付きにするときは、4444 か 4444 XQ を選んで、同じ「保存」の **「アルファチャンネル」をオン** にする
   （422 系はアルファに対応しないので、そもそもオンにできません）
3. 必要なら「オプション…」で次を設定（なくても書き出せます）
   - アルファを書き出すか（4444 系、既定はオン）
   - NTSC rate（×1000/1001 で 23.976、29.97、59.94）
   - ffmpeg.exe の場所

## 機能

| 項目 | 内容 |
|---|---|
| プロファイル | フォーマットの一覧で選ぶ（プロファイルごとに別の項目として登録） |
| アルファ | 4444・4444 XQ で「アルファチャンネル」がオンなら書き出す（straight） |
| フレームレート | ドキュメントの fps。「NTSC rate」をオンにすると ×1000/1001 |
| 色のタグ | Rec.709（primaries / trc / matrix）、video range |
| 奇数の解像度 | 1px パディングして偶数にする（4:2:2 の制約のため） |

## インストール

[Releases](https://github.com/yama203/c4d-prores/releases) の `c4d_prores-<バージョン>-setup.exe` を実行します（管理者権限の確認が出ます。C4D は閉じておく）。

- この PC に入っている Cinema 4D 2024 / 2026 を探して、選んだバージョンの `plugins\c4d_prores` に入れます（ffmpeg.exe も同梱）。
- アンインストールは「設定 → アプリ」の「ProRes for Cinema 4D」から。

手動で入れる場合：

1. `dist/<バージョン>/c4d_prores/` フォルダを Cinema 4D の plugins フォルダにコピーする
   （例：`C:\Program Files\Maxon Cinema 4D 2026\plugins\`。または 環境設定 → プラグイン でフォルダを追加する）
2. `ffmpeg.exe` を次のどこかに置く（上から順に探します）
   - オプション画面で指定したパス
   - `c4d_prores\ffmpeg\ffmpeg.exe`
   - `c4d_prores\ffmpeg.exe`
   - PATH の通った場所
3. Cinema 4D を再起動する

開発中は `build\install.ps1` で 2024 と 2026 の plugins フォルダにまとめてコピーできます（管理者権限の確認が出ます。C4D は閉じておく）。

エンコードに失敗すると、コンソールに FFmpeg のログの場所（`%TEMP%\c4d_prores_*.log`）が表示されます。

## ビルド

必要なもの
- Visual Studio 2022 Build Tools（C++ のワークロード）
- 2026 用：CMake 3.30 以上（`-CMake` で exe の場所を指定できます）
- 2024 用：Maxon Project Tool S24（https://developers.maxon.net/downloads/ProjectTool_S24.zip）

```powershell
cd build
.\build.ps1 -Version 2026 -Ffmpeg C:\path\to\ffmpeg.exe -CMake C:\path\to\cmake.exe
.\build.ps1 -Version 2024 -ProjectTool C:\path\to\kernel_app_64bit.exe -Ffmpeg C:\path\to\ffmpeg.exe
```

- SDK は各バージョンのインストールフォルダにある `sdk.zip` を自動で使います。作業フォルダは `%TEMP%\c4dpr`（パスが長いと Project Tool が失敗するため）。
- 2024 の SDK は v142（VS 2019）のツールセットを指定していますが、v142 が入っていなければ v143 でビルドします（バイナリ互換）。
  v143 だと SDK の nodes.framework がコンパイルできないため、このプラグインは cinema / core framework だけを使っています。
- Project Tool に必要な `libmmd.dll` は C4D 2024 からコピーします。
- テスト：`.\test_saver.ps1 -Version 2026`（c4dpy で 422 HQ・4444 アルファ・奇数解像度を書き出します）
- インストーラー：`.\package.ps1 -AppVersion 0.2.0` で `dist\c4d_prores-0.2.0-setup.exe` を作ります（[Inno Setup 6](https://jrsoftware.org/isinfo.php) が必要：`winget install JRSoftware.InnoSetup`。スクリプトは `build\installer.iss`）

## 注意

- **プラグイン ID**：今は Maxon のテスト用 ID（1000001〜1000006、プロファイルごとに1つ）です。配布する前に
  https://developers.maxon.net/forum/pid で ID を取得し、`source/prores_saver.cpp` の `g_formats` の ID を書き換えてください（6 個必要）。
- **ライセンス**：FFmpeg の ProRes エンコーダは Apple の認定を受けていません。社内や個人の制作で使う前提です。
  ffmpeg.exe を同梱して配布する場合は、そのビルドのライセンス（GPL / LGPL）に従ってください。
- **音声**：まだ書き出しません。
- **色**：OCIO（2024 以降の既定）で「ビュー変換をベイク」がオフのときは、レンダリング空間（ACEScg など）のまま渡されるので、C4D 標準の PNG などと同じく sRGB に変換してからエンコードします。ベイクがオンのときは渡された画像をそのまま使います。

## ライセンス

このプラグインのソースコードは [MIT](LICENSE) です。

- ビルドには Maxon の Cinema 4D SDK を使います（SDK 自体は Maxon のライセンス。このリポジトリには含めていません）。
- 配布物（setup.exe）に同梱している ffmpeg.exe は [gyan.dev](https://www.gyan.dev/ffmpeg/builds/) の 9.0.1 essentials ビルドで、GPL v3 です。
  プラグインとは別のプログラムとして起動して使っています。ソースは [FFmpeg bf1b838f2a](https://github.com/FFmpeg/FFmpeg/commit/bf1b838f2a)、
  ライセンス文と同梱ライブラリの版はインストール先の `c4d_prores\ffmpeg\LICENSE` と `README.txt` にあります。
- ProRes は Apple Inc. の商標です。
