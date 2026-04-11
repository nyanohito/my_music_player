// ============================================================
// screens/play_history_screen.dart
// 再生履歴画面
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';
import '../models/song.dart';
import '../utils/database_helper.dart';
import 'now_playing_screen.dart';

class PlayHistoryScreen extends ConsumerWidget {
  const PlayHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '再生履歴',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Song>>(
        future: DatabaseHelper().getRecentPlayHistory(),
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
                    '履歴の読み込みに失敗しました',
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
                    Icons.history,
                    size: 64,
                    color: AppColors.textDisabled,
                  ),
                  SizedBox(height: 16),
                  Text(
                    '最近再生した曲はありません',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '曲を再生すると履歴が表示されます',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return _PlaylistViewWithMenu(
                song: song,
                onSongTap: (song) async {
                  final playerState = ref.read(audioPlayerProvider);
                  final notifier = ref.read(audioPlayerProvider.notifier);
                  final originalIndex = playerState.playlist.indexWhere((s) => s.id == song.id);
                  if (originalIndex != -1) {
                    await notifier.playSongAtIndex(originalIndex);
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
                      );
                    }
                  }
                },
                onFavoriteToggle: (song) {
                  ref.read(audioPlayerProvider.notifier).toggleFavorite(song.id);
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Spotify風の曲リスト項目（ライブラリ画面と同じデザイン）
class _PlaylistViewWithMenu extends StatelessWidget {
  final Song song;
  final Function(Song) onSongTap;
  final Function(Song) onFavoriteToggle;

  const _PlaylistViewWithMenu({
    super.key,
    required this.song,
    required this.onSongTap,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
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
                )
              : Container(
                  color: AppColors.surface,
                  child: const Icon(
                    Icons.music_note_rounded,
                    size: 28,
                    color: AppColors.textDisabled,
                  ),
                ),
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
          Text(
            song.artist,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (song.lyrics.isNotEmpty)
            Row(
              children: [
                const Icon(
                  Icons.lyrics_rounded,
                  size: 14,
                  color: AppColors.accent,
                ),
              ],
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
        ],
      ),
      onTap: () => onSongTap(song),
    );
  }
}
