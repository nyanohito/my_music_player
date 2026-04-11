// ============================================================
// models/song.dart
// 1曲分の楽曲情報を保持するモデル
// ============================================================

import 'dart:typed_data';
import 'lyric_line.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// 1曲分の楽曲情報
///
/// ファイルピッカーで選んだ音楽ファイルと
/// オプションのLRCファイルをまとめて管理する
class Song {
  /// データベース用の一意ID
  final String id;

  /// 曲のタイトル（ファイル名から自動生成 or ID3タグから取得）
  final String title;

  /// アーティスト名（未設定の場合は "Unknown Artist"）
  final String artist;

  /// 音楽ファイルの絶対パス（例: /var/mobile/.../song.flac）
  final String filePath;

  /// LRCファイルのパス（歌詞なしの場合はnull）
  final String? lrcPath;

  /// パース済み歌詞データ（LRCがない場合は空リスト）
  final List<LyricLine> lyrics;

  /// アルバムアートワークのバイトデータ（nullの場合はデフォルト表示）
  final Uint8List? albumArt;

  /// お気に入り状態
  final bool isFavorite;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.filePath,
    this.lrcPath,
    this.lyrics = const [],
    this.albumArt,
    this.isFavorite = false,
  });

  /// ファイルパスからシンプルなSongを生成するファクトリ
  ///
  /// Windsurfでの開発時、まずここから始めると楽です
  factory Song.fromPath(String filePath) {
    // pathパッケージを使って拡張子を除いたファイル名を取得
    final titleWithoutExtension = p.basenameWithoutExtension(filePath);

    return Song(
      id: const Uuid().v4(),
      title: titleWithoutExtension,
      artist: 'Unknown Artist',
      filePath: filePath,
    );
  }

  /// 歌詞データをセットした新しいSongを返す（イミュータブル更新）
  Song copyWithLyrics({
    String? lrcPath,
    List<LyricLine>? lyrics,
  }) {
    return Song(
      id: id,
      title: title,
      artist: artist,
      filePath: filePath,
      lrcPath: lrcPath ?? this.lrcPath,
      lyrics: lyrics ?? this.lyrics,
      albumArt: albumArt,
      isFavorite: isFavorite,
    );
  }

  /// アルバムアートワークをセットした新しいSongを返す
  Song copyWithAlbumArt(Uint8List? albumArt) {
    return Song(
      id: id,
      title: title,
      artist: artist,
      filePath: filePath,
      lrcPath: lrcPath,
      lyrics: lyrics,
      albumArt: albumArt,
      isFavorite: isFavorite,
    );
  }

  /// お気に入り状態を更新した新しいSongを返す
  Song copyWithFavorite(bool isFavorite) {
    return Song(
      id: id,
      title: title,
      artist: artist,
      filePath: filePath,
      lrcPath: lrcPath,
      lyrics: lyrics,
      albumArt: albumArt,
      isFavorite: isFavorite,
    );
  }

  /// データベース保存用のMapに変換
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filePath': filePath,
      'title': title,
      'artist': artist,
      'isFavorite': isFavorite ? 1 : 0,
    };
  }

  /// データベースから読み込んだMapからSongを生成
  static Song fromMap(Map<String, dynamic> map) {
    return Song(
      id: map['id'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String,
      filePath: map['filePath'] as String,
      lrcPath: map['lrcPath'] as String?,
      lyrics: map['lyrics'] != null 
          ? (map['lyrics'] as List<dynamic>).map((item) => LyricLine(
              position: Duration(milliseconds: item['position'] as int),
              text: item['text'] as String,
            )).toList()
          : const [],
      albumArt: map['albumArt'] as Uint8List?,
      isFavorite: (map['isFavorite'] as int) == 1,
    );
  }

  /// 歌詞を持っているかどうか
  bool get hasLyrics => lyrics.isNotEmpty;

  /// 新しいSongオブジェクトを生成（一部プロパティを更新）
  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? filePath,
    String? lrcPath,
    List<LyricLine>? lyrics,
    Uint8List? albumArt,
    bool? isFavorite,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      filePath: filePath ?? this.filePath,
      lrcPath: lrcPath ?? this.lrcPath,
      lyrics: lyrics ?? this.lyrics,
      albumArt: albumArt ?? this.albumArt,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
