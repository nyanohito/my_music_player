// ============================================================
// screens/queue_screen.dart
// 再生キュー画面（Up Next / 今後の再生順を表示・並び替え）
//
// 使い方:
//   Navigator.push(context,
//     MaterialPageRoute(builder: (_) => const QueueScreen()));
//
// now_playing_screen.dart の AppBar アクションに追加:
//   IconButton(
//     icon: Icon(Icons.queue_music_rounded),
//     onPressed: () => Navigator.push(context,
//       MaterialPageRoute(builder: (_) => const QueueScreen())),
//   )
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(audioPlayerProvider);
    final notifier = ref.read(audioPlayerProvider.notifier);

    final playlist = playerState.playlist;
    final currentIndex = playerState.currentIndex ?? 0;

    // 現在再生中の曲
    final currentSong = currentIndex < playlist.length
        ? playlist[currentIndex]
        : null;

    // Up Next リスト（現在の曲より後）
    final upNext = currentIndex + 1 < playlist.length
        ? playlist.sublist(currentIndex + 1)
        : <dynamic>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textPrimary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '再生キュー',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: upNext.isEmpty
                ? null
                : () => _showClearDialog(context, notifier),
            child: Text(
              'クリア',
              style: TextStyle(
                color: upNext.isEmpty
                    ? AppColors.textDisabled
                    : Colors.redAccent,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // ── 再生中 ────────────────────────────────────────
          if (currentSong != null) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  '再生中',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _CurrentSongTile(song: currentSong),
            ),
          ],

          // ── Up Next ──────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  const Text(
                    'UP NEXT',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${upNext.length}曲',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (upNext.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.queue_music_rounded,
                          color: AppColors.textDisabled, size: 48),
                      SizedBox(height: 12),
                      Text(
                        'キューは空です',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            // ドラッグで並び替え可能なリスト
            SliverReorderableList(
              itemCount: upNext.length,
              onReorder: (oldIndex, newIndex) {
                // playlist 内の実際のインデックスに変換して並び替え
                final actualOld = currentIndex + 1 + oldIndex;
                int actualNew = currentIndex + 1 + newIndex;
                if (newIndex > oldIndex) actualNew -= 1;
                notifier.reorderQueue(actualOld, actualNew);
              },
              itemBuilder: (context, index) {
                final song = upNext[index];
                final actualIndex = currentIndex + 1 + index;

                return ReorderableDragStartListener(
                  key: ValueKey('queue_${song.id}_$index'),
                  index: index,
                  child: _QueueSongTile(
                    song: song,
                    index: actualIndex,
                    onTap: () async {
                      await notifier.playSongAtIndex(actualIndex);
                      if (context.mounted) Navigator.pop(context);
                    },
                    onRemove: () => notifier.removeFromQueue(actualIndex),
                  ),
                );
              },
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context, dynamic notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'キューをクリア',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          '再生中の曲以降のキューを全て削除しますか？',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              notifier.clearQueue();
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('クリア',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

// ── 再生中の曲タイル ─────────────────────────────────────────
class _CurrentSongTile extends StatelessWidget {
  final dynamic song;

  const _CurrentSongTile({required this.song});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          // アルバムアート
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: song.albumArt != null
                ? Image.memory(song.albumArt!,
                    width: 52, height: 52, fit: BoxFit.cover)
                : Container(
                    width: 52,
                    height: 52,
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.music_note_rounded,
                        color: AppColors.textDisabled, size: 24),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title ?? 'Unknown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  song.artist ?? 'Unknown',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.equalizer_rounded,
            color: AppColors.accent,
            size: 22,
          ),
        ],
      ),
    );
  }
}

// ── キュー内の曲タイル ───────────────────────────────────────
class _QueueSongTile extends StatelessWidget {
  final dynamic song;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _QueueSongTile({
    required this.song,
    required this.index,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // ドラッグハンドル
              const Icon(Icons.drag_handle_rounded,
                  color: AppColors.textDisabled, size: 22),
              const SizedBox(width: 12),

              // アルバムアート
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: song.albumArt != null
                    ? Image.memory(song.albumArt!,
                        width: 46, height: 46, fit: BoxFit.cover)
                    : Container(
                        width: 46,
                        height: 46,
                        color: AppColors.surfaceVariant,
                        child: const Icon(Icons.music_note_rounded,
                            color: AppColors.textDisabled, size: 20),
                      ),
              ),
              const SizedBox(width: 12),

              // 曲情報
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title ?? 'Unknown',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song.artist ?? 'Unknown',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // 削除ボタン
              IconButton(
                icon: const Icon(Icons.remove_circle_outline_rounded,
                    color: AppColors.textDisabled, size: 22),
                onPressed: onRemove,
                tooltip: 'キューから削除',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
