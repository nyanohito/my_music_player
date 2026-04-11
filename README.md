# Local Music Player

完全オフライン・高音質特化型のローカル音楽プレイヤー

## 🎵 機能

- MP3・FLAC・ALAC(m4a)・WAV・AAC などの主要音声フォーマットに対応
- LRC ファイルによる歌詞同期表示
- アルバムアートワークの抽出と表示（埋め込みメタデータ）
- 音量調節スライダー（0〜100%）
- 日本語ファイル名/フォルダ名対応（UTF-8 エンコードパス）
- Spotify ライクなダークテーマ UI
- バックグラウンド再生対応（iOS・Android）
- ロック画面コントロール対応
- Windows・macOS・Linux デスクトップ対応（MethodChannel競合解消済み）

## 📁 プロジェクト構成

```
local_music_player/
├── pubspec.yaml                    # パッケージ定義
├── ios/
│   └── Runner/
│       └── Info.plist              # バックグラウンド再生設定済み
└── lib/
    ├── main.dart                   # アプリ起動点
    ├── app.dart                    # MaterialApp・テーマ設定
    ├── models/                     # データ構造
    │   ├── song.dart               # 楽曲情報
    │   └── lyric_line.dart         # 歌詞データ
    ├── providers/                  # 状態管理（Riverpod）
    │   └── audio_player_provider.dart  # 再生制御
    ├── screens/                    # 画面
    │   ├── library_screen.dart     # ライブラリ画面
    │   └── now_playing_screen.dart # 再生画面
    ├── widgets/                    # UI 部品
    │   ├── lyric_view.dart         # 歌詞表示
    │   └── player_controls.dart    # 再生コントロール
    ├── utils/                      # ユーティリティ
    │   └── lrc_parser.dart         # LRC パーサー
    └── theme/
        └── app_theme.dart          # テーマ定義
```

## 🚀 セットアップ手順

### 1. Flutter 環境の準備

```bash
# Flutter SDK がインストールされていることを確認
flutter --version

# 未インストールの場合は https://flutter.dev/docs/get-started/install からインストール
```

### 2. パッケージのインストール

```bash
cd local_music_player
flutter pub get
```

### 3. iOS 設定（iOS でビルドする場合）

`ios/Runner/Info.plist` にバックグラウンド再生設定を追加済みです。

Xcode で確認する場合：
1. `ios/Runner.xcworkspace` を Xcode で開く
2. `Runner/Info.plist` を確認
3. 以下の設定が追加されていることを確認：

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

### 3. Windows 設定（Windows でビルドする場合）

日本語Windows環境でのビルドエンコーディング問題に対応済みです：

- `windows/CMakeLists.txt` に MSVC UTF-8 コンパイラオプションを追加済み
- `just_audio_windows` の日本語文字コードエラーを防止
- Visual Studio 2019+ で UTF-8 ソースコードを正しくコンパイル

### 4. アプリの実行

```bash
# iOS Simulator
flutter run -d ios

# Android エミュレータ/実機
flutter run -d android

# Windows デスクトップ
flutter run -d windows

# macOS デスクトップ
flutter run -d macos

# Linux デスクトップ
flutter run -d linux

# 利用可能なデバイス一覧
flutter devices
```

## 🎖️ 使い方

1. **起動** - アプリを起動するとライブラリ画面が表示されます
2. **曲の追加** - 「曲を追加」ボタンをタップして高音質音楽ファイル（MP3・FLAC・ALAC(m4a)・WAV・AAC）を選択
3. **歌詞の追加** - 「歌詞 (LRC)」ボタンで LRC ファイルを選択（オプション）
4. **再生** - 曲リストをタップすると再生画面に遷移し、自動的に再生開始
5. **歌詞表示** - 再生画面右上の歌詞アイコンで歌詞表示に切り替え
   - **ワイド画面**: 自動的に横並びレイアウトになり、右側に歌詞が常時表示されます
6. **音量調節** - 再生画面の音量スライダーで0〜100%の範囲で音量を調節できます

## 🎨 UI/UX の特徴

- **レスポンシブデザイン**: 画面幅に応じて最適なレイアウトに自動変更
  - 狭い画面（< 800px）: 縦並びのモバイル風レイアウト
  - 広い画面（≥ 800px）: 横並びのデスクトップ風レイアウト（左：操作パネル、右：歌詞表示）
- **Spotify風アートワーク**: グラデーション背景と複数シャドウによる洗練されたデザイン
- **Spotify ライクなダークテーマ**: 視認性の高い黒基調のデザイン
- **直感的な操作**: シンプルで分かりやすいインターフェース
- **歌詞同期**: LRC ファイルによるリアルタイム歌詞表示
- **ミニプレイヤー**: ライブラリ画面下部での簡易操作

## 📝 開発メモ

### 使用技術

- **Flutter**: UI フレームワーク
- **Riverpod**: 状態管理
- **just_audio**: 音声再生エンジン
- **file_picker**: ファイル選択
- **audio_session**: オーディオセッション管理

### アーキテクチャ

- **Provider パターン**: Riverpod による状態管理
- **関心の分離**: UI・ロジック・データを明確に分離
- **イミュータブルな状態**: 状態は不変、コピーして更新

### 今後の拡張案

- プレイリスト機能
- アルバムアート表示
- イコライザー
- シャッフル再生
- スリープタイマー

## 🐛 トラブルシューティング

### iOS でバックグラウンド再生が動かない場合

1. `Info.plist` の `UIBackgroundModes` 設定を確認
2. Xcode で「Signing & Capabilities」タブの「Background Modes」を確認
3. 実機でテスト（Simulator では制限あり）

### Android でファイルが読み込めない場合

1. `android/app/src/main/AndroidManifest.xml` に権限を追加
2. ストレージ権限を確認

### Windows でビルドが失敗する場合

1. **UTF-8 エンコーディングエラー**: 日本語Windows環境でのビルドエラー
   - `windows/CMakeLists.txt` に MSVC UTF-8 オプションが追加済み
   - エラーが続く場合は Visual Studio を再起動して再ビルド

2. **ビルドキャッシュのクリア**:
   ```bash
   flutter clean
   flutter pub get
   flutter run -d windows
   ```

### Windows Japanese filename support

1. **Custom StreamAudioSource**: Windows Media errors are now resolved
   - `LocalFileStreamAudioSource` reads file bytes directly
   - Avoids C++ native path handling that causes crashes
   - Supports Japanese filenames and folder names
   - Works with all audio formats (MP3, FLAC, M4A, etc.)

2. **Build cache clear**:
   ```bash
   flutter clean
   flutter pub get
   flutter run -d windows
   ```

### LRC ファイルが表示されない場合

1. LRC ファイルのエンコーディングが UTF-8 であることを確認
2. タイムフォーマットが `[mm:ss.xx]` であることを確認

## ライセンス

このプロジェクトは MIT ライセンスの下で公開されています。
