import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/lyric_line.dart';
import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';

const double _kBaseFontSize = 32.0;
const double _kScaleHighlighted = 1.000;
const double _kScaleNear        = 28.0 / _kBaseFontSize;
const double _kScaleNormal      = 24.0 / _kBaseFontSize;

const double _kOpacityHighlighted = 1.00;
const double _kOpacityNear        = 0.55;
const double _kOpacityNormal      = 0.38;

const double _kVertPadHighlighted = 16.0;
const double _kVertPadOther       =  8.0;

const double _kHorizontalPadding = 24.0;
const Duration _kAnimDuration = Duration(milliseconds: 400);
const Curve    _kAnimCurve    = Curves.easeInOutCubic;

const TextStyle _kMeasureStyle = TextStyle(
  fontSize:      _kBaseFontSize,
  fontWeight:    FontWeight.w800, 
  height:        1.5,
  letterSpacing: -0.3,
);

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
  final ItemScrollController    _scrollController  = ItemScrollController();
  final ItemPositionsListener   _positionsListener = ItemPositionsListener.create();

  int     _lastHighlightedIndex = -1;
  String? _lastSongId;
  bool    _isInitialScroll      = true;

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
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToIndex(currentIdx));
    }

    if (lyrics.isEmpty) return const _EmptyLyricView();

    return ScrollablePositionedList.builder(
      itemCount:              lyrics.length,
      itemScrollController:   _scrollController,
      itemPositionsListener:  _positionsListener,
      padding: EdgeInsets.only(
        top:    MediaQuery.of(context).size.height * 0.38,
        bottom: MediaQuery.of(context).size.height * 0.38,
        left:   _kHorizontalPadding,
        right:  _kHorizontalPadding,
      ),
      itemBuilder: (context, index) => _LyricLineItem(
        key:       ValueKey('${songId}_$index'),
        lyricLine: lyrics[index],
        state:     _resolveState(index, currentIdx),
        onTap:     () => notifier.seekTo(lyrics[index].position),
      ),
    );
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.isAttached) return;
    _scrollController.scrollTo(
      index:     index,
      alignment: 0.5,
      duration:  _isInitialScroll ? Duration.zero : const Duration(milliseconds: 450),
      curve:     Curves.easeOutCubic,
    );
    _isInitialScroll = false;
  }

  _LyricLineState _resolveState(int index, int current) {
    if (current < 0)                  return _LyricLineState.normal;
    if (index == current)             return _LyricLineState.highlighted;
    if ((index - current).abs() == 1) return _LyricLineState.near;
    return _LyricLineState.normal;
  }
}

class _LyricLineItem extends StatefulWidget {
  const _LyricLineItem({
    super.key,
    required this.lyricLine,
    required this.state,
    required this.onTap,
  });

  final LyricLine        lyricLine;
  final _LyricLineState  state;
  final VoidCallback     onTap;

  @override
  State<_LyricLineItem> createState() => _LyricLineItemState();
}

class _LyricLineItemState extends State<_LyricLineItem> {
  double _cachedWidth  = -1;
  double _naturalHeight = _kBaseFontSize * 1.5;

  double _measureNaturalHeight(double maxWidth, String text) {
    if ((maxWidth - _cachedWidth).abs() < 0.5) return _naturalHeight;

    final tp = TextPainter(
      text:           TextSpan(text: text, style: _kMeasureStyle),
      textDirection:  TextDirection.ltr,
      textAlign:      TextAlign.left,
      textWidthBasis: TextWidthBasis.parent,
      textScaler:     TextScaler.noScaling, // 🚨 iPhoneの文字サイズ設定を無視する
    )..layout(maxWidth: maxWidth);

    _cachedWidth   = maxWidth;
    _naturalHeight = tp.height;
    tp.dispose();
    return _naturalHeight;
  }

  String get _cleanText =>
      widget.lyricLine.text.isEmpty
          ? '♪'
          : _LyricSanitizer.clean(widget.lyricLine.text);

  double get _targetScale => switch (widget.state) {
    _LyricLineState.highlighted => _kScaleHighlighted,
    _LyricLineState.near        => _kScaleNear,
    _LyricLineState.normal      => _kScaleNormal,
  };

  double get _targetOpacity => switch (widget.state) {
    _LyricLineState.highlighted => _kOpacityHighlighted,
    _LyricLineState.near        => _kOpacityNear,
    _LyricLineState.normal      => _kOpacityNormal,
  };

  double get _targetVertPad =>
      widget.state == _LyricLineState.highlighted
          ? _kVertPadHighlighted
          : _kVertPadOther;

  @override
  Widget build(BuildContext context) {
    final text = _cleanText;

    return GestureDetector(
      onTap:    widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final naturalHeight = _measureNaturalHeight(constraints.maxWidth, text);

          return _AnimatedLyricBox(
            text:            text,
            naturalHeight:   naturalHeight,
            availableWidth:  constraints.maxWidth,
            scale:           _targetScale,
            opacity:         _targetOpacity,
            verticalPadding: _targetVertPad,
            duration:        _kAnimDuration,
            curve:           _kAnimCurve,
          );
        },
      ),
    );
  }
}

class _AnimatedLyricBox extends ImplicitlyAnimatedWidget {
  const _AnimatedLyricBox({
    required this.text,
    required this.naturalHeight,
    required this.availableWidth,
    required this.scale,
    required this.opacity,
    required this.verticalPadding,
    required super.duration,
    super.curve = Curves.linear,
  });

  final String text;
  final double naturalHeight;
  final double availableWidth;
  final double scale;
  final double opacity;
  final double verticalPadding;

  @override
  ImplicitlyAnimatedWidgetState<_AnimatedLyricBox> createState() =>
      _AnimatedLyricBoxState();
}

class _AnimatedLyricBoxState
    extends AnimatedWidgetBaseState<_AnimatedLyricBox> {
  Tween<double>? _scaleTween;
  Tween<double>? _opacityTween;
  Tween<double>? _vertPadTween;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _scaleTween = visitor(
      _scaleTween, widget.scale,
      (v) => Tween<double>(begin: v as double),
    ) as Tween<double>?;

    _opacityTween = visitor(
      _opacityTween, widget.opacity,
      (v) => Tween<double>(begin: v as double),
    ) as Tween<double>?;

    _vertPadTween = visitor(
      _vertPadTween, widget.verticalPadding,
      (v) => Tween<double>(begin: v as double),
    ) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    final scale   = _scaleTween?.evaluate(animation)   ?? widget.scale;
    final opacity = _opacityTween?.evaluate(animation) ?? widget.opacity;
    final vertPad = _vertPadTween?.evaluate(animation) ?? widget.verticalPadding;

    final rawH = widget.naturalHeight + vertPad * 2;
    final glowT = ((scale - _kScaleNormal) /
        (_kScaleHighlighted - _kScaleNormal)).clamp(0.0, 1.0);

    return SizedBox(
      height: rawH * scale,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minHeight: 0,
        // 🚨 究極の修正：高さを「無制限(double.infinity)」にして絶対に切らない！
        maxHeight: double.infinity, 
        minWidth:  0,
        maxWidth:  widget.availableWidth,
        child: Transform.scale(
          scale:     scale,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width:  widget.availableWidth,
            // 🚨 ここにあった height: rawH も削除し、テキスト自身の自然な高さに任せます
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: vertPad),
              child: RichText(
                // 🚨 iPhoneの「文字を大きくする」設定などでレイアウトが崩れるのを防ぐ
                textScaler: TextScaler.noScaling,
                text: TextSpan(
                  text:  widget.text,
                  style: TextStyle(
                    color:         Colors.white.withValues(alpha: opacity),
                    fontSize:      _kBaseFontSize, 
                    fontWeight:    FontWeight.w800,
                    height:        1.5,
                    letterSpacing: -0.3,
                    shadows: glowT > 0.05
                        ? [Shadow(
                            color:      Colors.white.withValues(alpha: glowT * 0.28),
                            blurRadius: 18,
                          )]
                        : const [],
                  ),
                ),
                textAlign:      TextAlign.left,
                textWidthBasis: TextWidthBasis.parent,
                textDirection:  TextDirection.ltr,
                softWrap:       true,
                overflow:       TextOverflow.visible,
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