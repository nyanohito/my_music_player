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

  // ★ バージョンを 3 に上げる（再生履歴のバグ修正のためのリセット）
  static const int _dbVersion = 4;

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

    await db.execute('''
      CREATE TABLE playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        createdAt INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

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

    await db.execute('''
      CREATE TABLE play_history (
        id TEXT PRIMARY KEY,
        song_id TEXT NOT NULL,
        played_at INTEGER NOT NULL,
        play_duration INTEGER DEFAULT 0,
        FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_songs_file_path ON songs(file_path)');
    await db.execute('CREATE INDEX idx_songs_is_favorite ON songs(is_favorite)');
    await db.execute('CREATE INDEX idx_songs_title_artist ON songs(title, artist)');
    await db.execute('CREATE INDEX idx_playlist_songs_playlist_id ON playlist_songs(playlist_id)');
    await db.execute('CREATE INDEX idx_play_history_played_at ON play_history(played_at)');

    // ── 再生状態永続化テーブル ────────────────────────────────
    // アプリ再起動後に最後の再生位置を復元するためのKVストア
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_state (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // ── 破損ファイルキャッシュテーブル ────────────────────────
    // MetadataGod が失敗したパスを記録し、次回スキャンをスキップする
    await db.execute('''
      CREATE TABLE IF NOT EXISTS broken_files (
        file_path  TEXT PRIMARY KEY,
        failed_at  INTEGER NOT NULL,
        error_msg  TEXT
      )
    ''');

    // ── インクリメンタルスキャン用: 最終更新日時カラム ─────────
    // songs テーブルに file_modified_at を追加（新規作成時から）
    await db.execute('ALTER TABLE songs ADD COLUMN file_modified_at INTEGER DEFAULT 0');
  }

  /// ★ マイグレーション処理
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try { await db.execute('ALTER TABLE songs ADD COLUMN lrc_path TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE songs ADD COLUMN lyric_offset INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
    }
    if (oldVersion < 3) {
      // v3: 再生履歴の型不一致バグを修正するため、古いバグデータをリセットする
      try { await db.execute('DELETE FROM play_history'); } catch (_) {}
    }
    if (oldVersion < 4) {
      // v4: 再生状態永続化テーブルを追加
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS app_state (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      } catch (_) {}

      // v4: 破損ファイルキャッシュテーブルを追加
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS broken_files (
            file_path  TEXT PRIMARY KEY,
            failed_at  INTEGER NOT NULL,
            error_msg  TEXT
          )
        ''');
      } catch (_) {}

      // v4: songs テーブルに更新日時カラムを追加
      try {
        await db.execute(
          'ALTER TABLE songs ADD COLUMN file_modified_at INTEGER DEFAULT 0',
        );
      } catch (_) {}
    }
  }

  Future<void> insertOrUpdateSong(Song song) async {
    final db = await database;
    await db.insert('songs', song.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Song>> getAllSongs() async {
    final db = await database;
    final maps = await db.query('songs', orderBy: 'title ASC');
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<List<Song>> getFavoriteSongs() async {
    final db = await database;
    final maps = await db.query('songs', where: 'is_favorite = 1', orderBy: 'title ASC');
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<List<Song>> searchSongs(String query) async {
    final db = await database;
    final maps = await db.query('songs', where: 'title LIKE ? OR artist LIKE ?', whereArgs: ['%$query%', '%$query%'], orderBy: 'title ASC');
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<void> toggleFavorite(String songId) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE songs SET is_favorite = CASE WHEN is_favorite = 1 THEN 0 ELSE 1 END WHERE id = ?
    ''', [songId]);
  }

  Future<void> deleteSong(String songId) async {
    final db = await database;
    await db.delete('songs', where: 'id = ?', whereArgs: [songId]);
  }

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
    await db.insert('playlist_songs', {'playlist_id': playlistId, 'song_id': songId}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Song>> getPlaylistSongs(String playlistId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT s.* FROM songs s INNER JOIN playlist_songs ps ON s.id = ps.song_id
      WHERE ps.playlist_id = ? ORDER BY ps.position ASC
    ''', [playlistId]);
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<void> removeSongFromPlaylist(String songId, String playlistId) async {
    final db = await database;
    await db.delete('playlist_songs', where: 'song_id = ? AND playlist_id = ?', whereArgs: [songId, playlistId]);
  }

  Future<void> deletePlaylist(String playlistId) async {
    final db = await database;
    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
  }

  // ★ 修正：再生履歴バグの解消
  Future<void> addPlayHistory(String songId) async {
    final db = await database;
    await db.insert(
      'play_history',
      {
        'id': _uuid.v4(), // 必須のIDを追加
        'song_id': songId,
        'played_at': DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unix秒に修正
        'play_duration': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Song>> getRecentPlayHistory({int limit = 20}) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT s.* FROM songs s INNER JOIN (
        SELECT song_id, MAX(played_at) as last_played FROM play_history
        GROUP BY song_id ORDER BY last_played DESC LIMIT ?
      ) ph ON s.id = ph.song_id ORDER BY ph.last_played DESC
    ''', [limit]);
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<void> updateSongLrcPath(String songId, String lrcFileName) async {
    final safeFileName = lrcFileName.split('/').last;
    final db = await database;
    await db.update('songs', {'lrc_path': safeFileName}, where: 'id = ?', whereArgs: [songId]);
  }

  Future<void> updateLyricOffset(String songId, int offsetMs) async {
    final db = await database;
    await db.update('songs', {'lyric_offset': offsetMs}, where: 'id = ?', whereArgs: [songId]);
  }

  Future<Song?> getSongByFilePath(String filePath) async {
    final db = await database;
    final maps = await db.query('songs', where: 'file_path = ?', whereArgs: [filePath], limit: 1);
    if (maps.isNotEmpty) return Song.fromMap(maps.first);
    return null;
  }

  Future<void> deleteSongByFilePath(String filePath) async {
    final db = await database;
    await db.delete('songs', where: 'file_path = ?', whereArgs: [filePath]);
  }

  Future<bool> isSongInAnyPlaylist(String songId) async {
    final db = await database;
    final result = await db.query('playlist_songs', where: 'song_id = ?', whereArgs: [songId], limit: 1);
    return result.isNotEmpty;
  }


  // ──────────────────────────────────────────────────────────
  // 再生状態の永続化（Feature 1: Resume Playback）
  // ──────────────────────────────────────────────────────────

  /// 再生状態をDBに保存する
  /// [songIndex]: プレイリスト内のインデックス
  /// [positionMs]: 再生位置（ミリ秒）
  Future<void> savePlaybackState({
    required int songIndex,
    required int positionMs,
  }) async {
    final db = await database;
    final batch = db.batch();
    batch.insert(
      'app_state',
      {'key': 'last_song_index', 'value': songIndex.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    batch.insert(
      'app_state',
      {'key': 'last_position_ms', 'value': positionMs.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await batch.commit(noResult: true);
  }

  /// 保存された再生状態を取得する
  /// 保存されていない場合は null を返す
  Future<({int songIndex, int positionMs})?> loadPlaybackState() async {
    final db = await database;
    final rows = await db.query(
      'app_state',
      where: "key IN ('last_song_index', 'last_position_ms')",
    );
    final map = {for (final r in rows) r['key'] as String: r['value'] as String};
    if (!map.containsKey('last_song_index') ||
        !map.containsKey('last_position_ms')) {
      return null;
    }
    final index = int.tryParse(map['last_song_index']!);
    final posMs  = int.tryParse(map['last_position_ms']!);
    if (index == null || posMs == null) return null;
    return (songIndex: index, positionMs: posMs);
  }

  /// 再生状態の保存データを削除する（リセット時に呼ぶ）
  Future<void> clearPlaybackState() async {
    final db = await database;
    await db.delete(
      'app_state',
      where: "key IN ('last_song_index', 'last_position_ms')",
    );
  }

  // ──────────────────────────────────────────────────────────
  // 破損ファイルキャッシュ（Feature 4: インクリメンタルスキャン）
  // ──────────────────────────────────────────────────────────

  /// ファイルを破損リストに追加する
  Future<void> addBrokenFile(String filePath, {String? errorMsg}) async {
    final db = await database;
    await db.insert(
      'broken_files',
      {
        'file_path': filePath,
        'failed_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'error_msg': errorMsg,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 破損ファイルのパス一覧を取得する
  Future<Set<String>> getBrokenFilePaths() async {
    final db = await database;
    final rows = await db.query('broken_files', columns: ['file_path']);
    return rows.map((r) => r['file_path'] as String).toSet();
  }

  /// 破損リストをクリア（ユーザーが手動リスキャンするとき）
  Future<void> clearBrokenFiles() async {
    final db = await database;
    await db.delete('broken_files');
  }

  /// songs テーブルの file_modified_at を更新する
  Future<void> updateSongModifiedAt(String songId, int modifiedAt) async {
    final db = await database;
    await db.update(
      'songs',
      {'file_modified_at': modifiedAt},
      where: 'id = ?',
      whereArgs: [songId],
    );
  }

  /// file_path → file_modified_at のマップを一括取得（スキャン高速化）
  Future<Map<String, int>> getSongModifiedAtMap() async {
    final db = await database;
    final rows = await db.query('songs', columns: ['file_path', 'file_modified_at']);
    return {
      for (final r in rows)
        r['file_path'] as String: (r['file_modified_at'] as int?) ?? 0,
    };
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}