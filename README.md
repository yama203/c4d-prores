# ProRes (FFmpeg) — Cinema 4D 用 ProRes 書き出しプラグイン（Windows）

レンダー設定 → 保存 → フォーマットに **「ProRes (FFmpeg)」** を追加します。
レンダリングしたフレームを 16bit RGB(A) のまま `ffmpeg.exe` に渡し、`prores_ks` で .mov にエンコードします。

対応：Cinema 4D 2024.5 / 2026.x（ソースは共通。バージョンごとにビルドが必要）

## 機能

| 項目 | 内容 |
|---|---|
| プロファイル | 422 Proxy / 422 LT / 422 / 422 HQ（既定）/ 4444 / 4444 XQ |
| アルファ | 4444・4444 XQ でレンダー設定の「アルファチャンネル」がオンなら書き出す |
| フレームレート | ドキュメントの fps。「NTSC rate」をオンにすると ×1000/1001（23.976、29.97 など） |
| 色のタグ | Rec.709（primaries / trc / matrix）、video range |
| 奇数の解像度 | 1px パディングして偶数にする（4:2:2 の制約のため） |

フォーマットの横にある「オプション…」から設定します。

## インストール

1. `dist/<バージョン>/c4d_prores/` フォルダを Cinema 4D の plugins フォルダにコピーする
   （例：`C:\Program Files\Maxon Cinema 4D 2026\plugins\`。または 環境設定 → プラグイン でフォルダを追加する）
2. `ffmpeg.exe` を次のどこかに置く（上から順に探します）
   - オプション画面で指定したパス
   - `c4d_prores\ffmpeg\ffmpeg.exe`
   - `c4d_prores\ffmpeg.exe`
   - PATH の通った場所
3. Cinema 4D を再起動する

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

## 注意

- **プラグイン ID**：今は Maxon のテスト用 ID（1000001）です。配布する前に
  https://developers.maxon.net/forum/pid で ID を取得し、`source/prores_saver.cpp` の `ID_PRORES_SAVER` を書き換えてください。
- **ライセンス**：FFmpeg の ProRes エンコーダは Apple の認定を受けていません。社内や個人の制作で使う前提です。
  ffmpeg.exe を同梱して配布する場合は、そのビルドのライセンス（GPL / LGPL）に従ってください。
- **音声**：まだ書き出しません。
- **色**：Cinema 4D が書き出し用に変換した後の 8/16bit の画像（表示用の色空間）を受け取って、そのままエンコードします。
