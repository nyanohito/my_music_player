// ============================================================
// utils/database_helper.dart
// SQLite database operations for persistent data storage
// ============================================================

import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../models/song.dart';

/// Database helper class for SQLite operations
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  final Uuid _uuid = const Uuid();

  // ★ バージョンを 2 に上げることで既存DBに onUpgrade が走る
  static const int _dbVersion = 2;

  /// Get database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'music_player.db');

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    // ★ songs テーブル: lrc_path と lyric_offset を最初から定義
    await db.execute('''
      CREATE TABLE IF NOT EXISTS songs (
        id           TEXT    PRIMARY KEY,
        title        TEXT    NOT NULL,
        artist       TEXT,
        file_path    TEXT    NOT NULL,
        lrc_path     TEXT,
        is_favorite  INTEGER NOT NULL DEFAULT 0,
        lyric_offset INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Playlists table
    await db.execute('''
      CREATE TABLE playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        createdAt INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // Playlist songs junction table
    await db.execute('''
      CREATE TABLE playlist_songs (
        playlist_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, song_id),
        FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE,
        FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE CASCADE
      )
    ''');

    // Play history table
    await db.execute('''
      CREATE TABLE play_history (
        id TEXT PRIMARY KEY,
        song_id TEXT NOT NULL,
        played_at INTEGER NOT NULL,
        play_duration INTEGER DEFAULT 0,
        FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE CASCADE
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_songs_file_path ON songs(file_path)');
    await db.execute('CREATE INDEX idx_songs_is_favorite ON songs(is_favorite)');
    await db.execute('CREATE INDEX idx_songs_title_artist ON songs(title, artist)');
    await db.execute('CREATE INDEX idx_playlist_songs_playlist_id ON playlist_songs(playlist_id)');
    await db.execute('CREATE INDEX idx_play_history_played_at ON play_history(played_at)');
  }

  /// ★ 既存 DB (v1) に新カラムを追加するマイグレーション
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2: lrc_path と lyric_offset を追加
    if (oldVersion < 2) {
      // カラムが既に存在する場合は例外を無視する
      try {
        await db.execute('ALTER TABLE songs ADD COLUMN lrc_path TEXT');
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE songs ADD COLUMN lyric_offset INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }
  }

  /// 挿入 or 上書き保存（song.toMap() 経由で全カラムを保存）
  Future<void> insertOrUpdateSong(Song song) async {
    final db = await database;
    await db.insert(
      'songs',
      song.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 全曲取得（lrc_path, lyric_offset を含む）
  Future<List<Song>> getAllSongs() async {
    final db = await database;
    final maps = await db.query('songs', orderBy: 'title ASC');
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<List<Song>> getFavoriteSongs() async {
    final db = await database;
    final maps =
        await db.query('songs', where: 'is_favorite = 1', orderBy: 'title ASC');
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<List<Song>> searchSongs(String query) async {
    final db = await database;
    final maps = await db.query(
      'songs',
      where: 'title LIKE ? OR artist LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'title ASC',
    );
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<void> toggleFavorite(String songId) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE songs
      SET    is_favorite = CASE WHEN is_favorite = 1 THEN 0 ELSE 1 END
      WHERE  id = ?
    ''', [songId]);
  }

  Future<void> deleteSong(String songId) async {
    final db = await database;
    await db.delete('songs', where: 'id = ?', whereArgs: [songId]);
  }

  // ──────────────────────────────────────────────────────────
  // CRUD: playlists
  // ──────────────────────────────────────────────────────────

  Future<String> createPlaylist(String name) async {
    final db = await database;
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await db.insert('playlists', {'id': id, 'name': name});
    return id;
  }

  Future<List<Map<String, dynamic>>> getAllPlaylists() async {
    final db = await database;
    return await db.query('playlists', orderBy: 'name ASC');
  }

  Future<void> addSongToPlaylist(String playlistId, String songId) async {
    final db = await database;
    await db.insert(
      'playlist_songs',
      {'playlist_id': playlistId, 'song_id': songId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Song>> getPlaylistSongs(String playlistId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT s.* FROM songs s
      INNER JOIN playlist_songs ps ON s.id = ps.song_id
      WHERE ps.playlist_id = ?
      ORDER BY ps.position ASC
    ''', [playlistId]);
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<void> removeSongFromPlaylist(String songId, String playlistId) async {
    final db = await database;
    await db.delete('playlist_songs',
        where: 'song_id = ? AND playlist_id = ?',
        whereArgs: [songId, playlistId]);
  }

  Future<void> deletePlaylist(String playlistId) async {
    final db = await database;
    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
  }

  // ──────────────────────────────────────────────────────────
  // 再生履歴
  // ──────────────────────────────────────────────────────────

  Future<void> addPlayHistory(String songId) async {
    final db = await database;
    await db.insert('play_history', {
      'song_id': songId,
      'played_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Song>> getRecentPlayHistory({int limit = 20}) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT s.* FROM play_history ph
      INNER JOIN songs s ON ph.song_id = s.id
      ORDER BY ph.played_at DESC
      LIMIT ?
    ''', [limit]);
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  /// ★ LRC ファイル名を DB に保存（ファイル名のみ、絶対パス禁止）
  /// これが呼ばれていなかった、または SQL が間違っていたケースを修正
  Future<void> updateSongLrcPath(String songId, String lrcFileName) async {
    // 防衛的サニタイズ: 万が一フルパスが渡されてもファイル名だけに変換
    final safeFileName = lrcFileName.split('/').last;

    final db = await database;
    final rowsAffected = await db.update(
      'songs',
      {'lrc_path': safeFileName},
      where: 'id = ?',
      whereArgs: [songId],
    );

    if (rowsAffected == 0) {
      // 対象行が存在しない場合はログに残す（例外を投げてもよい）
      print('[DB] updateSongLrcPath: no row found for id=$songId');
    } else {
      print('[DB] updateSongLrcPath: saved "$safeFileName" for id=$songId');
    }
  }

  /// ★ 歌詞オフセット（ms）を DB に保存
  Future<void> updateLyricOffset(String songId, int offsetMs) async {
    final db = await database;
    final rowsAffected = await db.update(
      'songs',
      {'lyric_offset': offsetMs},
      where: 'id = ?',
      whereArgs: [songId],
    );
    print('[DB] updateLyricOffset: offsetMs=$offsetMs for id=$songId '
        '(rows=$rowsAffected)');
  }

  /// Get song by file path
  Future<Song?> getSongByFilePath(String filePath) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'songs',
      where: 'file_path = ?',
      whereArgs: [filePath],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return Song.fromMap(maps.first);
    }
    return null;
  }

  /// Delete song by file path
  Future<void> deleteSongByFilePath(String filePath) async {
    final db = await database;
    await db.delete(
      'songs',
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
  }

  /// 指定された曲が、いずれかのプレイリストに登録されているかを確認する
  Future<bool> isSongInAnyPlaylist(String songId) async {
    final db = await database;
    final result = await db.query(
      'playlist_songs',
      where: 'song_id = ?',
      whereArgs: [songId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Close database
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
