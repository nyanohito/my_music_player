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
import 'package:metadata_god/metadata_god.dart'; // ✅ audiotags から変更
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
  final bool isEqualizerEnabled;
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
  
  final DatabaseHelper _dbHelper = DatabaseHelper();

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<int?>? _currentIndexSubscription;

  dynamic _equalizer;

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
      
      if (savedSongs.isNotEmpty) {
        final songsWithArtwork = await Future.wait(savedSongs.map((song) async {
          final albumArt = await _extractAlbumArt(song.filePath);
          return albumArt != null ? song.copyWithAlbumArt(albumArt) : song;
        }));
        
        state = state.copyWith(
          playlist: songsWithArtwork,
          playlists: playlists,
        );
        
        final audioSources = songsWithArtwork.map((song) {
          if (Platform.isAndroid || Platform.isIOS) {
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
        await _player.setAudioSource(playlist, initialIndex: 0);
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
      final lyricIndex = _getCurrentLyricIndex(
        state.currentSong?.lyrics ?? [],
        position,
      );
      state = state.copyWith(
        position: position,
        currentLyricIndex: lyricIndex,
      );
    });

    _durationSubscription = _player.durationStream.listen((duration) {
      if (duration != null) {
        state = state.copyWith(duration: duration);
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

  // ✅ metadata_god に合わせた情報抽出ロジック
  Future<Song> _createSongFromMetadata(String filePath) async {
    try {
      final metadata = await MetadataGod.readMetadata(file: filePath);
      
      final String title = p.basenameWithoutExtension(filePath);
      final String artist = metadata.artist ?? 'Unknown Artist';

      return Song(
        id: const Uuid().v4(),
        title: title,
        artist: artist,
        filePath: filePath,
      );
    } catch (e) {
      return Song.fromPath(filePath);
    }
  }

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
        
        final albumArt = await _extractAlbumArt(file.path!);
        if (albumArt != null) song = song.copyWithAlbumArt(albumArt);
        
        await _dbHelper.insertOrUpdateSong(song);
        newSongs.add(song);
      }

      final previousLength = state.playlist.length;
      final allSongs = [...state.playlist, ...newSongs];
      state = state.copyWith(playlist: allSongs);

      if (_player.audioSource == null) {
        final audioSources = allSongs.map((song) {
          return (Platform.isAndroid || Platform.isIOS)
              ? AudioSource.uri(Uri.file(song.filePath), tag: MediaItem(id: song.id, title: song.title, artist: song.artist))
              : LocalFileStreamAudioSource(song.filePath);
        }).toList();
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
    final newAudioSources = newSongs.map((song) {
      return (Platform.isAndroid || Platform.isIOS)
          ? AudioSource.uri(Uri.file(song.filePath), tag: MediaItem(id: song.id, title: song.title, artist: song.artist))
          : LocalFileStreamAudioSource(song.filePath);
    }).toList();

    final playlist = _player.audioSource as ConcatenatingAudioSource;
    await playlist.addAll(newAudioSources);
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

      final lrcContent = await File(lrcPath).readAsString();
      final lyrics = LrcParser.parse(lrcContent);

      final currentSong = state.currentSong!;
      final updatedSong = currentSong.copyWithLyrics(
        lrcPath: lrcPath,
        lyrics: lyrics,
      );

      final updatedPlaylist = List<Song>.from(state.playlist);
      updatedPlaylist[state.currentSongIndex] = updatedSong;

      state = state.copyWith(
        playlist: updatedPlaylist,
        currentLyricIndex: -1, 
      );
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to load lyrics: $e',
      );
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
        final audioSource = (Platform.isAndroid || Platform.isIOS)
            ? AudioSource.uri(
                Uri.file(song.filePath),
                tag: MediaItem(
                  id: song.id,
                  title: song.title,
                  artist: song.artist,
                ),
              )
            : LocalFileStreamAudioSource(song.filePath); 
        
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

    int index = -1;
    for (int i = 0; i < lyrics.length; i++) {
      if (lyrics[i].position <= position) {
        index = i;
      } else {
        break; 
      }
    }
    return index;
  }

  Future<void> toggleEqualizer() async {
    if (Platform.isWindows) {
      state = state.copyWith(
        errorMessage: 'Equalizer is not supported on Windows',
      );
      return;
    }

    try {
      final newEnabledState = !state.isEqualizerEnabled;
      state = state.copyWith(isEqualizerEnabled: newEnabledState);
      
      if (newEnabledState) {
        await _initEqualizer();
      }
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to toggle equalizer: $e',
      );
    }
  }

  Future<void> setEqualizerGain(int bandIndex, double gain) async {
    if (Platform.isWindows) {
      return;
    }

    try {
      final newGains = List<double>.from(state.equalizerGains);
      if (bandIndex >= 0 && bandIndex < newGains.length) {
        newGains[bandIndex] = gain;
        state = state.copyWith(equalizerGains: newGains);
        
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

  Future<void> _initEqualizer() async {
    if (Platform.isWindows) return;
    try {
      _equalizer = {}; 
      await _applyEqualizerSettings();
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to initialize equalizer: $e',
      );
    }
  }

  Future<void> _applyEqualizerSettings() async {
    if (Platform.isWindows || _equalizer == null) return;
  }

  Future<void> updateSongLrcPath(String songId, String lrcPath) async {
    try {
      await _dbHelper.updateSongLrcPath(songId, lrcPath);
      final lyrics = await _parseLrcFile(lrcPath);
      
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