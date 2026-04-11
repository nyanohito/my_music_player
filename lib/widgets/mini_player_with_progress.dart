// ============================================================
// widgets/mini_player_with_progress.dart
// ミニプレイヤーバー（プログレスバー付き）
// ============================================================

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MiniPlayerWithProgress extends StatelessWidget {
  final dynamic currentSong; // Song?
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onPlayPause;
  final Stream<Duration>? positionStream;
  final Duration? duration;

  const MiniPlayerWithProgress({
    required this.currentSong,
    required this.isPlaying,
    required this.onTap,
    required this.onPlayPause,
    this.positionStream,
    this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          // Main content
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // Mini album artwork
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: currentSong?.albumArt != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            currentSong!.albumArt!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.music_note_rounded,
                                color: AppColors.textSecondary,
                                size: 22,
                              );
                            },
                          ),
                        )
                      : const Icon(
                          Icons.music_note_rounded,
                          color: AppColors.textSecondary,
                          size: 22,
                        ),
                ),
                const SizedBox(width: 12),

                // Song title
                Expanded(
                  child: Text(
                    currentSong?.title ?? 'Unknown Song',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // 再生・一時停止ボタン
                IconButton(
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_filled_rounded,
                    size: 36,
                  ),
                  color: AppColors.textPrimary,
                  onPressed: onPlayPause,
                ),
              ],
            ),
          ),
          
          // Progress bar at bottom
          if (positionStream != null && duration != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: StreamBuilder<Duration>(
                stream: positionStream!,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? Duration.zero;
                  final progress = duration!.inMilliseconds > 0 
                      ? position.inMilliseconds / duration!.inMilliseconds 
                      : 0.0;
                  
                  return LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.accent,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
