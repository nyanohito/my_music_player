// ============================================================
// utils/lrc_parser.dart
// LRCファイルを解析して LyricLine のリストに変換するパーサー
// ============================================================
//
// LRCフォーマットの例:
//   [ti:曲名]
//   [ar:アーティスト名]
//   [00:12.34]歌詞のテキスト
//   [01:05.00]次の行の歌詞
//   [02:30.500]ミリ秒3桁にも対応

import '../models/lyric_line.dart';

class LrcParser {
  // [mm:ss.xx] または [mm:ss.xxx] の形式にマッチする正規表現
  // グループ1: 分, グループ2: 秒, グループ3: 小数部（2〜3桁）
  static final RegExp _timeTagRegex = RegExp(
    r'\[(\d{2}):(\d{2})\.(\d{2,3})\]',
  );

  /// LRCファイルの文字列を解析して LyricLine のリストを返す
  ///
  /// [lrcContent] LRCファイルの全文字列
  /// 戻り値: 時刻順にソートされた歌詞リスト
  static List<LyricLine> parse(String lrcContent) {
    final lines = lrcContent.split('\n');
    final List<LyricLine> result = [];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // [ti:], [ar:] などのメタデータ行はスキップ
      if (_isMetadataTag(trimmed)) continue;

      // 1行に複数のタイムタグがある場合にも対応
      // 例: [00:12.34][00:45.67]同じ歌詞
      final matches = _timeTagRegex.allMatches(trimmed);
      if (matches.isEmpty) continue;

      // タイムタグの後ろにあるテキスト部分を取り出す
      final text = trimmed.replaceAll(_timeTagRegex, '').trim();

      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final decimalStr = match.group(3)!;

        // 2桁なら×10してミリ秒に、3桁はそのままミリ秒
        final milliseconds = decimalStr.length == 2
            ? int.parse(decimalStr) * 10
            : int.parse(decimalStr);

        final position = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        result.add(LyricLine(position: position, text: text));
      }
    }

    // 時刻順にソートして返す（LRCが順不同でも安全に動作）
    result.sort((a, b) => a.position.compareTo(b.position));
    return result;
  }

  /// メタデータタグ行かどうかを判定
  /// 例: [ti:タイトル], [ar:アーティスト], [al:アルバム], [by:作成者]
  static bool _isMetadataTag(String line) {
    return RegExp(r'^\[(ti|ar|al|by|offset|re|ve):').hasMatch(line);
  }
}
