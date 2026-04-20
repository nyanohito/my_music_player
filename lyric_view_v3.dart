// ============================================================
// widgets/lyric_view.dart
// ============================================================
//
// ■ アーキテクチャ概要
//
//   【課題1: リフロー & ゴーストスペース解決】
//     _RenderLyricScaleBox (カスタム RenderBox)
//       - テキストは常に _kBaseFontSize(26sp) でレイアウト計算 → リフロー完全消滅
//       - 視覚的スケール(Canvas transform)のみアニメーション
//       - 報告するレイアウト高さ = rawHeight * scale → ゴーストスペース消滅
//     _AnimatedLyricBox (ImplicitlyAnimatedWidget)
//       - scale / opacity / verticalPadding を独立したTweenで補間
//       - forEachTween が「現在値→新ターゲット」を自動管理
//
//   【課題2: シーク時スクロール位置ズレ解決】
//     scrollable_positioned_list パッケージ
//       - ItemScrollController.scrollTo(index, alignment: 0.5)
//       - 高さが動的に変動するリストでも index ベースで正確に中央ロック
//       - ensureVisible/offset計算に依存しないため、複数行高変化に無敵
//
// ■ pubspec.yaml に追加:
//     scrollable_positioned_list: ^0.3.8
//
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/lyric_line.dart';
import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════

/// すべての行はこのサイズでテキストレイアウトを計算する。
/// 非ハイライト行はCanvas transformで縮小するのみ——fontSizeは不変。
const double _kBaseFontSize = 26.0;

// スケール比（= 見た目上のfontSize / _kBaseFontSize）
const double _kScaleHighlighted = 1.000;
const double _kScaleNear        = 19.0 / _kBaseFontSize; // ≈ 0.731
const double _kScaleNormal      = 17.0 / _kBaseFontSize; // ≈ 0.654

// 不透明度
const double _kOpacityHighlighted = 1.00;
const double _kOpacityNear        = 0.60;
const double _kOpacityNormal      = 0.28;

// 上下パディング
const double _kVertPadHighlighted = 14.0;
const double _kVertPadOther       =  7.0;

const double _kHorizontalPadding  = 32.0;
const Duration _kAnimDuration     = Duration(milliseconds: 380);
const Curve _kAnimCurve           = Curves.easeInOutCubic;

// ═══════════════════════════════════════════════════════════════
// LYRIC LINE STATE
// ═══════════════════════════════════════════════════════════════

enum _LyricLineState { highlighted, near, normal }

// ═══════════════════════════════════════════════════════════════
// SANITIZER
// ═══════════════════════════════════════════════════════════════

abstract final class _LyricSanitizer {
  static String clean(String raw) => raw
      .replaceAll('\r\n', ' ')
      .replaceAll('\r', '')       // ← \r をキャリッジリターンとして解釈するバグを根絶
      .replaceAll('\n', ' ')
      .replaceAll('\u200B', '')   // ZERO WIDTH SPACE
      .replaceAll('\u200C', '')   // ZERO WIDTH NON-JOINER
      .replaceAll('\u200D', '')   // ZERO WIDTH JOINER
      .replaceAll('\uFEFF', '')   // BOM
      .replaceAll('\u00A0', ' ')  // NO-BREAK SPACE → 通常スペース（禁則処理誤爆防止）
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
}

// ═══════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════

class LyricView extends ConsumerStatefulWidget {
  const LyricView({super.key});

  @override
  ConsumerState<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends ConsumerState<LyricView> {
  // ── scrollable_positioned_list controllers ──────────────────
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener = ItemPositionsListener.create();

  int _lastHighlightedIndex = -1;
  String? _lastSongId;
  bool _isInitialScroll = true; // 初回はアニメーションなしで即ジャンプ

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(audioPlayerProvider);
    final notifier    = ref.read(audioPlayerProvider.notifier);
    final lyrics      = playerState.currentSong?.lyrics ?? [];
    final currentIdx  = playerState.currentLyricIndex;
    final songId      = playerState.currentSong?.id;

    // 曲が変わったらスクロール状態をリセット
    if (songId != _lastSongId) {
      _lastSongId           = songId;
      _lastHighlightedIndex = -1;
      _isInitialScroll      = true;
    }

    // ハイライト行が変わったらスクロール命令をpost
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
      // ─────────────────────────────────────────────────────────
      // 【課題2の核心】
      // ScrollablePositionedList は offset ベースではなく
      // index ベースでスクロール位置を管理する。
      // scrollTo(index, alignment: 0.5) は:
      //   1. 対象 index のアイテムを仮想リストの先頭に置いた
      //      サブリストを構築し直す
      //   2. alignment=0.5 でそのアイテムをビューポート中央に配置
      // → 上にある複数行の高さが一斉に変動しても計算がずれない
      // ─────────────────────────────────────────────────────────
      itemCount: lyrics.length,
      itemScrollController: _scrollController,
      itemPositionsListener: _positionsListener,
      padding: EdgeInsets.symmetric(
        vertical: MediaQuery.of(context).size.height * 0.40,
        horizontal: _kHorizontalPadding,
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
      alignment: 0.5, // ビューポートの中央に配置
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

// ═══════════════════════════════════════════════════════════════
// LYRIC LINE ITEM
// ═══════════════════════════════════════════════════════════════

class _LyricLineItem extends StatelessWidget {
  const _LyricLineItem({
    required this.lyricLine,
    required this.state,
    required this.onTap,
  });

  final LyricLine lyricLine;
  final _LyricLineState state;
  final VoidCallback onTap;

  double get _targetScale => switch (state) {
    _LyricLineState.highlighted => _kScaleHighlighted,
    _LyricLineState.near        => _kScaleNear,
    _LyricLineState.normal      => _kScaleNormal,
  };

  double get _targetOpacity => switch (state) {
    _LyricLineState.highlighted => _kOpacityHighlighted,
    _LyricLineState.near        => _kOpacityNear,
    _LyricLineState.normal      => _kOpacityNormal,
  };

  double get _targetVertPad =>
      state == _LyricLineState.highlighted ? _kVertPadHighlighted : _kVertPadOther;

  @override
  Widget build(BuildContext context) {
    final text = lyricLine.text.isEmpty ? '・' : _LyricSanitizer.clean(lyricLine.text);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: _AnimatedLyricBox(
        text: text,
        scale: _targetScale,
        opacity: _targetOpacity,
        verticalPadding: _targetVertPad,
        duration: _kAnimDuration,
        curve: _kAnimCurve,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ANIMATED LYRIC BOX  (ImplicitlyAnimatedWidget)
// ═══════════════════════════════════════════════════════════════
//
// forEachTween により、state が変わるたびに
// 「現在の補間途中の値 → 新ターゲット」へ正確に再アニメーションされる。
// scale / opacity / verticalPadding は完全独立したTweenで補間。
//
// ═══════════════════════════════════════════════════════════════

class _AnimatedLyricBox extends ImplicitlyAnimatedWidget {
  const _AnimatedLyricBox({
    required this.text,
    required this.scale,
    required this.opacity,
    required this.verticalPadding,
    required super.duration,
    super.curve = Curves.linear,
  });

  final String text;
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
      _scaleTween,
      widget.scale,
      (v) => Tween<double>(begin: v as double),
    ) as Tween<double>?;

    _opacityTween = visitor(
      _opacityTween,
      widget.opacity,
      (v) => Tween<double>(begin: v as double),
    ) as Tween<double>?;

    _vertPadTween = visitor(
      _vertPadTween,
      widget.verticalPadding,
      (v) => Tween<double>(begin: v as double),
    ) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    final scale   = _scaleTween?.evaluate(animation)   ?? widget.scale;
    final opacity = _opacityTween?.evaluate(animation) ?? widget.opacity;
    final vertPad = _vertPadTween?.evaluate(animation) ?? widget.verticalPadding;

    // グロー影: scale が _kScaleHighlighted に近づくほど強くなる
    final glowT = ((scale - _kScaleNormal) / (_kScaleHighlighted - _kScaleNormal))
        .clamp(0.0, 1.0);
    final shadowAlpha = glowT * 0.38;

    return _LyricScaleBox(
      text: widget.text,
      scale: scale,
      color: Colors.white.withValues(alpha: opacity),
      shadows: shadowAlpha > 0.01
          ? [Shadow(color: Colors.white.withValues(alpha: shadowAlpha), blurRadius: 14)]
          : const [],
      verticalPadding: vertPad,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// _LyricScaleBox  (LeafRenderObjectWidget)
// ═══════════════════════════════════════════════════════════════

class _LyricScaleBox extends LeafRenderObjectWidget {
  const _LyricScaleBox({
    required this.text,
    required this.scale,
    required this.color,
    required this.shadows,
    required this.verticalPadding,
  });

  final String text;
  final double scale;
  final Color color;
  final List<Shadow> shadows;
  final double verticalPadding;

  @override
  _RenderLyricScaleBox createRenderObject(BuildContext context) {
    return _RenderLyricScaleBox(
      text: text,
      scale: scale,
      color: color,
      shadows: shadows,
      verticalPadding: verticalPadding,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, _RenderLyricScaleBox renderObject) {
    // 各 setter が変化があった場合のみ markNeedsLayout / markNeedsPaint を呼ぶ
    renderObject
      ..text           = text
      ..scale          = scale
      ..color          = color
      ..shadows        = shadows
      ..verticalPadding = verticalPadding;
  }
}

// ═══════════════════════════════════════════════════════════════
// _RenderLyricScaleBox  (カスタム RenderBox)
// ═══════════════════════════════════════════════════════════════
//
// 【レイアウトの仕組み】
//   performLayout() では常に _kBaseFontSize(26sp) でテキストを測定する。
//   報告するサイズは:
//     width  = constraints.maxWidth   （常に親幅いっぱい）
//     height = (textPainterHeight + vertPad*2) * scale
//   → scale が小さくなると高さも縮む → ゴーストスペース消滅
//
// 【描画の仕組み】
//   paint() では Canvas にスケール変換を適用する:
//     1. レイアウトボックスの中心へ移動
//     2. scale 変換（縮小）
//     3. フルサイズコンテンツボックスの左上へ戻す
//     4. テキストを垂直パディングつきで描画
//   → フォントサイズは変わらず、Canvas 上でスケールダウン → リフロー完全消滅
//
// ═══════════════════════════════════════════════════════════════

class _RenderLyricScaleBox extends RenderBox {
  _RenderLyricScaleBox({
    required String text,
    required double scale,
    required Color color,
    required List<Shadow> shadows,
    required double verticalPadding,
  })  : _text           = text,
        _scale          = scale,
        _color          = color,
        _shadows        = List.from(shadows),
        _verticalPadding = verticalPadding {
    _rebuildPainter();
  }

  // ── Fields ──────────────────────────────────────

  String          _text;
  double          _scale;
  Color           _color;
  List<Shadow>    _shadows;
  double          _verticalPadding;
  late TextPainter _painter;

  // ── Setters ─────────────────────────────────────

  set text(String v) {
    if (_text == v) return;
    _text = v;
    _rebuildPainter();
    markNeedsLayout();
  }

  set scale(double v) {
    if (_scale == v) return;
    _scale = v;
    markNeedsLayout(); // 高さが変わる
  }

  set color(Color v) {
    if (_color == v) return;
    _color = v;
    _rebuildPainter();
    markNeedsPaint(); // レイアウトには影響しない
  }

  set shadows(List<Shadow> v) {
    _shadows = List.from(v);
    _rebuildPainter();
    markNeedsPaint();
  }

  set verticalPadding(double v) {
    if (_verticalPadding == v) return;
    _verticalPadding = v;
    markNeedsLayout();
  }

  // ── TextPainter 構築 ─────────────────────────────
  //
  // fontSizeは常に _kBaseFontSize 固定。
  // これがリフロー消滅の根拠: テキストの折り返し判定が不変。
  //
  void _rebuildPainter() {
    _painter = TextPainter(
      text: TextSpan(
        text: _text,
        style: TextStyle(
          color: _color,
          fontSize: _kBaseFontSize, // ← 絶対に変えない
          fontWeight: FontWeight.w700,
          height: 1.55,
          letterSpacing: 0.15,
          shadows: _shadows,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      textWidthBasis: TextWidthBasis.parent, // 折り返し最終行も確実に中央揃え
      strutStyle: const StrutStyle(forceStrutHeight: true, leading: 0.3),
    );
  }

  // ── Layout ───────────────────────────────────────

  @override
  void performLayout() {
    final maxW = constraints.maxWidth;
    _painter.layout(maxWidth: maxW);
    final rawH = _painter.height + _verticalPadding * 2;
    size = Size(maxW, rawH * _scale);
  }

  // ── Paint ────────────────────────────────────────

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_scale <= 0.0) return;

    final canvas = context.canvas;
    final rawH   = _painter.height + _verticalPadding * 2;

    canvas.save();

    // ① スケール後のレイアウトボックス中心へ移動
    canvas.translate(
      offset.dx + size.width / 2,
      offset.dy + size.height / 2,
    );

    // ② スケール変換 (フォントサイズは変えず、canvas上で縮小)
    canvas.scale(_scale);

    // ③ フルサイズコンテンツボックスの左上へ戻す
    canvas.translate(-size.width / 2, -rawH / 2);

    // ④ テキストを垂直パディングつきで描画
    _painter.paint(canvas, Offset(0.0, _verticalPadding));

    canvas.restore();
  }

  // ── Intrinsic sizes ──────────────────────────────

  @override
  double computeMinIntrinsicHeight(double width) {
    _painter.layout(maxWidth: width.isFinite ? width : 9999.0);
    return (_painter.height + _verticalPadding * 2) * _scale;
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double computeMinIntrinsicWidth(double height) => 0.0;

  @override
  double computeMaxIntrinsicWidth(double height) => _kBaseFontSize * 20;

  @override
  bool hitTestSelf(Offset position) => true;
}

// ═══════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════

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
            style: TextStyle(
              color: AppColors.textDisabled,
              fontSize: 16,
              height: 1.6,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'LRCファイルを追加して歌詞を表示しましょう',
            style: TextStyle(
              color: AppColors.textDisabled,
              fontSize: 13,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
