// ============================================================
// providers/audio_player_provider.dart
// ★ アプリの心臓部：音楽再生の全状態とロジックを管理する
// ============================================================
//
// 【Riverpodの基本パターン（初心者向け解説）】
//
//   StateNotifier<State>  = 状態(State)を変更できるクラス
//   StateNotifierProvider = StateNotifier を Widget から使えるようにする橋渡し
//
//   Widget から使うときは:
//     ref.watch(audioPlayerProvider)        → 状態を読む（変化で再描画）
//     ref.read(audioPlayerProvider.notifier) → メソッドを呼ぶ（再描画なし）

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
import 'package:audiotags/audiotags.dart';
import 'package:uuid/uuid.dart';

import '../models/lyric_line.dart';
import '../models/song.dart';
import '../utils/lrc_parser.dart';
import '../utils/database_helper.dart';

// Playlist modes for repeat functionality
enum PlaylistMode { off, one, all }

// ============================================================
// Custom StreamAudioSource for Windows compatibility
// ============================================================
/// Custom audio source that reads file bytes directly to avoid Windows native path issues
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
      contentType: 'audio/mpeg', // Works for most formats including FLAC, M4A
    );
  }
}

// ─────────────────────────────────────────────
// 状態クラス：プレイヤーのすべての状態をまとめて管理
// ─────────────────────────────────────────────

/// AudioPlayer Playlist state for UI
class AudioPlayerState {
  /// Playlist of all songs
  final List<Song> playlist;

  /// Current song index in playlist
  final int currentSongIndex;

  /// Whether currently playing
  final bool isPlaying;

  /// Current playback position
  final Duration position;

  /// Total duration of current song
  final Duration duration;

  /// Current lyric line index to highlight (-1 means no lyrics)
  final int currentLyricIndex;

  /// Whether currently loading
  final bool isLoading;

  /// Error message (null means normal)
  final String? errorMessage;

  /// Shuffle mode enabled
  final bool isShuffleModeEnabled;

  /// Repeat mode (off, one, all)
  final PlaylistMode repeatMode;

  /// User playlists
  final List<Map<String, dynamic>> playlists;

  /// Equalizer enabled
  final bool isEqualizerEnabled;

  /// Equalizer band gains (5 bands: 60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz)
  final List<double> equalizerGains;

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
    this.isEqualizerEnabled = false,
    this.equalizerGains = const [0.0, 0.0, 0.0, 0.0, 0.0],
  });

  /// Create new state with specific fields updated (immutable update)
  AudioPlayerState copyWith({
    List<Song>? playlist,
    int? currentSongIndex,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    int? currentLyricIndex,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,  // Set to true to clear error
    bool? isShuffleModeEnabled,
    PlaylistMode? repeatMode,
    List<Map<String, dynamic>>? playlists,
    bool? isEqualizerEnabled,
    List<double>? equalizerGains,
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
      isEqualizerEnabled: isEqualizerEnabled ?? this.isEqualizerEnabled,
      equalizerGains: equalizerGains ?? this.equalizerGains,
    );
  }

  /// Get current song (null if no songs or invalid index)
  Song? get currentSong {
    if (currentSongIndex >= 0 && currentSongIndex < playlist.length) {
      return playlist[currentSongIndex];
    }
    return null;
  }

  /// Whether playlist has songs
  bool get hasSongs => playlist.isNotEmpty;

  /// Whether currently has a valid current song
  bool get hasCurrentSong => currentSong != null;
}

// ─────────────────────────────────────────────
// StateNotifier：状態を変更するロジックをここに書く
// ─────────────────────────────────────────────

class AudioPlayerNotifier extends StateNotifier<AudioPlayerState> {
  // just_audio のプレイヤーインスタンス（内部でのみ使用）
  final AudioPlayer _player = AudioPlayer();

  /// Expose position stream for progress bar
  Stream<Duration> get positionStream => _player.positionStream;

  /// Expose volume stream for volume control
  Stream<double> get volumeStream => _player.volumeStream;

  /// Set volume for audio player
  void setVolume(double value) => _player.setVolume(value);
  
  // Database helper instance
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Stream subscriptions for cleanup (prevent memory leaks)
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<int?>? _currentIndexSubscription;

  // Equalizer instance (platform-specific)
  dynamic _equalizer;

  // 外部からプレイヤーインスタンスにアクセスするためのゲッター
  AudioPlayer get player => _player;

  AudioPlayerNotifier() : super(const AudioPlayerState()) {
    _initAudioSession();
    _subscribeToPlayerStreams();
    _loadSavedSongs();
  }

  // ─────────────────────────────────────
  // 初期化
  // ─────────────────────────────────────

  /// Load saved songs from database on startup
  Future<void> _loadSavedSongs() async {
    try {
      // Load both songs and playlists
      final savedSongs = await _dbHelper.getAllSongs();
      final playlists = await _dbHelper.getAllPlaylists();
      
      if (savedSongs.isNotEmpty) {
        // Extract album artwork for each song asynchronously
        final songsWithArtwork = await Future.wait(savedSongs.map((song) async {
          final albumArt = await _extractAlbumArt(song.filePath);
          return albumArt != null ? song.copyWithAlbumArt(albumArt) : song;
        }));
        
        state = state.copyWith(
          playlist: songsWithArtwork,
          playlists: playlists,
        );
        
        // Initialize audio engine with loaded songs (critical fix)
        final audioSources = songsWithArtwork.map((song) {
          if (Platform.isAndroid || Platform.isIOS) {
            // Create artUri if album art is available
            String? artUri;
            if (song.albumArt != null) {
              artUri = Uri.dataFromBytes(song.albumArt!).toString();
            }
            
            return AudioSource.uri(
              Uri.file(song.filePath), 
              tag: MediaItem(
                id: song.id, 
                title: song.title, 
                artist: song.artist,
                artUri: artUri != null ? Uri.parse(artUri) : null,
              ),
            );
          } else {
            return LocalFileStreamAudioSource(song.filePath);
          }
        }).toList();
        final playlist = ConcatenatingAudioSource(children: audioSources);
        // Don't auto-play on startup, just initialize the audio source
        await _player.setAudioSource(playlist, initialIndex: 0);
      }
    } catch (e) {
      // If database loading fails, continue with empty playlist
      print('Failed to load saved songs: $e');
    }
  }

  /// オーディオセッションを設定する
  /// → iOS で他のアプリの音楽を止めて再生、Bluetooth対応
  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  /// Subscribe to player streams and update state
  void _subscribeToPlayerStreams() {
    // Listen to position changes and update state
    _positionSubscription = _player.positionStream.listen((position) {
      final lyricIndex = _getCurrentLyricIndex(
        state.currentSong?.lyrics ?? [],
        position,
      );
      state = state.copyWith(
        position: position,
        currentLyricIndex: lyricIndex,
      );
    });

    // Listen to duration changes and update state
    _durationSubscription = _player.durationStream.listen((duration) {
      if (duration != null) {
        state = state.copyWith(duration: duration);
      }
    });

    // Listen to player state changes (play/pause/complete)
    _playerStateSubscription = _player.playerStateStream.listen((playerState) {
      state = state.copyWith(
        isPlaying: playerState.playing,
        isLoading: playerState.processingState == ProcessingState.loading ||
            playerState.processingState == ProcessingState.buffering,
      );
    });

    // Listen to current index changes and record play history
    _currentIndexSubscription = _player.currentIndexStream.listen((index) {
      if (index != null && state.currentSongIndex != index) {
        final song = state.playlist[index!];
        if (song != null) {
          DatabaseHelper().addPlayHistory(song.id);
        }
      }
      
      // Update UI state
      if (index != null && index >= 0 && index < state.playlist.length) {
        state = state.copyWith(
          currentSongIndex: index,
        );
      }
    });
  }

  // ------------------------------------------------
  // Helper methods for metadata extraction
  // ------------------------------------------------

  /// Extract album artwork from audio file using audiotags
  Future<Uint8List?> _extractAlbumArt(String filePath) async {
    try {
      final tags = await AudioTags.read(filePath);
      // audiotags uses 'pictures' property for artwork
      // Add null safety check for tags
      if (tags != null && tags.pictures.isNotEmpty) {
        return tags.pictures.first.bytes;
      }
      return null;
    } catch (e) {
      // If metadata extraction fails, return null and continue
      // This is common for files without embedded artwork
      return null;
    }
  }

  /// Create Song object with metadata extracted from ID3 tags
  Future<Song> _createSongFromMetadata(String filePath) async {
    try {
      final tags = await AudioTags.read(filePath);
      
      // Always use filename for title (to preserve Japanese filenames)
      final String title = p.basenameWithoutExtension(filePath);

      // Extract artist from metadata, fallback to 'Unknown Artist'
      final String artist = (tags != null && tags.artist != null && tags.artist!.isNotEmpty)
          ? tags.artist!
          : 'Unknown Artist';

      return Song(
        id: const Uuid().v4(),
        title: title,
        artist: artist,
        filePath: filePath,
      );
    } catch (e) {
      // If metadata extraction fails, fallback to filename-based creation
      return Song.fromPath(filePath);
    }
  }

  // ------------------------------------------------
  // Public methods (called by Widgets)
  // ------------------------------------------------─────────────────────────────────────

  /// Open file picker to select music files and add them to playlist
  Future<void> pickAndLoadSong() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'flac', 'm4a', 'wav', 'aac'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      state = state.copyWith(isLoading: true);
      final List<Song> newSongs = [];

      for (final file in result.files) {
        if (file.path == null) continue;
        var song = await _createSongFromMetadata(file.path!);
        
        // Extract artwork
        final albumArt = await _extractAlbumArt(file.path!);
        if (albumArt != null) song = song.copyWithAlbumArt(albumArt);
        
        // Save to database
        await _dbHelper.insertOrUpdateSong(song);
        newSongs.add(song);
      }

      final previousLength = state.playlist.length;
      final allSongs = [...state.playlist, ...newSongs];
      state = state.copyWith(playlist: allSongs);

      if (_player.audioSource == null) {
        // Engine is empty - reconstruct entire playlist and set it
        final audioSources = allSongs.map((song) {
          return (Platform.isAndroid || Platform.isIOS)
              ? AudioSource.uri(Uri.file(song.filePath), tag: MediaItem(id: song.id, title: song.title, artist: song.artist))
              : LocalFileStreamAudioSource(song.filePath);
        }).toList();
        final playlist = ConcatenatingAudioSource(children: audioSources);
        await _player.setAudioSource(playlist, initialIndex: previousLength);
        _player.play(); // Start playback from first added song
      } else {
        // Engine already exists - append only new songs
        await _appendSongsToCurrentPlaylist(newSongs);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load songs: $e');
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  
  /// Append new songs to existing ConcatenatingAudioSource without interrupting playback
  Future<void> _appendSongsToCurrentPlaylist(List<Song> newSongs) async {
    final newAudioSources = newSongs.map((song) {
      return (Platform.isAndroid || Platform.isIOS)
          ? AudioSource.uri(Uri.file(song.filePath), tag: MediaItem(id: song.id, title: song.title, artist: song.artist))
          : LocalFileStreamAudioSource(song.filePath);
    }).toList();

    final playlist = _player.audioSource as ConcatenatingAudioSource;
    await playlist.addAll(newAudioSources);
  }

  /// Select LRC file and attach it to current song
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

      // Read and parse LRC file
      final lrcContent = await File(lrcPath).readAsString();
      final lyrics = LrcParser.parse(lrcContent);

      // Update current song with lyrics
      final currentSong = state.currentSong!;
      final updatedSong = currentSong.copyWithLyrics(
        lrcPath: lrcPath,
        lyrics: lyrics,
      );

      // Update playlist with the song that has lyrics
      final updatedPlaylist = List<Song>.from(state.playlist);
      updatedPlaylist[state.currentSongIndex] = updatedSong;

      state = state.copyWith(
        playlist: updatedPlaylist,
        currentLyricIndex: -1, // Reset lyric index when new lyrics are loaded
      );
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to load lyrics: $e',
      );
    }
  }

  /// Play song at specific index in playlist
  Future<void> playSongAtIndex(int index) async {
    if (index < 0 || index >= state.playlist.length) return;
    
    state = state.copyWith(currentSongIndex: index);
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  /// Play next song
  Future<void> playNext() async {
    if (state.playlist.isEmpty) return;
    
    int nextIndex = state.currentSongIndex + 1;
    if (nextIndex >= state.playlist.length) {
      if (state.repeatMode == PlaylistMode.all) {
        nextIndex = 0; // Loop back to first song
      } else {
        return; // Stop at end if not repeating all
      }
    }
    
    await playSongAtIndex(nextIndex);
  }

  /// Play previous song
  Future<void> playPrevious() async {
    if (state.playlist.isEmpty) return;
    
    int prevIndex = state.currentSongIndex - 1;
    if (prevIndex < 0) {
      if (state.repeatMode == PlaylistMode.all) {
        prevIndex = state.playlist.length - 1; // Loop to last song
      } else {
        return; // Stop at beginning if not repeating all
      }
    }
    
    await playSongAtIndex(prevIndex);
  }

  /// Toggle shuffle mode
  Future<void> toggleShuffle() async {
    final newShuffleState = !state.isShuffleModeEnabled;
    state = state.copyWith(isShuffleModeEnabled: newShuffleState);
    
    // Update player shuffle mode
    await _player.setShuffleModeEnabled(newShuffleState);
  }

  /// Toggle favorite status for a song
  Future<void> toggleFavorite(String songId) async {
    try {
      // Update database
      await _dbHelper.toggleFavorite(songId);
      
      // Update local state
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

  /// Search songs by query
  Future<List<Song>> searchSongs(String query) async {
    try {
      return await _dbHelper.searchSongs(query);
    } catch (e) {
      print('Failed to search songs: $e');
      return [];
    }
  }

  /// Get favorite songs
  Future<List<Song>> getFavoriteSongs() async {
    try {
      return await _dbHelper.getFavoriteSongs();
    } catch (e) {
      print('Failed to get favorite songs: $e');
      return [];
    }
  }

  /// Remove song from playlist, audio engine, and database
  Future<void> removeSong(String songId) async {
    try {
      // Find the song index in current playlist
      final songIndex = state.playlist.indexWhere((song) => song.id == songId);
      if (songIndex == -1) {
        print('Song not found in playlist: $songId');
        return;
      }

      // Remove from audio engine if it has a source loaded
      if (_player.audioSource != null) {
        final concatenatingSource = _player.audioSource as ConcatenatingAudioSource;
        await concatenatingSource.removeAt(songIndex);
      }

      // Remove from database
      await _dbHelper.deleteSong(songId);

      // Update local state
      final updatedPlaylist = List<Song>.from(state.playlist)..removeAt(songIndex);
      
      // Adjust current song index if needed
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

  /// Toggle repeat mode (off -> one -> all -> off)
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
    
    // Update player loop mode
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

  /// 既存の Song オブジェクトをロードして再生する
  /// （ライブラリ画面からタップして再生するときに使う）
  Future<void> loadSong(Song song) async {
    await _loadSong(song);
  }

  /// 再生 / 一時停止 トグル
  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  /// 再生
  Future<void> play() async {
    await _player.play();
  }

  /// 一時停止
  Future<void> pause() async {
    await _player.pause();
  }

  /// 指定した時刻にシーク（スライダー操作時など）
  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
  }

  /// Create a new playlist
  Future<void> createPlaylist(String name) async {
    try {
      final playlistId = await _dbHelper.createPlaylist(name);
      
      // Update state with new playlist
      final updatedPlaylists = [...state.playlists, {'id': playlistId, 'name': name}];
      state = state.copyWith(playlists: updatedPlaylists);
      
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to create playlist: $e',
      );
    }
  }

  /// Add song to playlist
  Future<void> addSongToPlaylist(String songId, String playlistId) async {
    try {
      await _dbHelper.addSongToPlaylist(playlistId, songId);
      
      // Optionally refresh playlist data if needed
      // For now, we'll just show success
      
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to add song to playlist: $e',
      );
    }
  }

  /// Load all playlists from database
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

  // ─────────────────────────────────────
  // プライベートヘルパー
  // ─────────────────────────────────────

  /// Load playlist with ConcatenatingAudioSource and start playback
  Future<void> _loadPlaylist(List<Song> playlist, int startIndex) async {
    try {
      state = state.copyWith(isLoading: true, clearError: true);

      // Create audio sources for each song in playlist
      final List<AudioSource> audioSources = [];
      
      for (final song in playlist) {
        // Create platform-specific AudioSource
        // Mobile: Use URI-based AudioSource with background support
        // Desktop: Use custom stream to avoid Windows native path issues (CRITICAL: Preserve this!)
        final audioSource = (Platform.isAndroid || Platform.isIOS)
            ? AudioSource.uri(
                Uri.file(song.filePath),
                tag: MediaItem(
                  id: song.id,
                  title: song.title,
                  artist: song.artist,
                  // artUri: ... <- Album artwork URI to be added later
                ),
              )
            : LocalFileStreamAudioSource(song.filePath); // CRITICAL: This prevents Windows crashes!
        
        audioSources.add(audioSource);
      }

      // Create ConcatenatingAudioSource for playlist
      final concatenatingSource = ConcatenatingAudioSource(
        useLazyPreparation: true,
        shuffleOrder: state.isShuffleModeEnabled ? DefaultShuffleOrder() : null,
        children: audioSources,
      );

      // Set the concatenated source and seek to start index
      await _player.setAudioSource(concatenatingSource, initialPosition: Duration.zero, preload: false);
      
      // Seek to the correct song index
      if (startIndex > 0) {
        await _player.seek(Duration.zero, index: startIndex);
      }

      // Start playback
      await _player.play();
      
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load playlist: $e',
      );
    }
  }

  /// 実際に AudioPlayer に曲をセットして再生開始する内部メソッド
  Future<void> _loadSong(Song song) async {
    await _loadPlaylist([song], 0);
  }

  /// 現在の再生位置に対応する歌詞のインデックスを計算する
  ///
  /// 「現在位置以下の最後のタイムスタンプ」の行が現在の歌詞
  int _getCurrentLyricIndex(List<LyricLine> lyrics, Duration position) {
    if (lyrics.isEmpty) return -1;

    int index = -1;
    for (int i = 0; i < lyrics.length; i++) {
      if (lyrics[i].position <= position) {
        index = i;
      } else {
        break; // ソート済みなので、超えたら以降はチェック不要
      }
    }
    return index;
  }

  /// Toggle equalizer
  Future<void> toggleEqualizer() async {
    if (Platform.isWindows) {
      // Windows: Skip equalizer functionality to prevent crashes
      state = state.copyWith(
        errorMessage: 'Equalizer is not supported on Windows',
      );
      return;
    }

    try {
      final newEnabledState = !state.isEqualizerEnabled;
      state = state.copyWith(isEqualizerEnabled: newEnabledState);
      
      // Initialize equalizer if enabling
      if (newEnabledState) {
        await _initEqualizer();
      }
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to toggle equalizer: $e',
      );
    }
  }

  /// Set equalizer band gain
  Future<void> setEqualizerGain(int bandIndex, double gain) async {
    if (Platform.isWindows) {
      return; // Skip on Windows
    }

    try {
      final newGains = List<double>.from(state.equalizerGains);
      if (bandIndex >= 0 && bandIndex < newGains.length) {
        newGains[bandIndex] = gain;
        state = state.copyWith(equalizerGains: newGains);
        
        // Apply gain to equalizer if enabled
        if (state.isEqualizerEnabled && _equalizer != null) {
          await _applyEqualizerSettings();
        }
      }
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to set equalizer gain: $e',
      );
    }
  }

  /// Initialize equalizer (platform-specific)
  Future<void> _initEqualizer() async {
    if (Platform.isWindows) {
      return; // Skip on Windows
    }

    try {
      // For Android: Use AndroidEqualizer
      // For iOS: Use IOSAudioContext (if available)
      // For now, we'll create a dummy implementation
      _equalizer = {}; // Placeholder for actual equalizer implementation
      
      // Apply current settings
      await _applyEqualizerSettings();
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to initialize equalizer: $e',
      );
    }
  }

  /// Apply equalizer settings to audio engine
  Future<void> _applyEqualizerSettings() async {
    if (Platform.isWindows || _equalizer == null) {
      return; // Skip on Windows or if not initialized
    }

    try {
      // Apply current gains to equalizer
      // This is a placeholder - actual implementation depends on platform
      // For Android: _equalizer.setBandLevel(bandIndex, gain)
      // For iOS: Use appropriate API
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to apply equalizer settings: $e',
      );
    }
  }

  /// Update song's LRC file path and lyrics data
  Future<void> updateSongLrcPath(String songId, String lrcPath) async {
    try {
      // Update database
      await _dbHelper.updateSongLrcPath(songId, lrcPath);
      
      // Parse LRC file
      final lyrics = await _parseLrcFile(lrcPath);
      
      // Update playlist in memory
      final updatedPlaylist = state.playlist.map<Song>((song) {
        if (song.id == songId) {
          return song.copyWith(
            lrcPath: lrcPath,
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

  /// Parse LRC file and return lyrics data
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
      print('Failed to parse LRC file: $e');
      return [];
    }
  }

  /// Widgetが破棄されたときにリソースを解放する
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

// ─────────────────────────────────────────────
// Provider 定義（Widget から参照するグローバルな「取っ手」）
// ─────────────────────────────────────────────

/// AudioPlayer の状態と操作にアクセスするための Provider
///
/// 【使い方例（Widget内）】
///
///   // 状態を読む（変化があると Widget が再描画される）
///   final playerState = ref.watch(audioPlayerProvider);
///   Text(playerState.currentSong?.title ?? '曲を選んでください')
///
///   // メソッドを呼ぶ（再描画は不要な操作）
///   ref.read(audioPlayerProvider.notifier).togglePlayPause();
final audioPlayerProvider =
    StateNotifierProvider<AudioPlayerNotifier, AudioPlayerState>(
  (ref) => AudioPlayerNotifier(),
);
