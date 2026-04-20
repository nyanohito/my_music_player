// ============================================================
// widgets/lyric_view.dart
// 歌詞の自動スクロール＆ハイライト表示ウィジェット
// ============================================================
//
// 【修正履歴 - テキスト中央揃え崩れの根本解決】
//
//   ■ 原因①（最有力）: LRC の \r による "幽霊キャリッジリターン"
//     LRCファイルの行末が \r\n の場合、パーサーが \n で分割すると
//     各行末に \r が残存します。trim() は行末の \r を除去しますが、
//     ゼロ幅スペース等の制御文字は除去しません。
//     テキストレンダラーが \r をキャリッジリターンとして解釈し
//     「最後の文字が行頭に描画される」バグが発生。
//     → _LyricSanitizer.clean() で完全除去。
//
//   ■ 原因②（構造的）: AnimatedDefaultTextStyle の継承パス問題
//     AnimatedDefaultTextStyle は DefaultTextStyle (InheritedWidget) 経由で
//     スタイルを伝播させます。アニメーション中の fontSize 補間 →
//     DefaultTextStyle 更新 → Text の intrinsic width 再計算 というサイクルが
//     LayoutBuilder の constraint 解決より先に走ることがあり、
//     レイアウトパスの不整合を起こします。
//     → TweenAnimationBuilder<TextStyle> + RichText に置き換え。
//       RichText は DefaultTextStyle を一切参照しないため継承チェーン問題が根絶。
//
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lyric_line.dart';
import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────
// 定数
// ─────────────────────────────────────────────

/// ハイライト行の推定高さ（スクロール位置計算用）
const double _kItemBaseHeight = 72.0;

/// 水平方向の内側余白（長いフレーズの折り返し制御）
const double _kHorizontalPadding = 32.0;

/// アニメーション時間
const Duration _kAnimDuration = Duration(milliseconds: 350);

/// アニメーション曲線
const Curve _kAnimCurve = Curves.easeInOutCubic;

// ─────────────────────────────────────────────
// LRC テキストのサニタイザ
// ─────────────────────────────────────────────

/// LRC ファイル由来の文字列に含まれる制御文字・ゼロ幅文字を完全除去する。
///
/// Flutter のテキストレンダラーは \r をキャリッジリターンとして解釈するため、
/// 行末に \r が残っていると「最後の文字が行頭に描画される」バグが発生する。
abstract final class _LyricSanitizer {
  static String clean(String raw) => raw
      // ① CRLF を単一スペースに置換（改行を折り返しでなく空白として扱う）
      .replaceAll('\r\n', ' ')
      // ② 残存する単独 CR / LF を除去
      .replaceAll('\r', '')
      .replaceAll('\n', ' ')
      // ③ ゼロ幅文字群（LRC タグの残骸として混入することがある）
      .replaceAll('\u200B', '') // ZERO WIDTH SPACE
      .replaceAll('\u200C', '') // ZERO WIDTH NON-JOINER
      .replaceAll('\u200D', '') // ZERO WIDTH JOINER
      .replaceAll('\uFEFF', '') // BOM / ZERO WIDTH NO-BREAK SPACE
      // ④ NO-BREAK SPACE → 通常スペース（禁則処理の誤爆を防ぐ）
      .replaceAll('\u00A0', ' ')
      // ⑤ 連続スペースを1つに正規化
      .replaceAll(RegExp(r' {2,}'), ' ')
      // ⑥ 前後の空白を除去
      .trim();
}

// ─────────────────────────────────────────────
// 歌詞行の表示状態
// ─────────────────────────────────────────────

enum _LyricLineState {
  /// 現在再生中の行
  highlighted,

  /// ハイライト行の直前・直後（±1）
  near,

  /// それ以外
  normal,
}

// ─────────────────────────────────────────────
// LyricView（メインウィジェット）
// ─────────────────────────────────────────────

/// 歌詞リストを表示し、現在の歌詞行を自動スクロール＆ハイライトする。
///
/// バックエンド（Riverpod / AudioPlayer）は一切変更しません。
class LyricView extends ConsumerStatefulWidget {
  const LyricView({super.key});

  @override
  ConsumerState<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends ConsumerState<LyricView> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _currentLyricKey = GlobalKey();
  int _lastHighlightedIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(audioPlayerProvider);
    final notifier = ref.read(audioPlayerProvider.notifier);
    final lyrics = playerState.currentSong?.lyrics ?? [];
    final currentIndex = playerState.currentLyricIndex;

    // ハイライト行が変わったときだけスクロール
    if (currentIndex != _lastHighlightedIndex &&
        currentIndex >= 0 &&
        currentIndex < lyrics.length) {
      _lastHighlightedIndex = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentLyric(currentIndex);
      });
    }

    if (lyrics.isEmpty) {
      return const _EmptyLyricView();
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: lyrics.length,
      padding: EdgeInsets.symmetric(
        vertical: MediaQuery.of(context).size.height * 0.40,
        horizontal: _kHorizontalPadding,
      ),
      itemBuilder: (context, index) {
        final state = _resolveState(index, currentIndex);
        return _LyricLineItem(
          key: index == currentIndex ? _currentLyricKey : null,
          lyricLine: lyrics[index],
          state: state,
          onTap: () => notifier.seekTo(lyrics[index].position),
        );
      },
    );
  }

  /// 現在の行を画面中央へスムーズスクロール
  void _scrollToCurrentLyric(int index) {
    if (!_scrollController.hasClients) return;

    final currentContext = _currentLyricKey.currentContext;
    if (currentContext != null) {
      Scrollable.ensureVisible(
        currentContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      // フォールバック: 概算値でジャンプして次フレームで再試行
      final viewportHeight = _scrollController.position.viewportDimension;
      final topPadding = viewportHeight * 0.40;
      final targetOffset = topPadding +
          (index * _kItemBaseHeight) -
          (viewportHeight / 2) +
          (_kItemBaseHeight / 2);

      _scrollController.jumpTo(
        targetOffset.clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        ),
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final retryContext = _currentLyricKey.currentContext;
        if (retryContext != null) {
          Scrollable.ensureVisible(
            retryContext,
            alignment: 0.5,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  /// インデックスから表示状態を解決
  _LyricLineState _resolveState(int index, int currentIndex) {
    if (currentIndex < 0) return _LyricLineState.normal;
    if (index == currentIndex) return _LyricLineState.highlighted;
    if ((index - currentIndex).abs() <= 1) return _LyricLineState.near;
    return _LyricLineState.normal;
  }
}

// ─────────────────────────────────────────────
// 1行分の歌詞ウィジェット
// ─────────────────────────────────────────────

class _LyricLineItem extends StatelessWidget {
  final LyricLine lyricLine;
  final _LyricLineState state;
  final VoidCallback onTap;

  const _LyricLineItem({
    super.key,
    required this.lyricLine,
    required this.state,
    required this.onTap,
  });

  // ── 状態ごとのターゲットスタイル ────────────────
  //
  // 1. フォントサイズは全て26.0に固定
  TextStyle get _targetTextStyle => switch (state) {
        _LyricLineState.highlighted => TextStyle(
            color: Colors.white,
            fontSize: 26.0,
            fontWeight: FontWeight.w700,
            height: 1.55,
            letterSpacing: 0.2,
            shadows: [
              Shadow(
                color: Colors.white.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: Offset.zero,
              ),
            ],
          ),
        _LyricLineState.near => TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 26.0,
            fontWeight: FontWeight.w500,
            height: 1.6,
            letterSpacing: 0.0,
            shadows: const [],
          ),
        _LyricLineState.normal => TextStyle(
            color: Colors.white.withValues(alpha: 0.30),
            fontSize: 26.0,
            fontWeight: FontWeight.w400,
            height: 1.6,
            letterSpacing: 0.0,
            shadows: const [],
          ),
       };

  @Override
  Widget build(BuildContext context) {
    // ── サニタイズ ──────────────────────────────────
    // 空行は視覚的な区切りとして「・」を表示
    final text = lyricLine.text.isEmpty
        ? '・'
        : _LyricSanitizer.clean(lyricLine.text);

    // 2. スケール値の定義
    final targetScale = switch (state) {
      _LyricLineState.highlighted => 1.0,
      _LyricLineState.near => 19.0 / 26.0,
      _LyricLineState.normal => 17.0 / 26.0,
    };

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedPadding(
        // 上下余白のアニメーションは AnimatedPadding で問題なし（レイアウト非依存）
        duration: _kAnimDuration,
        curve: _kAnimCurve,
        padding: EdgeInsets.symmetric(
          vertical: state == _LyricLineState.highlighted ? 12.0 : 7.0,
        ),
        child: TweenAnimationBuilder<TextStyle>(
          // ──────────────────────────────────────────────────────
          // 【修正】AnimatedDefaultTextStyle → TweenAnimationBuilder
          //
          // TextStyleTween(end: ...) を指定すると、state が変わるたびに
          // 「現在の補間値 → 新しいターゲット」へ自動的に再アニメーションします。
          // スタイルを DefaultTextStyle 経由ではなく RichText に直接渡すため、
          // InheritedWidget の伝播タイミングに依存しません。
          // ──────────────────────────────────────────────────────
          tween: TextStyleTween(end: _targetTextStyle),
          duration: _kAnimDuration,
          curve: _kAnimCurve,
          builder: (context, animatedStyle, _) {
            // 3. Scaleアニメーションの追加
            return TweenAnimationBuilder<double>(
              tween: Tween<double>(end: targetScale),
              duration: _kAnimDuration,
              curve: _kAnimCurve,
              builder: (context, scale, _) {
                return Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: double.infinity,
                    child: RichText(
                      // ──────────────────────────────────────────────
                      // 【修正】Text → RichText
                      //
                      // RichText は DefaultTextStyle を一切参照しません。
                      // animatedStyle を TextSpan に直接渡すため、
                      // アニメーション中のスタイル補間と幅計算が
                      // 完全に独立した単一のレイアウトパスで処理されます。
                      // ──────────────────────────────────────────────
                      text: TextSpan(
                        text: text,
                        style: animatedStyle,
                      ),
                      textAlign: TextAlign.center,
                      // ──────────────────────────────────────────────
                      // textWidthBasis.parent:「最長行の幅」ではなく
                      // 「親から渡された制約幅（= SizedBox の width）」を基準にします。
                      // これにより折り返し最終行の1文字でも
                      // 必ず親幅の中央に配置されます。
                      // ──────────────────────────────────────────────
                      textWidthBasis: TextWidthBasis.parent,
                      // テキスト方向を明示（自動判定による禁則処理の誤爆を防ぐ）
                      textDirection: TextDirection.ltr,
                      softWrap: true,
                      overflow: TextOverflow.visible,
                      strutStyle: const StrutStyle(
                        forceStrutHeight: true, // 日本語の行高ブレを抑制
                        leading: 0.3,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 歌詞がない場合のプレースホルダー
// ─────────────────────────────────────────────

class _EmptyLyricView extends StatelessWidget {
  const _EmptyLyricView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lyrics_outlined,
            color: AppColors.textDisabled,
            size: 48,
          ),
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