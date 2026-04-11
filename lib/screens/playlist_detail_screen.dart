// ============================================================
// screens/playlist_detail_screen.dart
// プレイリスト詳細画面
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../models/song.dart';
import '../utils/database_helper.dart';
import '../providers/audio_player_provider.dart';
import 'now_playing_screen.dart';
import '../theme/app_theme.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> playlist;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
  });

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  late Future<List<Song>> _playlistSongsFuture;

  @override
  void initState() {
    super.initState();
    _loadPlaylistSongs();
  }

  void _loadPlaylistSongs() {
    setState(() {
      _playlistSongsFuture = _dbHelper.getPlaylistSongs(widget.playlist['id']);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.playlist['name'] as String? ?? 'Untitled Playlist',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Song>>(
        future: _playlistSongsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.textDisabled,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading playlist',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error.toString(),
                    style: TextStyle(
                      color: Colors.red.withOpacity(0.7),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final songs = snapshot.data ?? [];

          if (songs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.playlist_play,
                    size: 64,
                    color: AppColors.textDisabled,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'このプレイリストは空です',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '曲を追加して楽しもう',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Spotify-style header
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Artwork and play button
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        // Large artwork
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: songs.first.albumArt != null
                                ? Image.memory(
                                    songs.first.albumArt!,
                                    width: 200,
                                    height: 200,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: AppColors.surface,
                                    child: const Icon(
                                      Icons.music_note_rounded,
                                      size: 80,
                                      color: AppColors.textDisabled,
                                    ),
                                  ),
                          ),
                        ),
                        // Play button overlay
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.play_arrow,
                                color: Colors.black,
                                size: 28,
                              ),
                              onPressed: () async {
                                final playerState = ref.read(audioPlayerProvider);
                                final notifier = ref.read(audioPlayerProvider.notifier);
                                final originalIndex = playerState.playlist.indexWhere((s) => s.id == songs.first.id);
                                if (originalIndex != -1) {
                                  await notifier.playSongAtIndex(originalIndex);
                                  if (mounted) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
                                    );
                                  }
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Playlist name
                    Text(
                      widget.playlist['name'] as String? ?? 'Untitled Playlist',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Song list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final rawSong = songs[index]; // ✅ 修正: 変数名を rawSong に変更
                    final allSongs = ref.watch(audioPlayerProvider).playlist;
                    final song = allSongs.firstWhere((s) => s.id == rawSong.id, orElse: () => rawSong); // ✅ rawSong を参照
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: SizedBox(
                        width: 56,
                        height: 56,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: song.albumArt != null
                              ? Image.memory(
                                  song.albumArt!,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _buildDefaultIcon();
                                  },
                                )
                              : _buildDefaultIcon(),
                        ),
                      ),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                song.artist,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (song.lyrics.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.lyrics_rounded,
                                  size: 14,
                                  color: AppColors.accent,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Checkmark
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.accent,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          // Lyrics button
                          IconButton(
                            icon: const Icon(
                              Icons.lyrics_rounded,
                              color: AppColors.accent,
                              size: 24,
                            ),
                            onPressed: () => _pickAndAttachLrcFile(song),
                            tooltip: '歌詞ファイルを登録',
                          ),
                          const SizedBox(width: 8),
                          // Delete button
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.red,
                              size: 24,
                            ),
                            onPressed: () async {
                              // Confirm removal
                              final confirmed = await _showRemoveConfirmation(context, song);
                              if (confirmed == true) {
                                await _dbHelper.removeSongFromPlaylist(song.id, widget.playlist['id']);
                                _loadPlaylistSongs(); // Refresh list
                              }
                            },
                            tooltip: 'プレイリストから削除',
                          ),
                        ],
                      ),
                      onTap: () async {
                        final playerState = ref.read(audioPlayerProvider);
                        final notifier = ref.read(audioPlayerProvider.notifier);
                        final originalIndex = playerState.playlist.indexWhere((s) => s.id == song.id);
                        if (originalIndex != -1) {
                          await notifier.playSongAtIndex(originalIndex);
                          if (mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
                            );
                          }
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDefaultIcon() {
    return const Icon(
      Icons.music_note_rounded,
      color: AppColors.textDisabled,
      size: 28,
    );
  }

  Future<bool?> _showRemoveConfirmation(BuildContext context, Song song) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'プレイリストから削除',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          '${song.title} をプレイリストから削除してもよろしいですか？',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'キャンセル',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '削除',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  /// Pick and attach LRC file to song
  Future<void> _pickAndAttachLrcFile(Song song) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lrc'],
        dialogTitle: '歌詞ファイルを選択',
      );

      if (result != null && result.files.isNotEmpty) {
        final lrcPath = result.files.first.path;
        if (lrcPath != null) {
          final notifier = ref.read(audioPlayerProvider.notifier);
          await notifier.updateSongLrcPath(song.id, lrcPath);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('歌詞ファイルを登録しました'),
                backgroundColor: AppColors.accent,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('歌詞ファイルの登録に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}