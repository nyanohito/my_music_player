import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/lyric_line.dart';
import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';

const double _kHorizontalPadding = 24.0;
const Duration _kAnimDuration = Duration(milliseconds: 300);
const Curve _kAnimCurve = Curves.easeOutCubic;

enum _LyricLineState { highlighted, near, normal }

abstract final class _LyricSanitizer {
  static String clean(String raw) => raw
      .replaceAll('\r\n', ' ')
      .replaceAll('\r', '')
      .replaceAll('\n', ' ')
      .replaceAll('\u200B', '')
      .replaceAll('\u200C', '')
      .replaceAll('\u200D', '')
      .replaceAll('\uFEFF', '')
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
}

class LyricView extends ConsumerStatefulWidget {
  const LyricView({super.key});

  @override
  ConsumerState<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends ConsumerState<LyricView> {
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener = ItemPositionsListener.create();

  int _lastHighlightedIndex = -1;
  String? _lastSongId;
  bool _isInitialScroll = true; 

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(audioPlayerProvider);
    final notifier    = ref.read(audioPlayerProvider.notifier);
    final lyrics      = playerState.currentSong?.lyrics ?? [];
    final currentIdx  = playerState.currentLyricIndex;
    final songId      = playerState.currentSong?.id;

    if (songId != _lastSongId) {
      _lastSongId           = songId;
      _lastHighlightedIndex = -1;
      _isInitialScroll      = true;
    }

    if (currentIdx != _lastHighlightedIndex &&
        currentIdx >= 0 &&
        currentIdx < lyrics.length) {
      _lastHighlightedIndex = currentIdx;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToIndex(currentIdx);
      });
    }

    if (lyrics.isEmpty) return const _EmptyLyricView();

    return ScrollablePositionedList.builder(
      itemCount: lyrics.length,
      itemScrollController: _scrollController,
      itemPositionsListener: _positionsListener,
      padding: EdgeInsets.only(
        top:    MediaQuery.of(context).size.height * 0.35,
        bottom: MediaQuery.of(context).size.height * 0.35,
        left:   _kHorizontalPadding,
        right:  _kHorizontalPadding,
      ),
      itemBuilder: (context, index) {
        return _LyricLineItem(
          lyricLine: lyrics[index],
          state: _resolveState(index, currentIdx),
          onTap: () => notifier.seekTo(lyrics[index].position),
        );
      },
    );
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.isAttached) return;
    _scrollController.scrollTo(
      index: index,
      alignment: 0.5, 
      duration: _isInitialScroll ? Duration.zero : const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
    _isInitialScroll = false;
  }

  _LyricLineState _resolveState(int index, int current) {
    if (current < 0) return _LyricLineState.normal;
    if (index == current) return _LyricLineState.highlighted;
    if ((index - current).abs() == 1) return _LyricLineState.near;
    return _LyricLineState.normal;
  }
}

class _LyricLineItem extends StatelessWidget {
  const _LyricLineItem({
    required this.lyricLine,
    required this.state,
    required this.onTap,
  });

  final LyricLine lyricLine;
  final _LyricLineState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = lyricLine.text.isEmpty ? '♪' : _LyricSanitizer.clean(lyricLine.text);

    final isHigh = state == _LyricLineState.highlighted;
    final isNear = state == _LyricLineState.near;

    final double targetFontSize = isHigh ? 32.0 : (isNear ? 26.0 : 22.0);
    final double targetOpacity  = isHigh ? 1.00 : (isNear ? 0.55 : 0.38);
    // 行間指定を消した分、ここでパディングを少し増やして上下の空間を確保します
    final double targetVertPad  = isHigh ? 16.0 : 10.0;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedPadding(
        duration: _kAnimDuration,
        curve: _kAnimCurve,
        padding: EdgeInsets.symmetric(vertical: targetVertPad),
        child: AnimatedDefaultTextStyle(
          duration: _kAnimDuration,
          curve: _kAnimCurve,
          style: TextStyle(
            color: Colors.white.withValues(alpha: targetOpacity),
            fontSize: targetFontSize,
            fontWeight: FontWeight.w800,
            // 🚨 ここにあった `height` の指定を完全に削除しました。
            // これによりフォントが本来必要とするサイズが100%確保され、見切れが消滅します。
            letterSpacing: -0.3,
            shadows: isHigh
                ? [Shadow(color: Colors.white.withValues(alpha: 0.3), blurRadius: 16)]
                : const [],
          ),
          child: Container(
            width: double.infinity,
            alignment: Alignment.centerLeft,
            // さらに念のため、OSレベルでの上下クリッピングを防ぐオプションを追加
            child: Text(
              text,
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: true,
                applyHeightToLastDescent: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyLyricView extends StatelessWidget {
  const _EmptyLyricView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lyrics_outlined, color: AppColors.textDisabled, size: 48),
          SizedBox(height: 16),
          Text(
            '歌詞がありません',
            style: TextStyle(color: AppColors.textDisabled, fontSize: 16, height: 1.6),
          ),
          SizedBox(height: 8),
          Text(
            'LRCファイルを追加して歌詞を表示しましょう',
            style: TextStyle(color: AppColors.textDisabled, fontSize: 13, height: 1.6),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}