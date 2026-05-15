// ============================================================
// providers/audio_player_provider.dart
// ★ 【完全版】画像読み込みを無効化し、堅牢性を最大化したプレイヤー
// ============================================================

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:uuid/uuid.dart';

import '../models/lyric_line.dart';
import '../models/song.dart';
import '../utils/lrc_parser.dart';
import '../utils/database_helper.dart';

enum PlaylistMode { off, one, all }

class LocalFileStreamAudioSource extends StreamAudioSource {
  final String filePath;
  LocalFileStreamAudioSource(this.filePath);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final file = File(filePath);
    final length = await file.length();
    start ??= 0;
    end ??= length;
    final stream = file.openRead(start, end);
    return StreamAudioResponse(
      sourceLength: length,
      contentLength: end - start,
      offset: start,
      stream: stream,
      contentType: 'audio/mpeg',
    );
  }
}

class AudioPlayerState {
  final List<Song> playlist;
  final int currentSongIndex;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final int currentLyricIndex;
  final bool isLoading;
  final String? errorMessage;
  final bool isShuffleModeEnabled;
  final PlaylistMode repeatMode;
  final List<Map<String, dynamic>> playlists;
  final double playbackSpeed;

  const AudioPlayerState({
    this.playlist = const [],
    this.currentSongIndex = -1,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.currentLyricIndex = -1,
    this.isLoading = false,
    this.errorMessage,
    this.isShuffleModeEnabled = false,
    this.repeatMode = PlaylistMode.off,
    this.playlists = const [],
    this.playbackSpeed = 1.0,
  });

  AudioPlayerState copyWith({
    List<Song>? playlist,
    int? currentSongIndex,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    int? currentLyricIndex,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool? isShuffleModeEnabled,
    PlaylistMode? repeatMode,
    List<Map<String, dynamic>>? playlists,
    double? playbackSpeed,
  }) {
    return AudioPlayerState(
      playlist: playlist ?? this.playlist,
      currentSongIndex: currentSongIndex ?? this.currentSongIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      currentLyricIndex: currentLyricIndex ?? this.currentLyricIndex,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isShuffleModeEnabled: isShuffleModeEnabled ?? this.isShuffleModeEnabled,
      repeatMode: repeatMode ?? this.repeatMode,
      playlists: playlists ?? this.playlists,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    );
  }

  Song? get currentSong {
    if (currentSongIndex >= 0 && currentSongIndex < playlist.length) {
      return playlist[currentSongIndex];
    }
    return null;
  }
  bool get hasSongs => playlist.isNotEmpty;
  bool get hasCurrentSong => currentSong != null;
}

class AudioPlayerNotifier extends StateNotifier<AudioPlayerState> {
  final AudioPlayer _player = AudioPlayer();
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<double> get volumeStream => _player.volumeStream;
  void setVolume(double value) => _player.setVolume(value);

  Future<void> setPlaybackSpeed(double speed) async {
    try {
      final safeSpeed = Platform.isIOS ? speed.clamp(0.5, 1.5) : speed.clamp(0.5, 2.0); 
      if (Platform.isIOS) {
        await _player.setSpeed(safeSpeed);
        await _player.setPitch(1.0);
      } else {
        await _player.setSpeed(safeSpeed);
      }
      state = state.copyWith(playbackSpeed: safeSpeed);
    } catch (e) {
      _logError('速度変更エラー: $e');
    }
  }

  final DatabaseHelper _dbHelper = DatabaseHelper();
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<int?>? _currentIndexSubscription;
  StreamSubscription<void>? _interruptionSubscription; // Feature 2: 割り込み復帰

  // Feature 1: 再生状態を5秒おきに保存するための最終保存時刻
  DateTime _lastStateSavedAt = DateTime.fromMillisecondsSinceEpoch(0);

  // --- 📝 ログ管理用ヘルパー ---
  void _log(String message) {
    print('[DIAGNOSTICS] $message');
    state = state.copyWith(errorMessage: message);
  }

  void _logError(String message) {
    print('[DIAGNOSTICS_ERROR] $message');
    state = state.copyWith(errorMessage: '❌ $message');
  }
  // -----------------------------

  Future<String> _copyFileToLocalDirectory(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) throw Exception('Source file does not exist: $sourcePath');
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = p.basename(sourcePath);
    final localPath = p.join(appDir.path, fileName);
    final localFile = File(localPath);
    if (await localFile.exists()) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final nameWithoutExt = p.basenameWithoutExtension(localPath);
      final extension = p.extension(localPath);
      final uniqueFileName = '${nameWithoutExt}_$timestamp$extension';
      final uniquePath = p.join(appDir.path, uniqueFileName);
      await File(sourcePath).openRead().pipe(File(uniquePath).openWrite());
      return uniqueFileName; 
    } else {
      await File(sourcePath).openRead().pipe(File(localPath).openWrite());
      return fileName; 
    }
  }

  Future<String> _getFullPath(String filePath) async {
    if (p.isAbsolute(filePath)) return filePath;
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, filePath);
  }

  AudioPlayer get player => _player;

  AudioPlayerNotifier() : super(const AudioPlayerState()) {
    _initAudioSession();
    _subscribeToPlayerStreams();
    _loadSavedSongs();
  }

  Future<void> _loadSavedSongs() async {
    try {
      _log('DBから曲を読み込み中...');
      final savedSongs = await _dbHelper.getAllSongs();
      final playlists = await _dbHelper.getAllPlaylists();

      _log('DBに ${savedSongs.length} 曲ありました。');

      final List<Song> validSongs = [];
      final List<AudioSource> audioSources = [];

      for (final song in savedSongs) {
        final fullPath = await _getFullPath(song.filePath);
        if (!await File(fullPath).exists()) continue;

        List<LyricLine>? parsedLyrics;
        if (song.lrcPath != null && song.lrcPath!.isNotEmpty) {
          try {
            final lrcFullPath = await _getFullPath(song.lrcPath!);
            final lrcFile = File(lrcFullPath);
            if (await lrcFile.exists()) {
              final lrcContent = await lrcFile.readAsString();
              parsedLyrics = LrcParser.parse(lrcContent);
            }
          } catch (_) {}
        }

        var updatedSong = song;
        if (parsedLyrics != null && parsedLyrics.isNotEmpty) {
          updatedSong = updatedSong.copyWith(lyrics: parsedLyrics);
        }
        validSongs.add(updatedSong);

        if (Platform.isAndroid || Platform.isIOS) {
          audioSources.add(AudioSource.uri(
            Uri.file(fullPath),
            tag: MediaItem(id: updatedSong.id, title: updatedSong.title, artist: updatedSong.artist, artUri: null),
          ));
        } else {
          audioSources.add(LocalFileStreamAudioSource(fullPath));
        }
      }

      state = state.copyWith(playlist: validSongs, playlists: playlists);

      if (audioSources.isNotEmpty) {
        final playlist = ConcatenatingAudioSource(children: audioSources);
        await _player.setAudioSource(playlist, initialPosition: Duration.zero, preload: false);
      }
      _log('起動完了: 有効な曲は ${validSongs.length} 曲です。');

      // Feature 1: 保存された再生状態を復元する
      await _restorePlaybackState(validSongs.length);

    } catch (e) {
      _logError('起動時ロードエラー: $e');
    }
  }

  /// Feature 1: 起動時に最後の再生位置へシークする（再生はしない）
  Future<void> _restorePlaybackState(int playlistLength) async {
    try {
      final saved = await _dbHelper.loadPlaybackState();
      if (saved == null) return;
      if (saved.songIndex < 0 || saved.songIndex >= playlistLength) return;

      _log('前回の再生位置を復元: index=${saved.songIndex}, pos=${saved.positionMs}ms');

      // プレイヤーに反映（seek のみ。play() は呼ばない）
      await _player.seek(
        Duration(milliseconds: saved.positionMs),
        index: saved.songIndex,
      );
      state = state.copyWith(currentSongIndex: saved.songIndex);
    } catch (e) {
      // 復元失敗は致命的ではないので握り潰す
      print('[AudioPlayer] restorePlaybackState failed: $e');
    }
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;

    // Feature 2: Spotify相当のオーディオセッション設定
    // 🚨 修正: `AudioSessionConfiguration` の前の `const` を削除しました
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.allowBluetoothA2dp,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.longFormAudio,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      // 代わりにこちらに const を付けます
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: false, // ナビ案内時は duck（音量下げ）で共存
    ));

    // Feature 2: 割り込み（電話・Siri・ナビ）からの復帰処理
    _interruptionSubscription = session.interruptionEventStream.listen((event) {
      if (event.begin) {
        // 割り込み開始 → 一時停止
        if (_player.playing) _player.pause();
      } else {
        // 割り込み終了 → shouldResume が true なら自動再生再開
        switch (event.type) {
          case AudioInterruptionType.pause:
          case AudioInterruptionType.duck:
            if (event.type == AudioInterruptionType.duck) {
              // duck 終了は音量を戻すだけ（just_audio が自動処理）
            } else if (state.isPlaying) {
              _player.play();
            }
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });

    // Feature 2: Bluetooth接続/切断イベントを監視し、接続時に再生再開
    session.devicesChangedEventStream.listen((event) {
      final connected = event.devicesAdded.where((d) =>
          d.type.name.toLowerCase().contains('bluetooth'));
      if (connected.isNotEmpty && !_player.playing && state.hasSongs) {
        // Bluetooth デバイスが接続されたら0.5秒待って再生
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!_player.playing) _player.play();
        });
      }
    });

    await session.setActive(true);
  }

  void _subscribeToPlayerStreams() {
    _positionSubscription = _player.positionStream.listen((position) {
      final safePosition = position > state.duration ? state.duration : position;
      final lyricIndex = _getCurrentLyricIndex(state.currentSong?.lyrics ?? [], safePosition);
      state = state.copyWith(position: safePosition, currentLyricIndex: lyricIndex);

      // Feature 1: 5秒おきに再生状態を永続化（連続書き込みを防ぐ）
      final now = DateTime.now();
      if (state.currentSongIndex >= 0 &&
          now.difference(_lastStateSavedAt).inSeconds >= 5) {
        _lastStateSavedAt = now;
        _dbHelper.savePlaybackState(
          songIndex: state.currentSongIndex,
          positionMs: safePosition.inMilliseconds,
        );
      }
    });

    _durationSubscription = _player.durationStream.listen((duration) {
      if (duration != null) {
        final safePosition = state.position > duration ? duration : state.position;
        state = state.copyWith(duration: duration, position: safePosition);
      }
    });

    _playerStateSubscription = _player.playerStateStream.listen((playerState) {
      state = state.copyWith(
        isPlaying: playerState.playing,
        isLoading: playerState.processingState == ProcessingState.loading ||
            playerState.processingState == ProcessingState.buffering,
      );
    });

    _currentIndexSubscription = _player.currentIndexStream.listen((index) {
      if (index == null) return;
      if (index >= 0 && index < state.playlist.length) {
        if (state.currentSongIndex != index) {
          final song = state.playlist[index];
          DatabaseHelper().addPlayHistory(song.id);
        }
        state = state.copyWith(currentSongIndex: index);
      }
    });
  }

  // 🚀 修正：画像読み込み機能を完全に無効化（エラー原因の徹底排除）
  Future<Uint8List?> _extractAlbumArt(String filePath) async {
    return null;
  }

  Future<Song> _createSongFromMetadata(String absolutePath) async {
    try {
      final metadata = await MetadataGod.readMetadata(file: absolutePath).timeout(const Duration(seconds: 2));
      final String title = p.basenameWithoutExtension(absolutePath);
      final String rawArtist = metadata.artist ?? '';
      final String artist = (rawArtist.isEmpty || rawArtist.toLowerCase().contains('unknown')) ? 'Mrs. GREEN APPLE' : rawArtist;
      final String fileName = p.basename(absolutePath);
      return Song(id: const Uuid().v4(), title: title, artist: artist, filePath: fileName);
    } catch (e) {
      final String fileName = p.basename(absolutePath);
      final song = Song.fromPath(fileName);
      final String rawArtist = song.artist ?? '';
      if (rawArtist.isEmpty || rawArtist.toLowerCase().contains('unknown')) {
        return song.copyWith(artist: 'Mrs. GREEN APPLE');
      }
      return song;
    }
  }

  // 🚀 修正：画像読み込みを行わないため、中身を空にして即終了
  Future<void> loadAlbumArtForCurrentSong() async {
    return;
  }

  Future<void> pickAndLoadSong() async {
    _log('ファイル選択画面を開きます...');
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true, 
        type: FileType.custom,
        allowedExtensions: ['mp3', 'flac', 'aac', 'm4a', 'wav', 'ogg', 'opus', 'wma', 'alac', 'aiff', 'aif', 'lrc'],
      );
      
      if (result == null) {
        _logError('キャンセル、またはiOSメモリ限界で強制終了しました。');
        return;
      }
      if (result.files.isEmpty) {
        _logError('選択されたファイルが0件です。');
        return;
      }

      state = state.copyWith(isLoading: true);
      _log('${result.files.length}件のファイルを処理中...');
      
      final List<Song> newSongs = [];
      final Map<String, List<PlatformFile>> groups = {};

      for (final file in result.files) {
        if (file.path == null) continue;
        final dir = p.dirname(file.path!);
        final name = p.basenameWithoutExtension(file.path!).toLowerCase();
        groups.putIfAbsent('$dir/$name', () => []).add(file);
      }

      const audioExtensions = {'mp3', 'flac', 'aac', 'm4a', 'wav', 'ogg', 'opus', 'wma', 'alac', 'aiff', 'aif'};
      int processedCount = 0;

      for (final entry in groups.entries) {
        try {
          final files = entry.value;
          PlatformFile? audioFile;
          PlatformFile? lrcFile;

          for (final f in files) {
            final ext = p.extension(f.path!).replaceFirst('.', '').toLowerCase();
            if (ext == 'lrc') lrcFile = f;
            else if (audioExtensions.contains(ext)) audioFile = f;
          }

          if (audioFile == null || audioFile.path == null) continue;

          final audioFileName = await _copyFileToLocalDirectory(audioFile.path!);
          final audioFullPath = await _getFullPath(audioFileName);
          
          var song = await _createSongFromMetadata(audioFullPath);

          String? lrcFileName;
          List<LyricLine> parsedLyrics = [];

          if (lrcFile != null && lrcFile.path != null) {
            try {
              lrcFileName = await _copyFileToLocalDirectory(lrcFile.path!);
              final lrcFullPath = await _getFullPath(lrcFileName);
              parsedLyrics = await _parseLrcFile(lrcFullPath);
              song = song.copyWith(lrcPath: lrcFileName, lyrics: parsedLyrics);
            } catch (_) {}
          }

          song = song.copyWith(filePath: song.filePath.split('/').last, lrcPath: song.lrcPath != null ? song.lrcPath!.split('/').last : null);
          await _dbHelper.insertOrUpdateSong(song);
          newSongs.add(song);

          processedCount++;
          if (processedCount % 10 == 0) {
            _log('$processedCount曲 読み込み完了...');
            await Future.delayed(const Duration(milliseconds: 50));
          }
        } catch (e) { 
          _logError('エラー: $e');
          continue; 
        }
      }

      final previousLength = state.playlist.length;
      final allSongs = [...state.playlist, ...newSongs];
      state = state.copyWith(playlist: allSongs);

      if (_player.audioSource == null) {
        final audioSources = <AudioSource>[];
        for (final song in allSongs) {
          final fullPath = await _getFullPath(song.filePath);
          if (Platform.isAndroid || Platform.isIOS) {
            audioSources.add(AudioSource.uri(Uri.file(fullPath), tag: MediaItem(id: song.id, title: song.title, artist: song.artist, artUri: null)));
          } else {
            audioSources.add(LocalFileStreamAudioSource(fullPath));
          }
        }
        final playlist = ConcatenatingAudioSource(children: audioSources);
        await _player.setAudioSource(playlist, initialIndex: previousLength);
        _player.play(); 
      } else {
        await _appendSongsToCurrentPlaylist(newSongs);
      }
      _log('完了！新しく ${newSongs.length} 曲追加しました。');
    } catch (e) {
      _logError('全体エラー発生: $e');
    } finally {
      state = state.copyWith(isLoading: false);
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) state = state.copyWith(clearError: true);
      });
    }
  }

  Future<int> pickAndLoadFolder() async {
    _log('フォルダ選択画面を開きます...');
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true);
      
      if (result == null) {
        _logError('キャンセル、またはiOSメモリ限界で強制終了しました。');
        return 0;
      }
      if (result.files.isEmpty) {
        _logError('選択されたファイルが0件です。');
        return 0;
      }

      state = state.copyWith(isLoading: true);
      _log('${result.files.length}件のファイルを処理中...');

      final List<Song> newSongs = [];
      final allowedExtensions = ['.mp3', '.m4a', '.flac', '.wav', '.aac', '.lrc'];
      final filteredFiles = result.files.where((file) {
        if (file.path == null) return false;
        final extension = p.extension(file.path!).toLowerCase();
        return allowedExtensions.contains(extension);
      }).toList();
      
      final Map<String, List<PlatformFile>> groupedFiles = {};
      for (final file in filteredFiles) {
        if (file.path != null) {
          final extension = p.extension(file.path!).toLowerCase();
          final dir = p.dirname(file.path!);
          final fileName = p.basenameWithoutExtension(file.path!).toLowerCase();
          final key = '$dir/$fileName'; 
          
          if (['.mp3', '.m4a', '.flac', '.wav', '.aac'].contains(extension)) {
            if (!groupedFiles.containsKey(key)) groupedFiles[key] = [];
            groupedFiles[key]!.add(file);
          } else if (extension == '.lrc') {
            if (!groupedFiles.containsKey(key)) groupedFiles[key] = [];
            groupedFiles[key]!.add(file);
          }
        }
      }
      
      int processedCount = 0;
      for (final entry in groupedFiles.entries) {
        final files = entry.value;
        PlatformFile? audioFile;
        PlatformFile? lrcFile;
        for (final file in files) {
          final extension = p.extension(file.path!).toLowerCase();
          if (['.mp3', '.m4a', '.flac', '.wav', '.aac'].contains(extension)) audioFile = file;
          else if (extension == '.lrc') lrcFile = file;
        }
        
        if (audioFile != null && audioFile.path != null) {
          try { 
            final audioFileName = await _copyFileToLocalDirectory(audioFile.path!);
            final audioFullPath = await _getFullPath(audioFileName);
            var song = await _createSongFromMetadata(audioFullPath);
            
            if (lrcFile != null && lrcFile.path != null) {
              final lrcFileName = await _copyFileToLocalDirectory(lrcFile.path!);
              final lrcFullPath = await _getFullPath(lrcFileName);
              final lyrics = await _parseLrcFile(lrcFullPath);
              song = song.copyWith(lrcPath: lrcFileName, lyrics: lyrics);
            }
            
            song = song.copyWith(
              filePath: song.filePath.split('/').last,
              lrcPath: song.lrcPath != null ? song.lrcPath!.split('/').last : null,
            );
            await _dbHelper.insertOrUpdateSong(song);
            newSongs.add(song);

            processedCount++;
            if (processedCount % 10 == 0) {
              _log('$processedCount曲 読み込み完了...');
              await Future.delayed(const Duration(milliseconds: 50));
            }
          } catch (e) {
            _logError('エラー: $e');
            continue; 
          }
        }
      }

      final previousLength = state.playlist.length;
      final allSongs = [...state.playlist, ...newSongs];
      state = state.copyWith(playlist: allSongs);

      if (_player.audioSource == null) {
        final audioSources = <AudioSource>[];
        for (final song in allSongs) {
          final fullPath = await _getFullPath(song.filePath);
          if (Platform.isAndroid || Platform.isIOS) {
            audioSources.add(AudioSource.uri(Uri.file(fullPath), tag: MediaItem(id: song.id, title: song.title, artist: song.artist, artUri: null)));
          } else {
            audioSources.add(LocalFileStreamAudioSource(fullPath));
          }
        }
        final playlist = ConcatenatingAudioSource(children: audioSources);
        await _player.setAudioSource(playlist, initialIndex: previousLength);
        _player.play(); 
      } else {
        await _appendSongsToCurrentPlaylist(newSongs);
      }
      _log('完了！新しく ${newSongs.length} 曲追加しました。');
      return newSongs.length;
    } catch (e) {
      _logError('全体エラー発生: $e');
      return 0;
    } finally {
      state = state.copyWith(isLoading: false);
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) state = state.copyWith(clearError: true);
      });
    }
  }

  /// Feature 4: インクリメンタルスキャン
  /// - ファイルの最終更新日時を比較し、変更がある曲だけ更新する
  /// - MetadataGod が失敗したファイルを破損リストに追加してフリーズを防ぐ
  Future<int> scanLocalDocuments() async {
    state = state.copyWith(isLoading: true);
    _log('スキャン開始: インクリメンタルモード');
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final List<FileSystemEntity> entities =
          await appDir.list(recursive: true).toList();

      final audioExtensions = {'.mp3', '.m4a', '.flac', '.wav', '.aac'};
      final List<File> audioFiles = [];
      final Map<String, File> lrcFiles = {};

      for (final entity in entities) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (audioExtensions.contains(ext)) {
            audioFiles.add(entity);
          } else if (ext == '.lrc') {
            final key = entity.path.substring(
                0, entity.path.length - ext.length);
            lrcFiles[key] = entity;
          }
        }
      }

      if (audioFiles.isEmpty) {
        _logError('スキャン対象の曲が見つかりません。');
        return 0;
      }

      _log('${audioFiles.length}個のファイルをスキャン中...');

      // Feature 4: 既存DBの modifiedAt マップを一括取得
      final existingModMap  = await _dbHelper.getSongModifiedAtMap();
      // Feature 4: 破損ファイルリストを取得（スキャン除外用）
      final brokenPaths     = await _dbHelper.getBrokenFilePaths();

      final List<Song> newSongs     = [];
      final List<Song> updatedSongs = [];
      int skippedCount = 0;
      int processedCount = 0;

      for (final file in audioFiles) {
        final relativePath = p.relative(file.path, from: appDir.path)
            .replaceAll('\\', '/');

        // Feature 4: 破損ファイルはスキップ
        if (brokenPaths.contains(relativePath) ||
            brokenPaths.contains(file.path)) {
          skippedCount++;
          continue;
        }

        // Feature 4: ファイルの最終更新日時を取得
        int fileModifiedAt = 0;
        try {
          final stat = await file.stat();
          fileModifiedAt = stat.modified.millisecondsSinceEpoch ~/ 1000;
        } catch (_) {}

        final savedModifiedAt = existingModMap[relativePath] ?? 0;

        // Feature 4: DB に保存済みで、更新日時も同じならスキップ
        if (existingModMap.containsKey(relativePath) &&
            savedModifiedAt > 0 &&
            fileModifiedAt <= savedModifiedAt) {
          skippedCount++;
          continue;
        }

        try {
          var song = await _createSongFromMetadata(file.path);

          final key = file.path.substring(
              0, file.path.length - p.extension(file.path).length);
          String? relativeLrcPath;
          List<LyricLine> lyrics = [];
          if (lrcFiles.containsKey(key)) {
            final lrcFile = lrcFiles[key]!;
            lyrics = await _parseLrcFile(lrcFile.path);
            relativeLrcPath = p.relative(lrcFile.path, from: appDir.path)
                .replaceAll('\\', '/');
          }

          song = song.copyWith(
            filePath: relativePath,
            lrcPath: relativeLrcPath,
            lyrics: lyrics,
          );
          await _dbHelper.insertOrUpdateSong(song);
          // Feature 4: 更新日時をDBに記録
          await _dbHelper.updateSongModifiedAt(song.id, fileModifiedAt);

          if (existingModMap.containsKey(relativePath)) {
            updatedSongs.add(song);
          } else {
            newSongs.add(song);
          }

          processedCount++;
          if (processedCount % 10 == 0) {
            _log('$processedCount曲 スキャン完了...');
            await Future.delayed(const Duration(milliseconds: 50));
          }
        } catch (e) {
          // Feature 4: 失敗ファイルを破損リストに登録
          _logError('ファイル読込エラー: $e');
          await _dbHelper.addBrokenFile(relativePath, errorMsg: e.toString());
          continue;
        }
      }

      if (newSongs.isNotEmpty) {
        final previousLength = state.playlist.length;
        final allSongs = [...state.playlist, ...newSongs];
        state = state.copyWith(playlist: allSongs);

        if (_player.audioSource == null) {
          final audioSources = <AudioSource>[];
          for (final song in allSongs) {
            final fullPath = await _getFullPath(song.filePath);
            if (Platform.isAndroid || Platform.isIOS) {
              audioSources.add(AudioSource.uri(
                Uri.file(fullPath),
                tag: MediaItem(
                  id: song.id,
                  title: song.title,
                  artist: song.artist,
                  artUri: null,
                ),
              ));
            } else {
              audioSources.add(LocalFileStreamAudioSource(fullPath));
            }
          }
          final playlist = ConcatenatingAudioSource(children: audioSources);
          await _player.setAudioSource(
              playlist, initialIndex: previousLength);
          _player.play();
        } else {
          await _appendSongsToCurrentPlaylist(newSongs);
        }
      }

      _log('スキャン完了! 追加:${newSongs.length} '
          '更新:${updatedSongs.length} スキップ:$skippedCount '
          '破損スキップ:${brokenPaths.length}');
      return newSongs.length;
    } catch (e) {
      _logError('スキャン中に致命的エラー: $e');
      return 0;
    } finally {
      state = state.copyWith(isLoading: false);
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) state = state.copyWith(clearError: true);
      });
    }
  }


  Future<void> _appendSongsToCurrentPlaylist(List<Song> newSongs) async {
    final newAudioSources = <AudioSource>[];
    for (final song in newSongs) {
      final fullPath = await _getFullPath(song.filePath);
      final audioSource = (Platform.isAndroid || Platform.isIOS)
          ? AudioSource.uri(Uri.file(fullPath), tag: MediaItem(id: song.id, title: song.title, artist: song.artist, artUri: null))
          : LocalFileStreamAudioSource(fullPath);
      newAudioSources.add(audioSource);
    }
    
    final currentAudioSource = _player.audioSource;
    if (currentAudioSource is ConcatenatingAudioSource) {
      await currentAudioSource.addAll(newAudioSources);
    }
  }

  Future<void> pickAndLoadLrc() async {
    if (!state.hasCurrentSong) return;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['lrc'], allowMultiple: false);
      if (result == null || result.files.isEmpty) return;
      final lrcPath = result.files.single.path;
      if (lrcPath == null) return;
      await updateSongLrcPath(state.currentSong!.id, lrcPath);
    } catch (e) {
      _logError('歌詞追加エラー: $e');
    }
  }

  Future<void> playSongAtIndex(int index) async {
    if (index < 0 || index >= state.playlist.length) return;
    state = state.copyWith(currentSongIndex: index);
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  Future<void> playNext() async {
    if (state.playlist.isEmpty) return;
    int nextIndex = state.currentSongIndex + 1;
    if (nextIndex >= state.playlist.length) {
      if (state.repeatMode == PlaylistMode.all) nextIndex = 0; else return; 
    }
    await playSongAtIndex(nextIndex);
  }

  Future<void> playPrevious() async {
    if (state.playlist.isEmpty) return;
    int prevIndex = state.currentSongIndex - 1;
    if (prevIndex < 0) {
      if (state.repeatMode == PlaylistMode.all) prevIndex = state.playlist.length - 1; else return; 
    }
    await playSongAtIndex(prevIndex);
  }

  Future<void> toggleShuffle() async {
    final newShuffleState = !state.isShuffleModeEnabled;
    state = state.copyWith(isShuffleModeEnabled: newShuffleState);
    await _player.setShuffleModeEnabled(newShuffleState);
  }

  Future<void> toggleFavorite(String songId) async {
    try {
      await _dbHelper.toggleFavorite(songId);
      final updatedPlaylist = state.playlist.map((song) {
        if (song.id == songId) return song.copyWithFavorite(!song.isFavorite);
        return song;
      }).toList();
      state = state.copyWith(playlist: updatedPlaylist);
    } catch (e) {
      _logError('お気に入り切替エラー: $e');
    }
  }

  Future<List<Song>> searchSongs(String query) async {
    return await _dbHelper.searchSongs(query);
  }

  Future<List<Song>> getFavoriteSongs() async {
    return await _dbHelper.getFavoriteSongs();
  }

  Future<void> removeSong(String songId) async {
    try {
      final songIndex = state.playlist.indexWhere((song) => song.id == songId);
      if (songIndex == -1) return;
      if (_player.audioSource != null) {
        final concatenatingSource = _player.audioSource as ConcatenatingAudioSource;
        await concatenatingSource.removeAt(songIndex);
      }
      await _dbHelper.deleteSong(songId);
      final updatedPlaylist = List<Song>.from(state.playlist)..removeAt(songIndex);
      int newCurrentIndex = state.currentSongIndex;
      if (songIndex < state.currentSongIndex) {
        newCurrentIndex = state.currentSongIndex - 1;
      } else if (songIndex == state.currentSongIndex && newCurrentIndex >= updatedPlaylist.length) {
        newCurrentIndex = updatedPlaylist.length > 0 ? 0 : -1;
      }
      state = state.copyWith(playlist: updatedPlaylist, currentSongIndex: newCurrentIndex);
    } catch (e) {
      _logError('曲の削除エラー: $e');
    }
  }

  Future<void> toggleRepeat() async {
    PlaylistMode newMode;
    switch (state.repeatMode) {
      case PlaylistMode.off: newMode = PlaylistMode.one; break;
      case PlaylistMode.one: newMode = PlaylistMode.all; break;
      case PlaylistMode.all: newMode = PlaylistMode.off; break;
    }
    state = state.copyWith(repeatMode: newMode);
    LoopMode loopMode;
    switch (newMode) {
      case PlaylistMode.off: loopMode = LoopMode.off; break;
      case PlaylistMode.one: loopMode = LoopMode.one; break;
      case PlaylistMode.all: loopMode = LoopMode.all; break;
    }
    await _player.setLoopMode(loopMode);
  }

  Future<void> loadSong(Song song) async {
    await _loadPlaylist([song], 0);
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) await _player.pause(); else await _player.play();
  }

  Future<void> play() async => await _player.play();
  Future<void> pause() async => await _player.pause();
  Future<void> seekTo(Duration position) async => await _player.seek(position);

  Future<void> createPlaylist(String name) async {
    try {
      final playlistId = await _dbHelper.createPlaylist(name);
      final updatedPlaylists = [...state.playlists, {'id': playlistId, 'name': name}];
      state = state.copyWith(playlists: updatedPlaylists);
    } catch (e) {}
  }

  Future<void> addSongToPlaylist(String songId, String playlistId) async {
    try {
      await _dbHelper.addSongToPlaylist(playlistId, songId);
    } catch (e) {}
  }

  Future<void> loadPlaylists() async {
    try {
      final playlists = await _dbHelper.getAllPlaylists();
      state = state.copyWith(playlists: playlists);
    } catch (e) {}
  }

  Future<void> _loadPlaylist(List<Song> playlist, int startIndex) async {
    try {
      state = state.copyWith(isLoading: true, clearError: true);
      final List<AudioSource> audioSources = [];
      for (final song in playlist) {
        final fullPath = await _getFullPath(song.filePath);
        audioSources.add(Platform.isAndroid || Platform.isIOS
            ? AudioSource.uri(Uri.file(fullPath), tag: MediaItem(id: song.id, title: song.title, artist: song.artist, artUri: null))
            : LocalFileStreamAudioSource(fullPath));
      }
      final concatenatingSource = ConcatenatingAudioSource(useLazyPreparation: true, shuffleOrder: state.isShuffleModeEnabled ? DefaultShuffleOrder() : null, children: audioSources);
      await _player.setAudioSource(concatenatingSource, initialPosition: Duration.zero, preload: false);
      if (startIndex > 0) await _player.seek(Duration.zero, index: startIndex);
      await _player.play();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: '再生エラー: $e');
    }
  }

  int _getCurrentLyricIndex(List<LyricLine> lyrics, Duration position) {
    if (lyrics.isEmpty) return -1;
    final offsetMs = state.currentSong?.lyricOffset ?? 0;
    final adjustedPosition = Duration(milliseconds: (position.inMilliseconds + offsetMs).clamp(0, double.maxFinite.toInt()));
    int index = -1;
    for (int i = 0; i < lyrics.length; i++) {
      if (lyrics[i].position <= adjustedPosition) index = i; else break; 
    }
    return index;
  }

  Future<void> updateSongLrcPath(String songId, String lrcPath) async {
    try {
      final lrcFileName = await _copyFileToLocalDirectory(lrcPath);
      final fullLrcPath = await _getFullPath(lrcFileName);
      final lyrics = await _parseLrcFile(fullLrcPath);
      await _dbHelper.updateSongLrcPath(songId, lrcFileName);
      final updatedPlaylist = state.playlist.map<Song>((song) {
        if (song.id == songId) return song.copyWith(lrcPath: lrcFileName, lyrics: lyrics);
        return song;
      }).toList();
      state = state.copyWith(playlist: updatedPlaylist);
    } catch (e) {}
  }

  Future<void> updateLyricOffset(String songId, int deltaMs) async {
    try {
      final songIndex = state.playlist.indexWhere((s) => s.id == songId);
      if (songIndex == -1) return;
      final currentOffset = state.playlist[songIndex].lyricOffset;
      final newOffset = currentOffset + deltaMs;
      await _dbHelper.updateLyricOffset(songId, newOffset);
      final updatedPlaylist = List<Song>.from(state.playlist);
      updatedPlaylist[songIndex] = updatedPlaylist[songIndex].copyWith(lyricOffset: newOffset);
      state = state.copyWith(playlist: updatedPlaylist);
    } catch (e) {}
  }

  Future<List<LyricLine>> _parseLrcFile(String lrcPath) async {
    try {
      final file = File(lrcPath);
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final lines = content.split('\n');
      final lyrics = <LyricLine>[];
      for (final line in lines) {
        final match = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2})\](.*)').firstMatch(line);
        if (match != null) {
          final minutes = int.parse(match.group(1)!);
          final seconds = int.parse(match.group(2)!);
          final milliseconds = int.parse(match.group(3)!);
          final text = match.group(4)?.trim() ?? '';
          lyrics.add(LyricLine(position: Duration(minutes: minutes, seconds: seconds, milliseconds: milliseconds), text: text));
        }
      }
      return lyrics;
    } catch (e) { return []; }
  }

  @override
  void dispose() {
    // Feature 1: アプリ終了時に最後の状態を保存
    if (state.currentSongIndex >= 0) {
      _dbHelper.savePlaybackState(
        songIndex: state.currentSongIndex,
        positionMs: state.position.inMilliseconds,
      );
    }
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _currentIndexSubscription?.cancel();
    _interruptionSubscription?.cancel(); // Feature 2
    _player.dispose();
    super.dispose();
  }
}

final audioPlayerProvider = StateNotifierProvider<AudioPlayerNotifier, AudioPlayerState>(
  (ref) => AudioPlayerNotifier(),
);