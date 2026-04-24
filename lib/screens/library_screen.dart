// ============================================================
// screens/library_screen.dart
// ライブラリ画面（Spotify風UI + プレイリスト機能）
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/audio_player_provider.dart';
import 'now_playing_screen.dart';
import 'playlist_detail_screen.dart';
import 'play_history_screen.dart';
import '../theme/app_theme.dart';
import '../models/song.dart';
import '../utils/database_helper.dart';
import '../widgets/mini_player_with_progress.dart';
import '../widgets/playlist_selection_dialog.dart';

enum FilterMode { all, favorites, playlists }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _searchQuery = '';
  FilterMode _filterMode = FilterMode.all;

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(audioPlayerProvider);
    final notifier = ref.read(audioPlayerProvider.notifier);
    final playlist = playerState.playlist;
    final currentSongIndex = playerState.currentSongIndex;

    // 
    ref.listen<AudioPlayerState>(audioPlayerProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });

    List<Song> displaySongs = [];
    if (_filterMode != FilterMode.playlists) {
      displaySongs = playlist.where((song) {
        if (_filterMode == FilterMode.favorites && !song.isFavorite) return false;
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          return song.title.toLowerCase().contains(query) ||
                 song.artist.toLowerCase().contains(query);
        }
        return true;
      }).toList();
      
      // タイトル名でソート（A-Z/あいうえお順）
      displaySongs.sort((a, b) => a.title.compareTo(b.title));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'My Library',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            color: AppColors.textSecondary,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlayHistoryScreen()),
              );
            },
            tooltip: 'Play History',
          ),
          IconButton(
            icon: const Icon(Icons.lyrics_rounded),
            color: AppColors.textSecondary,
            onPressed: () async {
              await notifier.pickAndLoadLrc();
            },
            tooltip: 'Add Lyrics',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: '何を探していますか？',
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                hintStyle: const TextStyle(color: AppColors.textSecondary),
              ),
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),

          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('すべて'),
                  selected: _filterMode == FilterMode.all,
                  onSelected: (selected) {
                    if (selected) setState(() => _filterMode = FilterMode.all);
                  },
                  backgroundColor: Colors.transparent,
                  selectedColor: const Color(0xFF1DB954),
                  labelStyle: TextStyle(
                    color: _filterMode == FilterMode.all ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: const StadiumBorder(
                    side: BorderSide(color: Colors.white54),
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('お気に入り'),
                  selected: _filterMode == FilterMode.favorites,
                  onSelected: (selected) {
                    if (selected) setState(() => _filterMode = FilterMode.favorites);
                  },
                  backgroundColor: Colors.transparent,
                  selectedColor: const Color(0xFF1DB954),
                  labelStyle: TextStyle(
                    color: _filterMode == FilterMode.favorites ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: const StadiumBorder(
                    side: BorderSide(color: Colors.white54),
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('プレイリスト'),
                  selected: _filterMode == FilterMode.playlists,
                  onSelected: (selected) {
                    if (selected) setState(() => _filterMode = FilterMode.playlists);
                  },
                  backgroundColor: Colors.transparent,
                  selectedColor: const Color(0xFF1DB954),
                  labelStyle: TextStyle(
                    color: _filterMode == FilterMode.playlists ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: const StadiumBorder(
                    side: BorderSide(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),

          // ▼ === 追加：曲数・プレイリスト数の表示 === ▼
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _filterMode == FilterMode.playlists
                    ? '${playerState.playlists.length} プレイリスト'
                    : '${displaySongs.length} 曲',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // ▲ =================================== ▲

          Expanded(
            child: _filterMode == FilterMode.playlists
                ? PlaylistGridView(
                    playlists: playerState.playlists,
                    onPlaylistTap: (playlist) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PlaylistDetailScreen(playlist: playlist),
                        ),
                      );
                    },
                  )
                : displaySongs.isEmpty
                    ? const _EmptyLibraryView()
                    : _PlaylistViewWithMenu(
                        playlist: displaySongs,
                        originalPlaylist: playlist,
                        currentSongIndex: currentSongIndex,
                        isPlaying: playerState.isPlaying,
                        onSongTap: (index) async {
                          final tappedSong = displaySongs[index];
                          final originalIndex = playlist.indexWhere((s) => s.id == tappedSong.id);
                          if (originalIndex != -1) {
                            await notifier.playSongAtIndex(originalIndex);
                            if (mounted) _openNowPlaying(context);
                          }
                        },
                        onFavoriteToggle: (song) async {
                          await notifier.toggleFavorite(song.id);
                        },
                        onDeleteSong: (song) async {
                          await notifier.removeSong(song.id);
                        },
                        onAddToPlaylist: (song) {
                          _showPlaylistSelectionDialog(context, notifier, song.id);
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddMusicBottomSheet(context, notifier),
        backgroundColor: AppColors.accent,
        child: const Icon(
          Icons.add_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
      bottomNavigationBar: playerState.currentSong != null
          ? SafeArea(
              child: GestureDetector(
                onTap: () => _openNowPlaying(context),
                onVerticalDragEnd: (details) {
                  if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
                    _openNowPlaying(context);
                  }
                },
                child: MiniPlayerWithProgress(
                  currentSong: playerState.currentSong,
                  isPlaying: playerState.isPlaying,
                  onTap: () => _openNowPlaying(context),
                  onPlayPause: () async {
                    if (playerState.isPlaying) {
                      await notifier.pause();
                    } else {
                      await notifier.play();
                    }
                  },
                  positionStream: notifier.positionStream,
                  duration: playerState.duration,
                ),
              ),
            )
          : null,
    );
  }

  void _openNowPlaying(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NowPlayingScreen(),
    );
  }

  void _showPlaylistSelectionDialog(BuildContext context, dynamic notifier, String songId) {
    showDialog(
      context: context,
      builder: (context) => PlaylistSelectionDialog(songId: songId),
    );
  }

  void _showAddMusicBottomSheet(BuildContext context, dynamic notifier) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '音楽を追加',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(
                Icons.music_note,
                color: AppColors.accent,
                size: 24,
              ),
              title: const Text(
                '1曲ずつ追加',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              onTap: () async {
                Navigator.pop(context);
                if (Platform.isIOS) {
                  await notifier.pickAndLoadSong();
                } else {
                  var status = await Permission.storage.request();
                  if (status.isGranted) {
                    await notifier.pickAndLoadSong();
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('ストレージ権限が必要です。設定で権限を許可してください。'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.folder,
                color: AppColors.accent,
                size: 24,
              ),
              title: const Text(
                'フォルダごと一括追加',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              onTap: () async {
                Navigator.pop(context);
                final addedCount = await notifier.pickAndLoadFolder();
                if (addedCount > 0 && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$addedCount曲を追加しました'),
                      backgroundColor: AppColors.accent,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ライブラリ空状態
// ─────────────────────────────────────────────

class _EmptyLibraryView extends StatelessWidget {
  const _EmptyLibraryView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_music_outlined,
            size: 64,
            color: AppColors.textDisabled,
          ),
          SizedBox(height: 16),
          Text(
            'ライブラリは空です',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '右下の＋ボタンから曲を追加してください',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 曲リスト表示（ポップアップメニュー拡張版）
// ─────────────────────────────────────────────

class _PlaylistViewWithMenu extends ConsumerWidget {
  final List<Song> playlist;
  final List<Song> originalPlaylist;
  final int currentSongIndex;
  final bool isPlaying;
  final Function(int) onSongTap;
  final Function(Song) onFavoriteToggle;
  final Function(Song) onDeleteSong;
  final Function(Song) onAddToPlaylist;

  const _PlaylistViewWithMenu({
    required this.playlist,
    required this.originalPlaylist,
    required this.currentSongIndex,
    required this.isPlaying,
    required this.onSongTap,
    required this.onFavoriteToggle,
    required this.onDeleteSong,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: playlist.length,
      itemBuilder: (context, index) {
        final song = playlist[index];
        final isCurrentSong = index == currentSongIndex;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    song.artist,
                    style: TextStyle(
                      color: Colors.grey.withValues(alpha: 0.7),
                      fontSize: 13,
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
              // Playlist checkmark
              FutureBuilder<bool>(
                future: DatabaseHelper().isSongInAnyPlaylist(song.id),
                builder: (context, snapshot) {
                  if (snapshot.data == true) {
                    return const Padding(
                      padding: EdgeInsets.only(right: 12.0),
                      child: Icon(Icons.check_circle, color: AppColors.accent, size: 24),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              // Favorite button
              IconButton(
                icon: Icon(
                  song.isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: song.isFavorite ? Colors.red : AppColors.textSecondary,
                  size: 24,
                ),
                onPressed: () => onFavoriteToggle(song),
                tooltip: song.isFavorite ? 'お気に入りから削除' : 'お気に入りに追加',
              ),

              // More options menu
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                onSelected: (value) {
                  if (value == 'delete') {
                    onDeleteSong(song);
                  } else if (value == 'add_to_playlist') {
                    onAddToPlaylist(song);
                  } else if (value == 'add_lyrics') {
                    _pickAndAttachLrcFile(context, ref, song); // ✅ context, ref, song の順
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'add_lyrics',
                    child: Row(
                      children: [
                        const Icon(Icons.lyrics_rounded, color: AppColors.accent, size: 20),
                        const SizedBox(width: 12),
                        const Text(
                          '歌詞ファイルを登録(.lrc)',
                          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 12),
                        const Text(
                          'ライブラリから削除',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'add_to_playlist',
                    child: Row(
                      children: [
                        const Icon(Icons.playlist_add, color: AppColors.accent, size: 20),
                        const SizedBox(width: 12),
                        const Text(
                          'プレイリストに追加',
                          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Playing indicator
              if (isCurrentSong && isPlaying)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: AppColors.accent,
                    size: 20,
                  ),
                ),
            ],
          ),
          onTap: () => onSongTap(index),
        );
      },
    );
  }

  Widget _buildDefaultIcon() {
    return const Icon(
      Icons.music_note_rounded,
      color: AppColors.textDisabled,
      size: 28,
    );
  }

  Future<void> _pickAndAttachLrcFile(BuildContext context, WidgetRef ref, Song song) async {
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

          if (context.mounted) { // ✅ mounted → context.mounted
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
      if (context.mounted) { // ✅ mounted → context.mounted
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

// ─────────────────────────────────────────────
// プレイリストグリッド表示
// ─────────────────────────────────────────────

class PlaylistGridView extends StatelessWidget {
  final List<Map<String, dynamic>> playlists;
  final Function(Map<String, dynamic>) onPlaylistTap;

  const PlaylistGridView({
    required this.playlists,
    required this.onPlaylistTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.85,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return GestureDetector(
          onTap: () => onPlaylistTap(playlist),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceVariant, width: 1),
            ),
            child: Column(
              children: [
                Expanded(
                  flex: 3,
                  child: FutureBuilder<List<Song>>(
                    future: DatabaseHelper().getPlaylistSongs(playlist['id']),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                        final firstSong = snapshot.data!.first;
                        return Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                          ),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            child: firstSong.albumArt != null
                                ? Image.memory(
                                    firstSong.albumArt!,
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: AppColors.surface,
                                        child: const Icon(
                                          Icons.playlist_play,
                                          color: AppColors.accent,
                                          size: 32,
                                        ),
                                      );
                                    },
                                  )
                                : Container(
                                    color: AppColors.surface,
                                    child: const Icon(
                                      Icons.playlist_play,
                                      color: AppColors.accent,
                                      size: 32,
                                    ),
                                  ),
                          ),
                        );
                      } else {
                        return Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                          ),
                          child: const Icon(
                            Icons.playlist_play,
                            color: AppColors.accent,
                            size: 32,
                          ),
                        );
                      }
                    },
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      playlist['name'] as String? ?? 'Untitled',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}