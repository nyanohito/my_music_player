// ============================================================
// widgets/lyric_view.dart  — v4 完全書き直し
// ============================================================
//
// ■ これまでの問題の根本原因
//
//   ① カスタム RenderBox の strutStyle(forceStrutHeight: true, leading: 0.2) が
//     TextStyle.height: 1.45 の行間を強制上書きし、
//     日本語の縦スペースを圧縮していた（全状態で潰れる原因）。
//
//   ② computeMinIntrinsicHeight() が同一の _painter に
//     異なる maxWidth で layout() を呼び、
//     その後 performLayout() に使われる painter の状態を汚染していた。
//
//   ③ _painter.debugDisposed はデバッグビルド専用プロパティであり
//     リリースビルドで意図通りに動作しない。
//
// ■ 新アーキテクチャ：カスタム RenderBox を全廃
//
//   カスタム RenderBox の代わりに、Flutter 標準ウィジェットの組み合わせで
//   「リフローなし・ゴーストスペースなし・クリップなし」を実現する:
//
//     SizedBox(height: rawH × scale)          … リストへの高さ申告
//     └─ ClipRect                             … 視覚オーバーフロー防止
//        └─ OverflowBox(maxHeight: rawH)      … 子がフルサイズで描画できる余地
//           └─ Transform.scale(topLeft)       … 視覚縮小（フォントサイズ不変）
//              └─ SizedBox(h: rawH, w: maxW)  … フルサイズコンテナ
//                 └─ Padding(vertical: pad)
//                    └─ RichText(32sp, left)  … 実テキスト
//
//   【なぜこれで潰れないか】
//     fontSizeは常に32sp固定 → TextPainterの折り返し判定が絶対に変わらない。
//     Transform.scale はキャンバスを縮小するだけなのでリフローゼロ。
//     SizedBox(height: rawH×scale) が高さを申告するのでゴーストスペースゼロ。
//     OverflowBox が rawH の描画空間を確保するのでクリップゼロ。
//
// ■ pubspec.yaml に必要なパッケージ:
//     scrollable_positioned_list: ^0.3.8
//
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/lyric_line.dart';
import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════

/// 全行共通の基準フォントサイズ。絶対に変更しない。
/// 非ハイライト行は Transform.scale で縮小するのみ。
const double _kBaseFontSize = 32.0;

// ─── スケール比 ──────────────────────────────────────────────
const double _kScaleHighlighted = 1.000;                  // 32sp 相当
const double _kScaleNear        = 28.0 / _kBaseFontSize;  // 28sp 相当
const double _kScaleNormal      = 24.0 / _kBaseFontSize;  // 24sp 相当

// ─── 不透明度 ────────────────────────────────────────────────
const double _kOpacityHighlighted = 1.00;
const double _kOpacityNear        = 0.55;
const double _kOpacityNormal      = 0.38;

// ─── 縦パディング ────────────────────────────────────────────
const double _kVertPadHighlighted = 16.0;
const double _kVertPadOther       =  8.0;

// ─── 左右余白 ────────────────────────────────────────────────
const double _kHorizontalPadding = 24.0;

const Duration _kAnimDuration = Duration(milliseconds: 400);
const Curve    _kAnimCurve    = Curves.easeInOutCubic;

/// テキスト高さ測定用スタイル（RichText の描画スタイルと完全一致させること）
const TextStyle _kMeasureStyle = TextStyle(
  fontSize:      _kBaseFontSize,
  fontWeight:    FontWeight.w700,
  height:        1.5,    // 行間係数: デフォルト(≈1.2) より広め
  letterSpacing: -0.3,
  // color は測定に不要なので省略
);

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
      .replaceAll('\r', '')
      .replaceAll('\n', ' ')
      .replaceAll('\u200B', '')   // ZERO WIDTH SPACE
      .replaceAll('\u200C', '')   // ZERO WIDTH NON-JOINER
      .replaceAll('\u200D', '')   // ZERO WIDTH JOINER
      .replaceAll('\uFEFF', '')   // BOM
      .replaceAll('\u00A0', ' ')  // NO-BREAK SPACE
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
        key:      ValueKey('${songId}_$index'),
        lyricLine: lyrics[index],
        state:    _resolveState(index, currentIdx),
        onTap:    () => notifier.seekTo(lyrics[index].position),
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

// ═══════════════════════════════════════════════════════════════
// _LyricLineItem  (StatefulWidget)
// ═══════════════════════════════════════════════════════════════
//
// StatefulWidget にする理由:
//   テキスト高さの測定結果をキャッシュし、
//   lyric 行が再ビルドされても TextPainter.layout() を毎回呼ばないため。
//   幅が変化したとき（端末回転等）のみ再測定する。
//
// ═══════════════════════════════════════════════════════════════

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
  double _naturalHeight = _kBaseFontSize * 1.5; // 初期値フォールバック（1行分相当）

  /// テキストを _kBaseFontSize で描画したときの高さを測定する。
  /// 前回と同じ幅なら測定をスキップしてキャッシュを返す。
  double _measureNaturalHeight(double maxWidth, String text) {
    if ((maxWidth - _cachedWidth).abs() < 0.5) return _naturalHeight;

    final tp = TextPainter(
      text:           TextSpan(text: text, style: _kMeasureStyle),
      textDirection:  TextDirection.ltr,
      textAlign:      TextAlign.left,
      textWidthBasis: TextWidthBasis.parent,
    )..layout(maxWidth: maxWidth);

    _cachedWidth   = maxWidth;
    _naturalHeight = tp.height;
    tp.dispose(); // リソース解放
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
          // 幅が変化したときのみ TextPainter.layout() を再実行する
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

// ═══════════════════════════════════════════════════════════════
// _AnimatedLyricBox  (ImplicitlyAnimatedWidget)
// ═══════════════════════════════════════════════════════════════
//
// scale / opacity / verticalPadding を独立した Tween で補間する。
// forEachTween により「アニメーション途中で state が変わっても
// 現在の補間値から新ターゲットへ再アニメーション」が保証される。
//
// ═══════════════════════════════════════════════════════════════

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
  final double naturalHeight;   // _kMeasureStyle で測定したテキスト高さ
  final double availableWidth;  // LayoutBuilder から取得した利用可能幅
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

    // フルサイズ（scale=1.0 時）のアイテム高さ
    final rawH = widget.naturalHeight + vertPad * 2;

    // ハイライト度合いに応じてグロー影を強める（0.0〜1.0）
    final glowT = ((scale - _kScaleNormal) /
        (_kScaleHighlighted - _kScaleNormal)).clamp(0.0, 1.0);

    return SizedBox(
      // ────────────────────────────────────────────────────────────
      // ① SizedBox(height: rawH * scale)
      //    ScrollablePositionedList のリストアイテムに「この行の高さ」を伝える。
      //    scale が 0.75 なら高さも 75% → ゴーストスペース消滅。
      // ────────────────────────────────────────────────────────────
      height: rawH * scale,
      child: ClipRect(
        // ──────────────────────────────────────────────────────────
        // ② ClipRect
        //    SizedBox の境界（rawH * scale）を超えた視覚コンテンツを切り捨てる。
        //    Transform.scale が正確に縮小するのでクリップは発生しないが
        //    万一の浮動小数点誤差を吸収する安全網。
        // ──────────────────────────────────────────────────────────
        child: OverflowBox(
          // ────────────────────────────────────────────────────────
          // ③ OverflowBox(maxHeight: rawH)
          //    子ウィジェットが「フルサイズ rawH」でレイアウトできるよう許可する。
          //    SizedBox は rawH*scale しか割り当てていないが、
          //    OverflowBox がそれを超えた制約を子に渡す。
          //    Transform.scale が縮小するので視覚的には境界内に収まる。
          // ────────────────────────────────────────────────────────
          alignment:  Alignment.topLeft,
          minHeight:  0,
          maxHeight:  rawH,
          minWidth:   0,
          maxWidth:   widget.availableWidth,
          child: Transform.scale(
            // ──────────────────────────────────────────────────────
            // ④ Transform.scale(scale, Alignment.topLeft)
            //    フォントサイズは 32sp 固定のまま、キャンバスだけを縮小する。
            //    → テキストの折り返し判定が一切変わらない = リフロー完全消滅
            //    Alignment.topLeft: 左端・上端を起点にスケール
            //    → 横ブレなし（前回の「ウネウネ」バグ修正済み）
            // ──────────────────────────────────────────────────────
            scale:     scale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width:  widget.availableWidth,
              height: rawH,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: vertPad),
                child: RichText(
                  // ────────────────────────────────────────────────
                  // ⑤ RichText (DefaultTextStyle を参照しない)
                  //    Text ウィジェットは DefaultTextStyle(InheritedWidget) を
                  //    参照するため、アニメーション中のスタイル継承が
                  //    レイアウト計算と競合する場合がある。
                  //    RichText は TextSpan.style のみを参照するため安全。
                  //
                  //    fontSize: _kBaseFontSize  ← 絶対に変えない
                  //    height: 1.5              ← strutStyle なし・シンプルな行間
                  //    strutStyle は使用しない  ← forceStrutHeight が行間を
                  //                               圧縮していた原因を根絶
                  // ────────────────────────────────────────────────
                  text: TextSpan(
                    text:  widget.text,
                    style: TextStyle(
                      color:         Colors.white.withValues(alpha: opacity),
                      fontSize:      _kBaseFontSize, // ← 絶対に変えない
                      fontWeight:    FontWeight.w700,
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
                  textAlign:      TextAlign.left,           // Spotify スタイル
                  textWidthBasis: TextWidthBasis.parent,    // 折り返し最終行も確実に左揃え
                  textDirection:  TextDirection.ltr,
                  softWrap:       true,
                  overflow:       TextOverflow.visible,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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