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
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    // Songs table
    await db.execute('''
      CREATE TABLE songs (
        id TEXT PRIMARY KEY,
        filePath TEXT UNIQUE NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        isFavorite INTEGER DEFAULT 0,
        createdAt INTEGER DEFAULT (strftime('%s', 'now'))
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
        playlistId TEXT NOT NULL,
        songId TEXT NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (playlistId, songId),
        FOREIGN KEY (playlistId) REFERENCES playlists (id) ON DELETE CASCADE,
        FOREIGN KEY (songId) REFERENCES songs (id) ON DELETE CASCADE
      )
    ''');

    // Play history table
    await db.execute('''
      CREATE TABLE play_history (
        id TEXT PRIMARY KEY,
        songId TEXT NOT NULL,
        playedAt INTEGER NOT NULL,
        playDuration INTEGER DEFAULT 0,
        FOREIGN KEY (songId) REFERENCES songs (id) ON DELETE CASCADE
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_songs_filePath ON songs(filePath)');
    await db.execute('CREATE INDEX idx_songs_isFavorite ON songs(isFavorite)');
    await db.execute('CREATE INDEX idx_songs_title_artist ON songs(title, artist)');
    await db.execute('CREATE INDEX idx_playlist_songs_playlistId ON playlist_songs(playlistId)');
    await db.execute('CREATE INDEX idx_play_history_playedAt ON play_history(playedAt)');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle future database schema upgrades here
  }

  /// Insert or update a song
  Future<String> insertOrUpdateSong(Song song) async {
    final db = await database;
    
    // Check if song already exists by filePath
    final existing = await db.query(
      'songs',
      where: 'filePath = ?',
      whereArgs: [song.filePath],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      // Update existing song
      await db.update(
        'songs',
        {
          'title': song.title,
          'artist': song.artist,
          'isFavorite': song.isFavorite ? 1 : 0,
        },
        where: 'filePath = ?',
        whereArgs: [song.filePath],
      );
      return existing.first['id'] as String;
    } else {
      // Insert new song
      final songId = _uuid.v4();
      await db.insert('songs', {
        'id': songId,
        'filePath': song.filePath,
        'title': song.title,
        'artist': song.artist,
        'isFavorite': song.isFavorite ? 1 : 0,
      });
      return songId;
    }
  }

  /// Get all songs from database
  Future<List<Song>> getAllSongs() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'songs',
      orderBy: 'createdAt DESC',
    );

    return List.generate(maps.length, (i) {
      return Song.fromMap(maps[i]);
    });
  }

  /// Get favorite songs
  Future<List<Song>> getFavoriteSongs() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'songs',
      where: 'isFavorite = ?',
      whereArgs: [1],
      orderBy: 'createdAt DESC',
    );

    return List.generate(maps.length, (i) {
      return Song.fromMap(maps[i]);
    });
  }

  /// Search songs by title or artist
  Future<List<Song>> searchSongs(String query) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'songs',
      where: 'title LIKE ? OR artist LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'createdAt DESC',
    );

    return List.generate(maps.length, (i) {
      return Song.fromMap(maps[i]);
    });
  }

  /// Toggle favorite status
  Future<void> toggleFavorite(String songId) async {
    final db = await database;
    
    // Get current favorite status
    final result = await db.query(
      'songs',
      columns: ['isFavorite'],
      where: 'id = ?',
      whereArgs: [songId],
      limit: 1,
    );

    if (result.isNotEmpty) {
      final currentFavorite = result.first['isFavorite'] as int;
      final newFavorite = currentFavorite == 0 ? 1 : 0;
      
      await db.update(
        'songs',
        {'isFavorite': newFavorite},
        where: 'id = ?',
        whereArgs: [songId],
      );
    }
  }

  /// Get song by file path
  Future<Song?> getSongByFilePath(String filePath) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'songs',
      where: 'filePath = ?',
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
      where: 'filePath = ?',
      whereArgs: [filePath],
    );
  }

  /// Delete song by ID
  Future<void> deleteSong(String id) async {
    final db = await database;
    await db.delete(
      'songs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Create a new playlist
  Future<String> createPlaylist(String name) async {
    final db = await database;
    final playlistId = _uuid.v4();
    
    await db.insert('playlists', {
      'id': playlistId,
      'name': name,
    });
    
    return playlistId;
  }

  /// Get all playlists
  Future<List<Map<String, dynamic>>> getAllPlaylists() async {
    final db = await database;
    return await db.query(
      'playlists',
      orderBy: 'createdAt DESC',
    );
  }

  /// Add song to playlist
  Future<void> addSongToPlaylist(String playlistId, String songId, {int? position}) async {
    final db = await database;
    
    // Get current max position if not provided
    if (position == null) {
      final result = await db.rawQuery(
        'SELECT MAX(position) as maxPos FROM playlist_songs WHERE playlistId = ?',
        [playlistId],
      );
      position = (result.first['maxPos'] as int? ?? 0) + 1;
    }
    
    await db.insert('playlist_songs', {
      'playlistId': playlistId,
      'songId': songId,
      'position': position,
    });
  }

  /// Get songs in playlist
  Future<List<Song>> getPlaylistSongs(String playlistId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT s.*, ps.position FROM songs s
      INNER JOIN playlist_songs ps ON s.id = ps.songId
      WHERE ps.playlistId = ?
      ORDER BY ps.position ASC
    ''', [playlistId]);

    return List.generate(maps.length, (i) {
      return Song.fromMap(maps[i]);
    });
  }

  /// Remove song from playlist
  Future<void> removeSongFromPlaylist(String songId, String playlistId) async {
    final db = await database;
    await db.delete('playlist_songs', where: 'songId = ? AND playlistId = ?', whereArgs: [songId, playlistId]);
  }

  /// 指定された曲が、いずれかのプレイリストに登録されているかを確認する
  Future<bool> isSongInAnyPlaylist(String songId) async {
    final db = await database;
    final result = await db.query(
      'playlist_songs', 
      where: 'songId = ?', 
      whereArgs: [songId], 
      limit: 1
    );
    return result.isNotEmpty;
  }

  /// 再生履歴を追加
  Future<void> addPlayHistory(String songId, {int playDuration = 0}) async {
    final db = await database;
    final historyId = const Uuid().v4();
    
    await db.insert(
      'play_history',
      {
        'id': historyId,
        'songId': songId,
        'playedAt': DateTime.now().millisecondsSinceEpoch,
        'playDuration': playDuration,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 最近再生した曲のリストを取得
  Future<List<Song>> getRecentPlayHistory({int limit = 20}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT s.* FROM play_history ph
      INNER JOIN songs s ON ph.songId = s.id
      ORDER BY ph.playedAt DESC
      LIMIT ?
    ''', [limit]);

    return List.generate(maps.length, (i) {
      return Song.fromMap(maps[i]);
    });
  }

  /// Update song's LRC file path
  Future<void> updateSongLrcPath(String songId, String lrcPath) async {
    final db = await database;
    await db.update(
      'songs',
      {'lrcPath': lrcPath},
      where: 'id = ?',
      whereArgs: [songId],
    );
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
