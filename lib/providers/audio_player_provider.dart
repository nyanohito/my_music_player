// ============================================================
// providers/audio_player_provider.dart
// ★ アプリの心臓部：音楽再生の全状態とロジックを管理する
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
import 'package:metadata_god/metadata_god.dart'; // audiotags から変更
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
      // For iOS, limit speed range to prevent audio distortion
      final safeSpeed = Platform.isIOS 
          ? speed.clamp(0.5, 1.5) // Conservative range for iOS
          : speed.clamp(0.5, 2.0); // Full range for Android
      
      // Disable pitch compensation on iOS to prevent stuttering
      if (Platform.isIOS) {
        await _player.setSpeed(safeSpeed);
        // Ensure pitch is not changed when adjusting speed on iOS
        await _player.setPitch(1.0);
      } else {
        await _player.setSpeed(safeSpeed);
      }
      
      state = state.copyWith(playbackSpeed: safeSpeed);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to set playback speed: $e');
    }
  }

    
  final DatabaseHelper _dbHelper = DatabaseHelper();

  StreamSubscription<Duration>? _positionSubscription;

  /// Copy file to app's local directory and return the filename only
  Future<String> _copyFileToLocalDirectory(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Source file does not exist: $sourcePath');
    }

    final appDir = await getApplicationDocumentsDirectory();
    final fileName = p.basename(sourcePath);
    final localPath = p.join(appDir.path, fileName);
    
    // If file already exists, generate unique name
    final localFile = File(localPath);
    if (await localFile.exists()) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final nameWithoutExt = p.basenameWithoutExtension(localPath);
      final extension = p.extension(localPath);
      final uniqueFileName = '${nameWithoutExt}_$timestamp$extension';
      final uniquePath = p.join(appDir.path, uniqueFileName);
      // 
      await File(sourcePath).copy(uniquePath);
      return uniqueFileName; // Return filename only
    } else {
      // 
      await File(sourcePath).copy(localPath);
      return fileName; // Return filename only
    }
  }

  /// Get full absolute path from filename
  Future<String> _getFullPath(String fileName) async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, fileName);
  }
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<int?>? _currentIndexSubscription;

    
  AudioPlayer get player => _player;

  AudioPlayerNotifier() : super(const AudioPlayerState()) {
    _initAudioSession();
    _subscribeToPlayerStreams();
    _loadSavedSongs();
  }

  Future<void> _loadSavedSongs() async {
    try {
      final savedSongs = await _dbHelper.getAllSongs();
      final playlists = await _dbHelper.getAllPlaylists();

      // ★ 根本修正: state.playlist と ConcatenatingAudioSource を
      //   「常に同じ曲・同じ順序」で構築する。
      //   旧実装は state.playlist に全曲を入れた後で audioSources だけ欠損スキップ
      //   していたためインデックスがずれ「追加直後 0:00/0:00」を引き起こしていた。
      final List<Song> validSongs = [];
      final List<AudioSource> audioSources = [];

      for (final song in savedSongs) {
        final fullPath = await _getFullPath(song.filePath);

        // ファイルが存在しない曲は playlist にも AudioSource にも追加しない
        if (!await File(fullPath).exists()) {
          print('[AudioPlayer] File not found, skipping from playlist: $fullPath');
          continue;
        }

        // アルバムアート抽出
        final albumArt = await _extractAlbumArt(fullPath);

        // ★ Bug 1 Fix: LRC を readAsString → LrcParser.parse で確実に復元
        List<LyricLine>? parsedLyrics;
        if (song.lrcPath != null && song.lrcPath!.isNotEmpty) {
          try {
            final lrcFullPath = await _getFullPath(song.lrcPath!);
            final lrcFile = File(lrcFullPath);
            if (await lrcFile.exists()) {
              final lrcContent = await lrcFile.readAsString();
              parsedLyrics = LrcParser.parse(lrcContent);
            }
          } catch (e) {
            print('[AudioPlayer] Failed to restore lyrics for ${song.title}: $e');
          }
        }

        var updatedSong = song;
        if (albumArt != null) updatedSong = updatedSong.copyWithAlbumArt(albumArt);
        if (parsedLyrics != null && parsedLyrics.isNotEmpty) {
          updatedSong = updatedSong.copyWith(lyrics: parsedLyrics);
        }

        // state.playlist と audioSources に同時・同順で追加する
        validSongs.add(updatedSong);

        if (Platform.isAndroid || Platform.isIOS) {
          String? artUri;
          if (updatedSong.albumArt != null) {
            artUri = Uri.dataFromBytes(updatedSong.albumArt!).toString();
          }
          audioSources.add(AudioSource.uri(
            Uri.file(fullPath),
            tag: MediaItem(
              id: updatedSong.id,
              title: updatedSong.title,
              artist: updatedSong.artist,
              artUri: artUri != null ? Uri.parse(artUri) : null,
            ),
          ));
        } else {
          audioSources.add(LocalFileStreamAudioSource(fullPath));
        }
      }

      // playlist と AudioSource を同時に確定（順序保証）
      state = state.copyWith(
        playlist: validSongs,
        playlists: playlists,
      );

      if (audioSources.isNotEmpty) {
        final playlist = ConcatenatingAudioSource(children: audioSources);
        await _player.setAudioSource(playlist, initialPosition: Duration.zero, preload: false);
      }
    } catch (e) {
      print('Failed to load saved songs: $e');
    }
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  void _subscribeToPlayerStreams() {
    _positionSubscription = _player.positionStream.listen((position) {
      // Ensure position doesn't exceed duration
      final safePosition = state.duration != null && position > state.duration! 
          ? state.duration! 
          : position;
      
      final lyricIndex = _getCurrentLyricIndex(
        state.currentSong?.lyrics ?? [],
        safePosition,
      );
      state = state.copyWith(
        position: safePosition,
        currentLyricIndex: lyricIndex,
      );
    });

    _durationSubscription = _player.durationStream.listen((duration) {
      if (duration != null) {
        // Ensure current position is within new duration bounds
        final safePosition = state.position > duration ? duration : state.position;
        state = state.copyWith(
          duration: duration,
          position: safePosition,
        );
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
      if (index != null && state.currentSongIndex != index) {
        final song = state.playlist[index!];
        if (song != null) {
          DatabaseHelper().addPlayHistory(song.id);
        }
      }
      
      if (index != null && index >= 0 && index < state.playlist.length) {
        state = state.copyWith(
          currentSongIndex: index,
        );
      }
    });
  }

  // ✅ metadata_god に合わせた画像抽出ロジック
  Future<Uint8List?> _extractAlbumArt(String filePath) async {
    try {
      final metadata = await MetadataGod.readMetadata(file: filePath);
      return metadata.picture?.data;
    } catch (e) {
      return null;
    }
  }

  //  metadata_god  metadata extraction logic
  Future<Song> _createSongFromMetadata(String absolutePath) async {
    try {
      final metadata = await MetadataGod.readMetadata(file: absolutePath);
      
      final String title = p.basenameWithoutExtension(absolutePath);
      // ★ Bug 2 Fix: artist が null・空文字・"unknown" 含む場合は生成時点で強制書き換え
      final String rawArtist = metadata.artist ?? '';
      final String artist = (rawArtist.isEmpty ||
              rawArtist.toLowerCase().contains('unknown'))
          ? 'Mrs. GREEN APPLE'
          : rawArtist;
      // Safeguard: Always extract filename only, never store absolute paths
      final String fileName = p.basename(absolutePath);

      return Song(
        id: const Uuid().v4(),
        title: title,
        artist: artist,
        filePath: fileName, // CRITICAL: Always save only filename, never absolute path
      );
    } catch (e) {
      // Safeguard: Always extract filename only, never store absolute paths
      final String fileName = p.basename(absolutePath);
      // ★ Bug 2 Fix: fromPath 経由でも artist を強制書き換え
      final song = Song.fromPath(fileName);
      final String rawArtist = song.artist ?? '';
      if (rawArtist.isEmpty || rawArtist.toLowerCase().contains('unknown')) {
        return song.copyWith(artist: 'Mrs. GREEN APPLE');
      }
      return song;
    }
  }

  Future<void> pickAndLoadSong() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          // 
          'mp3', 'flac', 'aac', 'm4a', 'wav', 'ogg', 'opus', 'wma', 'alac',
          'aiff', 'aif',
          // 
          'lrc',
        ],
      );
      if (result == null || result.files.isEmpty) return;

      state = state.copyWith(isLoading: true);
      final List<Song> newSongs = [];

      // 
      final Map<String, List<PlatformFile>> groups = {};

      for (final file in result.files) {
        if (file.path == null) continue;
        final key = p.basenameWithoutExtension(file.path!).toLowerCase();
        groups.putIfAbsent(key, () => []).add(file);
      }

      // 
      const audioExtensions = {
        'mp3', 'flac', 'aac', 'm4a', 'wav', 'ogg', 'opus', 'wma', 'alac',
        'aiff', 'aif',
      };

      // 
      for (final entry in groups.entries) {
        try {
          final files = entry.value;

          // 
          PlatformFile? audioFile;
          PlatformFile? lrcFile;

          for (final f in files) {
            final ext = p.extension(f.path!).replaceFirst('.', '').toLowerCase();
            if (ext == 'lrc') {
              lrcFile = f;
            } else if (audioExtensions.contains(ext)) {
              audioFile = f;
            }
          }

          // 
          if (audioFile == null || audioFile.path == null) continue;

          // 
          final audioFileName = await _copyFileToLocalDirectory(audioFile.path!);
          final audioFullPath = await _getFullPath(audioFileName);
          
          // 
          var song = await _createSongFromMetadata(audioFullPath);
          
          // 
          final albumArt = await _extractAlbumArt(audioFullPath);
          if (albumArt != null) song = song.copyWithAlbumArt(albumArt);

          // 
          String? lrcFileName;
          List<LyricLine> parsedLyrics = [];

          if (lrcFile != null && lrcFile.path != null) {
            try {
              // 
              lrcFileName = await _copyFileToLocalDirectory(lrcFile.path!);
              final lrcFullPath = await _getFullPath(lrcFileName);
              parsedLyrics = await _parseLrcFile(lrcFullPath);
              
              // 
              song = song.copyWith(
                lrcPath: lrcFileName, // 
                lyrics: parsedLyrics,
              );
            } catch (lrcError) {
              // 
              print('[pickAndLoadSong] LRC: $lrcError');
              lrcFileName = null;
              parsedLyrics = [];
            }
          }

          // 
          song = song.copyWith(
            filePath: song.filePath.split('/').last, // 
            lrcPath: song.lrcPath != null ? song.lrcPath!.split('/').last : null,
          );
          
          await _dbHelper.insertOrUpdateSong(song);
          newSongs.add(song);
        } catch (e) {
          // 
          print('[pickAndLoadSong] Group error (${entry.key}): $e');
        }
      }

      // 
      final previousLength = state.playlist.length;
      final allSongs = [...state.playlist, ...newSongs];
      state = state.copyWith(playlist: allSongs);

      // 
      if (_player.audioSource == null) {
        final audioSources = <AudioSource>[];
        for (final song in allSongs) {
          final fullPath = await _getFullPath(song.filePath);
          final audioSource = (Platform.isAndroid || Platform.isIOS)
              ? AudioSource.uri(Uri.file(fullPath), tag: MediaItem(id: song.id, title: song.title, artist: song.artist))
              : LocalFileStreamAudioSource(fullPath);
          audioSources.add(audioSource);
        }
        final playlist = ConcatenatingAudioSource(children: audioSources);
        await _player.setAudioSource(playlist, initialIndex: previousLength);
        _player.play(); 
      } else {
        await _appendSongsToCurrentPlaylist(newSongs);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load songs: $e');
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }
  
  Future<void> _appendSongsToCurrentPlaylist(List<Song> newSongs) async {
    final newAudioSources = <AudioSource>[];
    for (final song in newSongs) {
      final fullPath = await _getFullPath(song.filePath);
      final audioSource = (Platform.isAndroid || Platform.isIOS)
          ? AudioSource.uri(Uri.file(fullPath), tag: MediaItem(id: song.id, title: song.title, artist: song.artist))
          : LocalFileStreamAudioSource(fullPath);
      newAudioSources.add(audioSource);
    }
    
    // Get current audio source and add new songs without stopping playback
    final currentAudioSource = _player.audioSource;
    if (currentAudioSource is ConcatenatingAudioSource) {
      await currentAudioSource.addAll(newAudioSources);
    }
  }

  Future<void> pickAndLoadLrc() async {
    if (!state.hasCurrentSong) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lrc'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final lrcPath = result.files.single.path;
      if (lrcPath == null) return;

      // ★ Bug Fix: 旧実装は元のパスをメモリにだけ読み込み DB を更新しないため
      //   再起動で歌詞が消えていた。updateSongLrcPath 経由で
      //   ① アプリローカルにコピー ② DB 更新 ③ state 更新 を確実に行う。
      await updateSongLrcPath(state.currentSong!.id, lrcPath);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load lyrics: $e');
    }
  }

  Future<int> pickAndLoadFolder() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return 0;

      state = state.copyWith(isLoading: true);
      final List<Song> newSongs = [];
      
      // 拡張子でフィルタリング
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
          final fileName = p.basenameWithoutExtension(file.path!);
          
          if (['.mp3', '.m4a', '.flac', '.wav', '.aac'].contains(extension)) {
            if (!groupedFiles.containsKey(fileName)) {
              groupedFiles[fileName] = [];
            }
            groupedFiles[fileName]!.add(file);
          } else if (extension == '.lrc') {
            if (!groupedFiles.containsKey(fileName)) {
              groupedFiles[fileName] = [];
            }
            groupedFiles[fileName]!.add(file);
          }
        }
      }
      
      for (final entry in groupedFiles.entries) {
        final files = entry.value;
        PlatformFile? audioFile;
        PlatformFile? lrcFile;
        
        for (final file in files) {
          final extension = p.extension(file.path!).toLowerCase();
          if (['.mp3', '.m4a', '.flac', '.wav', '.aac'].contains(extension)) {
            audioFile = file;
          } else if (extension == '.lrc') {
            lrcFile = file;
          }
        }
        
        if (audioFile != null && audioFile.path != null) {
          // ★ Fix 1適用: コピー先フルパスでメタデータ抽出・アートワーク抽出
          final audioFileName = await _copyFileToLocalDirectory(audioFile.path!);
          final audioFullPath = await _getFullPath(audioFileName);
          
          var song = await _createSongFromMetadata(audioFullPath);
          
          final albumArt = await _extractAlbumArt(audioFullPath);
          if (albumArt != null) song = song.copyWithAlbumArt(albumArt);
          
          if (lrcFile != null && lrcFile.path != null) {
            // ★ Fix 1適用: LRCもバイナリコピーしてローカルに保存
            final lrcFileName = await _copyFileToLocalDirectory(lrcFile.path!);
            final lrcFullPath = await _getFullPath(lrcFileName);
            final lyrics = await _parseLrcFile(lrcFullPath);
            song = song.copyWith(
              lrcPath: lrcFileName, // ★ Fix 2: コピー済みファイル名のみを設定
              lyrics: lyrics,
            );
          }
          
          // ★ Fix 2: DB保存直前に絶対パスを物理ブロック — ファイル名のみに強制クレンジング
          song = song.copyWith(
            filePath: song.filePath.split('/').last,
            lrcPath: song.lrcPath != null ? song.lrcPath!.split('/').last : null,
          );
          await _dbHelper.insertOrUpdateSong(song);
          newSongs.add(song);
        }
      }

      final previousLength = state.playlist.length;
      final allSongs = [...state.playlist, ...newSongs];
      state = state.copyWith(playlist: allSongs);

      if (_player.audioSource == null) {
        // ★ Bug Fix: map() は async 非対応なので for ループで _getFullPath を使う
        final audioSources = <AudioSource>[];
        for (final song in allSongs) {
          final fullPath = await _getFullPath(song.filePath);
          if (Platform.isAndroid || Platform.isIOS) {
            String? artUri;
            if (song.albumArt != null) {
              artUri = Uri.dataFromBytes(song.albumArt!).toString();
            }
            audioSources.add(AudioSource.uri(
              Uri.file(fullPath),
              tag: MediaItem(
                id: song.id,
                title: song.title,
                artist: song.artist,
                artUri: artUri != null ? Uri.parse(artUri) : null,
              ),
            ));
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
      
      return newSongs.length;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load files: $e');
      return 0;
    } finally {
      state = state.copyWith(isLoading: false);
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
      if (state.repeatMode == PlaylistMode.all) {
        nextIndex = 0; 
      } else {
        return; 
      }
    }
    
    await playSongAtIndex(nextIndex);
  }

  Future<void> playPrevious() async {
    if (state.playlist.isEmpty) return;
    
    int prevIndex = state.currentSongIndex - 1;
    if (prevIndex < 0) {
      if (state.repeatMode == PlaylistMode.all) {
        prevIndex = state.playlist.length - 1; 
      } else {
        return; 
      }
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
        if (song.id == songId) {
          return song.copyWithFavorite(!song.isFavorite);
        }
        return song;
      }).toList();
      
      state = state.copyWith(playlist: updatedPlaylist);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to toggle favorite: $e',
      );
    }
  }

  Future<List<Song>> searchSongs(String query) async {
    try {
      return await _dbHelper.searchSongs(query);
    } catch (e) {
      return [];
    }
  }

  Future<List<Song>> getFavoriteSongs() async {
    try {
      return await _dbHelper.getFavoriteSongs();
    } catch (e) {
      return [];
    }
  }

  Future<void> removeSong(String songId) async {
    try {
      final songIndex = state.playlist.indexWhere((song) => song.id == songId);
      if (songIndex == -1) {
        return;
      }

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

      state = state.copyWith(
        playlist: updatedPlaylist,
        currentSongIndex: newCurrentIndex,
      );

    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to remove song: $e',
      );
    }
  }

  Future<void> toggleRepeat() async {
    PlaylistMode newMode;
    switch (state.repeatMode) {
      case PlaylistMode.off:
        newMode = PlaylistMode.one;
        break;
      case PlaylistMode.one:
        newMode = PlaylistMode.all;
        break;
      case PlaylistMode.all:
        newMode = PlaylistMode.off;
        break;
    }
    
    state = state.copyWith(repeatMode: newMode);
    
    LoopMode loopMode;
    switch (newMode) {
      case PlaylistMode.off:
        loopMode = LoopMode.off;
        break;
      case PlaylistMode.one:
        loopMode = LoopMode.one;
        break;
      case PlaylistMode.all:
        loopMode = LoopMode.all;
        break;
    }
    
    await _player.setLoopMode(loopMode);
  }

  Future<void> loadSong(Song song) async {
    await _loadSong(song);
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> play() async {
    await _player.play();
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
  }

  Future<void> createPlaylist(String name) async {
    try {
      final playlistId = await _dbHelper.createPlaylist(name);
      final updatedPlaylists = [...state.playlists, {'id': playlistId, 'name': name}];
      state = state.copyWith(playlists: updatedPlaylists);
      
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to create playlist: $e',
      );
    }
  }

  Future<void> addSongToPlaylist(String songId, String playlistId) async {
    try {
      await _dbHelper.addSongToPlaylist(playlistId, songId);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to add song to playlist: $e',
      );
    }
  }

  Future<void> loadPlaylists() async {
    try {
      final playlists = await _dbHelper.getAllPlaylists();
      state = state.copyWith(playlists: playlists);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to load playlists: $e',
      );
    }
  }

  Future<void> _loadPlaylist(List<Song> playlist, int startIndex) async {
    try {
      state = state.copyWith(isLoading: true, clearError: true);

      final List<AudioSource> audioSources = [];
      
      for (final song in playlist) {
        // ★ Bug Fix: 旧実装は song.filePath（ファイル名のみ）を直接渡していた。
        //   _getFullPath で絶対パスに変換してから AudioSource を生成する。
        final fullPath = await _getFullPath(song.filePath);
        final audioSource = (Platform.isAndroid || Platform.isIOS)
            ? AudioSource.uri(
                Uri.file(fullPath),
                tag: MediaItem(
                  id: song.id,
                  title: song.title,
                  artist: song.artist,
                ),
              )
            : LocalFileStreamAudioSource(fullPath);
        
        audioSources.add(audioSource);
      }

      final concatenatingSource = ConcatenatingAudioSource(
        useLazyPreparation: true,
        shuffleOrder: state.isShuffleModeEnabled ? DefaultShuffleOrder() : null,
        children: audioSources,
      );

      await _player.setAudioSource(concatenatingSource, initialPosition: Duration.zero, preload: false);
      
      if (startIndex > 0) {
        await _player.seek(Duration.zero, index: startIndex);
      }

      await _player.play();
      
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load playlist: $e',
      );
    }
  }

  Future<void> _loadSong(Song song) async {
    await _loadPlaylist([song], 0);
  }

  int _getCurrentLyricIndex(List<LyricLine> lyrics, Duration position) {
    if (lyrics.isEmpty) return -1;

    // lyricOffset 
    final offsetMs = state.currentSong?.lyricOffset ?? 0;
    final adjustedPosition = Duration(
      milliseconds: (position.inMilliseconds + offsetMs).clamp(0, double.maxFinite.toInt()),
    );

    int index = -1;
    for (int i = 0; i < lyrics.length; i++) {
      if (lyrics[i].position <= adjustedPosition) {
        index = i;
      } else {
        break; 
      }
    }
    return index;
  }

  
  Future<void> updateSongLrcPath(String songId, String lrcPath) async {
    try {
      // Copy LRC file to local directory first
      final lrcFileName = await _copyFileToLocalDirectory(lrcPath);
      final fullLrcPath = await _getFullPath(lrcFileName);
      
      // Use absolute path for parsing lyrics
      final lyrics = await _parseLrcFile(fullLrcPath);
      
      // Save only filename to database
      await _dbHelper.updateSongLrcPath(songId, lrcFileName);
      
      final updatedPlaylist = state.playlist.map<Song>((song) {
        if (song.id == songId) {
          return song.copyWith(
            lrcPath: lrcFileName, // Ensure only filename is saved
            lyrics: lyrics,
          );
        }
        return song;
      }).toList();
      
      state = state.copyWith(playlist: updatedPlaylist);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to update LRC path: $e',
      );
    }
  }

  /// 
  Future<void> updateLyricOffset(String songId, int deltaMs) async {
    try {
      final songIndex = state.playlist.indexWhere((s) => s.id == songId);
      if (songIndex == -1) return;

      final currentOffset = state.playlist[songIndex].lyricOffset;
      final newOffset = currentOffset + deltaMs;

      // DB 
      await _dbHelper.updateLyricOffset(songId, newOffset);

      // state 
      final updatedPlaylist = List<Song>.from(state.playlist);
      updatedPlaylist[songIndex] =
          updatedPlaylist[songIndex].copyWith(lyricOffset: newOffset);

      state = state.copyWith(playlist: updatedPlaylist);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update lyric offset: $e');
    }
  }

  Future<List<LyricLine>> _parseLrcFile(String lrcPath) async {
    try {
      final file = File(lrcPath);
      if (!await file.exists()) {
        return [];
      }
      
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
          
          lyrics.add(LyricLine(
            position: Duration(
              minutes: minutes,
              seconds: seconds,
              milliseconds: milliseconds,
            ),
            text: text,
          ));
        }
      }
      
      return lyrics;
    } catch (e) {
      return [];
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _currentIndexSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }
}

final audioPlayerProvider =
    StateNotifierProvider<AudioPlayerNotifier, AudioPlayerState>(
  (ref) => AudioPlayerNotifier(),
);