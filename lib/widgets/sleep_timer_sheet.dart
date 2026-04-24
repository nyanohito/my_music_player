// ============================================================
// widgets/sleep_timer_sheet.dart
// スリープタイマー（曲の終わりで停止 or N分後に停止）
//
// 使い方:
//   SleepTimerSheet.show(context);
//
// now_playing_screen.dart の設定ボタン等から呼び出す:
//   IconButton(
//     icon: Icon(Icons.bedtime_outlined),
//     onPressed: () => SleepTimerSheet.show(context),
//   )
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';

// ── スリープタイマーの状態管理 Provider ─────────────────────
final sleepTimerProvider =
    StateNotifierProvider<SleepTimerNotifier, SleepTimerState>((ref) {
  return SleepTimerNotifier(ref);
});

class SleepTimerState {
  final bool isActive;
  final Duration? remaining; // null = 非アクティブ
  final bool endOfSong;      // true = 曲の終わりで停止

  const SleepTimerState({
    this.isActive = false,
    this.remaining,
    this.endOfSong = false,
  });

  SleepTimerState copyWith({
    bool? isActive,
    Duration? remaining,
    bool? endOfSong,
    bool clearRemaining = false,
  }) {
    return SleepTimerState(
      isActive: isActive ?? this.isActive,
      remaining: clearRemaining ? null : remaining ?? this.remaining,
      endOfSong: endOfSong ?? this.endOfSong,
    );
  }

  String get displayText {
    if (!isActive) return 'オフ';
    if (endOfSong) return '曲の終わりで停止';
    final r = remaining;
    if (r == null) return 'オフ';
    final m = r.inMinutes;
    final s = r.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class SleepTimerNotifier extends StateNotifier<SleepTimerState> {
  final Ref _ref;
  Timer? _ticker;

  SleepTimerNotifier(this._ref) : super(const SleepTimerState());

  /// N分後に停止するタイマーをセット
  void setTimer(Duration duration) {
    _cancelTimer();
    state = SleepTimerState(
      isActive: true,
      remaining: duration,
      endOfSong: false,
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final r = state.remaining;
      if (r == null || r.inSeconds <= 0) {
        _stopPlayback();
        return;
      }
      state = state.copyWith(remaining: r - const Duration(seconds: 1));
    });
  }

  /// 今の曲が終わったら停止
  void setEndOfSong() {
    _cancelTimer();
    state = SleepTimerState(isActive: true, endOfSong: true);
  }

  /// タイマーをキャンセル
  void cancel() {
    _cancelTimer();
    state = const SleepTimerState();
  }

  void _cancelTimer() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _stopPlayback() {
    _cancelTimer();
    state = const SleepTimerState();
    _ref.read(audioPlayerProvider.notifier).player.stop();
  }

  /// 曲が変わったときに呼ぶ（endOfSong モードで停止判定）
  void onSongChanged() {
    if (state.isActive && state.endOfSong) {
      _stopPlayback();
    }
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }
}

// ── ボトムシート本体 ─────────────────────────────────────────
class SleepTimerSheet extends ConsumerWidget {
  const SleepTimerSheet._();

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const SleepTimerSheet._(),
    );
  }

  static const _presets = [
    (label: '5分', duration: Duration(minutes: 5)),
    (label: '10分', duration: Duration(minutes: 10)),
    (label: '15分', duration: Duration(minutes: 15)),
    (label: '20分', duration: Duration(minutes: 20)),
    (label: '30分', duration: Duration(minutes: 30)),
    (label: '45分', duration: Duration(minutes: 45)),
    (label: '60分', duration: Duration(minutes: 60)),
    (label: '90分', duration: Duration(minutes: 90)),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(sleepTimerProvider);
    final notifier = ref.read(sleepTimerProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── ハンドル ───────────────────────────────────
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── タイトル + 現在の状態 ───────────────────────
            Row(
              children: [
                const Icon(Icons.bedtime_rounded,
                    color: AppColors.accent, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'スリープタイマー',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (timer.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      timer.displayText,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // ── 曲の終わりで停止 ─────────────────────────────
            _OptionTile(
              icon: Icons.music_note_rounded,
              label: '曲の終わりで停止',
              isSelected: timer.isActive && timer.endOfSong,
              onTap: () {
                notifier.setEndOfSong();
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 12),

            // ── プリセット ───────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets.map((p) {
                final isSelected = timer.isActive &&
                    !timer.endOfSong &&
                    timer.remaining != null &&
                    (timer.remaining!.inMinutes == p.duration.inMinutes);

                return _TimerChip(
                  label: p.label,
                  isSelected: isSelected,
                  onTap: () {
                    notifier.setTimer(p.duration);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── キャンセルボタン ─────────────────────────────
            if (timer.isActive) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('タイマーをキャンセル'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    notifier.cancel();
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 選択肢タイル ─────────────────────────────────────────────
class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? AppColors.accent.withValues(alpha: 0.15)
          : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon,
                  color:
                      isSelected ? AppColors.accent : AppColors.textSecondary,
                  size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.accent
                      : AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              const Spacer(),
              if (isSelected)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── プリセットチップ ─────────────────────────────────────────
class _TimerChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TimerChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? AppColors.accent
                : AppColors.textDisabled.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
