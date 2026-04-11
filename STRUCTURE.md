# 📁 プロジェクト ディレクトリ構成

```
local_music_player/
│
├── pubspec.yaml                    # パッケージ定義
│
├── ios/
│   └── Runner/
│       └── Info.plist              # ★ バックグラウンド再生の設定が必要（後述）
│
└── lib/
    │
    ├── main.dart                   # アプリ起動点・JustAudioBackground初期化
    ├── app.dart                    # MaterialApp・テーマ・ルート設定
    │
    ├── models/                     # データ構造の定義（ロジックなし）
    │   ├── song.dart               # 楽曲情報（タイトル・パス・歌詞など）
    │   └── lyric_line.dart         # 1行分の歌詞データ（時刻＋テキスト）
    │
    ├── providers/                  # ★ アプリの「頭脳」（Riverpod状態管理）
    │   ├── audio_player_provider.dart  # 再生・一時停止・シークなどの制御
    │   └── lyric_provider.dart         # LRC解析・現在行のハイライト管理
    │
    ├── screens/                    # 画面単位のWidget
    │   ├── library_screen.dart     # ライブラリ画面（ファイル選択・曲一覧）
    │   └── now_playing_screen.dart # 再生画面（アートワーク・歌詞・操作UI）
    │
    ├── widgets/                    # 再利用可能な部品Widget
    │   ├── lyric_view.dart         # 歌詞の自動スクロール表示
    │   └── player_controls.dart    # 再生ボタン・シークバーなど
    │
    ├── utils/                      # ユーティリティ（純粋な関数）
    │   └── lrc_parser.dart         # LRCファイルのパーサー
    │
    └── theme/
        └── app_theme.dart          # Spotifyライクなダークテーマ定義
```

## iOS Info.plist に追加が必要な設定

`ios/Runner/Info.plist` の `<dict>` 内に以下を追加してください:

```xml
<!-- バックグラウンド再生を許可 -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>

<!-- ファイルアプリからの読み込みを許可 -->
<key>UIFileSharingEnabled</key>
<true/>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>

<!-- マイクなし（読み取り専用）でも動作させる -->
<key>NSMicrophoneUsageDescription</key>
<string>音楽ファイルの再生に使用します</string>
```

## Windsurf での作業の流れ

1. `flutter pub get` でパッケージをインストール
2. iOS Simulator または実機でデバッグ実行
3. ライブラリ画面の「曲を追加」→ ファイルアプリから .mp3 / .flac を選択
4. 「歌詞を選択」→ 同名の .lrc ファイルを選択
5. 曲をタップ → 再生画面で歌詞が同期スクロールされることを確認
