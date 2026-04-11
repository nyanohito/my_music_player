// ============================================================
// models/lyric_line.dart
// LRCファイルの「1行分の歌詞データ」を表すシンプルなモデル
// ============================================================

/// LRCファイルの1行を表すデータクラス
///
/// 例: [01:23.45]サビのここが一番好き
///   → position: Duration(minutes: 1, seconds: 23, milliseconds: 450)
///   → text: "サビのここが一番好き"
class LyricLine {
  /// この歌詞が表示されるべき再生時刻
  final Duration position;

  /// 歌詞のテキスト（空行の場合もある）
  final String text;

  const LyricLine({
    required this.position,
    required this.text,
  });

  @override
  String toString() => '[${position.inSeconds}s] $text';
}
