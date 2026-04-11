// ============================================================
// widgets/player_controls.dart
// 再生ボタン・シークバーなどの操作UIウィジェット
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';

/// 再生コントロール全体（シークバー＋ボタン群）
class PlayerControls extends ConsumerWidget {
  const PlayerControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(audioPlayerProvider);
    final notifier = ref.read(audioPlayerProvider.notifier);

    return Column(
      children: [
        // ── シークバー ──────────────────────────
        _SeekBar(
          position: playerState.position,
          duration: playerState.duration,
          onSeek: notifier.seekTo,
        ),

        const SizedBox(height: 8),

        // ── 再生位置の時刻表示 ───────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(playerState.position),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              Text(
                _formatDuration(playerState.duration),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Volume control
        _VolumeSlider(),

        const SizedBox(height: 24),

        // Control buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Shuffle button
            _ShuffleButton(
              isShuffleModeEnabled: playerState.isShuffleModeEnabled,
              onTap: notifier.toggleShuffle,
            ),

            const SizedBox(width: 8),

            // Previous button
            IconButton(
              icon: const Icon(Icons.skip_previous_rounded),
              iconSize: 44,
              color: AppColors.textPrimary,
              onPressed: () async {
                await notifier.playPrevious();
              },
            ),

            const SizedBox(width: 16),

            // Play/Pause button (main)
            _PlayPauseButton(
              isPlaying: playerState.isPlaying,
              isLoading: playerState.isLoading,
              onTap: notifier.togglePlayPause,
            ),

            const SizedBox(width: 16),

            // Next button
            IconButton(
              icon: const Icon(Icons.skip_next_rounded),
              iconSize: 44,
              color: AppColors.textPrimary,
              onPressed: () async {
                await notifier.playNext();
              },
            ),

            const SizedBox(width: 8),

            // Repeat button
            _RepeatButton(
              repeatMode: playerState.repeatMode,
              onTap: notifier.toggleRepeat,
            ),
          ],
        ),
      ],
    );
  }

  /// Duration を "m:ss" 形式にフォーマット
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────
// 再生 / 一時停止ボタン
// ─────────────────────────────────────────────

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onTap;

  const _PlayPauseButton({
    required this.isPlaying,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        height: 68,
        decoration: const BoxDecoration(
          color: AppColors.textPrimary, // 白い丸ボタン（Spotify スタイル）
          shape: BoxShape.circle,
        ),
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  color: AppColors.background,
                  strokeWidth: 2.5,
                ),
              )
            : Icon(
                isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: AppColors.background,
                size: 36,
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// シークバー
// ─────────────────────────────────────────────

class _SeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const _SeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  // ドラッグ中の位置（nullならドラッグしていない）
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds.toDouble();
    final current = _dragValue ??
        widget.position.inMilliseconds.toDouble().clamp(0, total == 0 ? 1 : total);

    return Slider(
      value: total > 0 ? current : 0,
      min: 0,
      max: total > 0 ? total : 1,
      onChangeStart: (value) {
        setState(() => _dragValue = value);
      },
      onChanged: (value) {
        setState(() => _dragValue = value);
      },
      onChangeEnd: (value) {
        widget.onSeek(Duration(milliseconds: value.toInt()));
        setState(() => _dragValue = null);
      },
    );
  }
}

// ─────────────────────────────────────────────
// 音量調節スライダー
// ─────────────────────────────────────────────

class _VolumeSlider extends ConsumerStatefulWidget {
  const _VolumeSlider();

  @override
  ConsumerState<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends ConsumerState<_VolumeSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(audioPlayerProvider);
    final notifier = ref.read(audioPlayerProvider.notifier);
    
    return StreamBuilder<double>(
      stream: notifier.player.volumeStream,
      initialData: 1.0,
      builder: (context, snapshot) {
        final currentVolume = _dragValue ?? snapshot.data ?? 1.0;
        
        return Row(
          children: [
            // スピーカーアイコン
            Icon(
              currentVolume == 0.0 
                  ? Icons.volume_off_rounded 
                  : (currentVolume < 0.5 
                      ? Icons.volume_down_rounded 
                      : Icons.volume_up_rounded),
              color: AppColors.textSecondary,
              size: 24,
            ),
            
            const SizedBox(width: 12),
            
            // 音量スライダー
            Expanded(
              child: SliderTheme(
                data: const SliderThemeData(
                  activeTrackColor: AppColors.textSecondary,
                  inactiveTrackColor: AppColors.textDisabled,
                  thumbColor: AppColors.textSecondary,
                  overlayColor: Color(0x29FFFFFF),
                  trackHeight: 2,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
                ),
                child: Slider(
                  value: currentVolume,
                  min: 0.0,
                  max: 1.0,
                  onChangeStart: (value) {
                    setState(() => _dragValue = value);
                  },
                  onChanged: (value) {
                    setState(() => _dragValue = value);
                    notifier.player.setVolume(value);
                  },
                  onChangeEnd: (value) {
                    setState(() => _dragValue = null);
                  },
                ),
              ),
            ),
            
            const SizedBox(width: 8),
            
            // 音量数値表示
            SizedBox(
              width: 40,
              child: Text(
                '${(currentVolume * 100).round()}%',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
    );
  }
}

// Shuffle button widget
class _ShuffleButton extends StatelessWidget {
  final bool isShuffleModeEnabled;
  final VoidCallback onTap;

  const _ShuffleButton({
    required this.isShuffleModeEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.shuffle_rounded),
      iconSize: 32,
      color: isShuffleModeEnabled ? AppColors.accent : AppColors.textSecondary,
      onPressed: onTap,
      tooltip: 'Shuffle',
    );
  }
}

// Repeat button widget
class _RepeatButton extends StatelessWidget {
  final PlaylistMode repeatMode;
  final VoidCallback onTap;

  const _RepeatButton({
    required this.repeatMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String tooltip;

    switch (repeatMode) {
      case PlaylistMode.off:
        icon = Icons.repeat_rounded;
        color = AppColors.textSecondary;
        tooltip = 'Repeat: Off';
        break;
      case PlaylistMode.one:
        icon = Icons.repeat_one_rounded;
        color = AppColors.accent;
        tooltip = 'Repeat: One';
        break;
      case PlaylistMode.all:
        icon = Icons.repeat_rounded;
        color = AppColors.accent;
        tooltip = 'Repeat: All';
        break;
    }

    return IconButton(
      icon: Icon(icon),
      iconSize: 32,
      color: color,
      onPressed: onTap,
      tooltip: tooltip,
    );
  }
}
