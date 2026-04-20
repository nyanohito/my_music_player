// ============================================================
// widgets/lyric_view.dart
// 歌詞の自動スクロール＆ハイライト表示ウィジェット
// ============================================================
//
// 【UI改善ポイント】
//   1. 行間・余白: TextStyle.height + 縦 Padding でゆったりした呼吸感
//   2. ハイライト: AnimatedDefaultTextStyle + AnimatedContainer で
//                  サイズ・不透明度・テキスト影が滑らかにアニメーション
//   3. 折り返し:   水平 Padding 32px + softWrap + 中央揃えで
//                  長いフレーズが美しく折り返される
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
///
/// 折り返しが発生すると実際の高さはこれより大きくなりますが、
/// スクロール先の「目安」として使うため厳密な一致は不要です。
const double _kItemBaseHeight = 72.0;

/// 水平方向の内側余白（長いフレーズの折り返し制御）
const double _kHorizontalPadding = 32.0;

/// アニメーション時間
const Duration _kAnimDuration = Duration(milliseconds: 350);

/// アニメーション曲線
const Curve _kAnimCurve = Curves.easeInOutCubic;

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
      // ────────────────────────────────────────────────────
      // 【改善 3】上下に大きなパディングを設けることで
      //   現在行が常に画面の中央付近に来やすくなります。
      //   値は viewportHeight の 40% 程度が Spotify 近似です。
      // ────────────────────────────────────────────────────
      padding: EdgeInsets.symmetric(
        vertical: MediaQuery.of(context).size.height * 0.40,
        horizontal: _kHorizontalPadding, // ← 左右余白をここで一括指定
      ),
      itemBuilder: (context, index) {
        final state = _resolveState(index, currentIndex);
        return _LyricLineItem(
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

    final viewportHeight = _scrollController.position.viewportDimension;
    final topPadding = viewportHeight * 0.40;

    // 中央に合わせるオフセット計算
    final targetOffset = topPadding +
        (index * _kItemBaseHeight) -
        (viewportHeight / 2) +
        (_kItemBaseHeight / 2);

    _scrollController.animateTo(
      targetOffset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
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
    required this.lyricLine,
    required this.state,
    required this.onTap,
  });

  // ────────────────────────────────────────────
  // 【改善 2】状態ごとのスタイル定義
  //
  //  highlighted : 白・26sp・Bold・影付き → 「歌っている感」
  //  near        : 半透明白・19sp・w500  → 視線誘導のための中間層
  //  normal      : 低透明白・17sp・w400  → 背景に溶け込む
  // ────────────────────────────────────────────
  (Color, double, FontWeight, double) get _style => switch (state) {
        _LyricLineState.highlighted => (
            Colors.white,
            26.0,
            FontWeight.w700,
            1.55, // TextStyle.height（行間係数）
          ),
        _LyricLineState.near => (
            Colors.white.withValues(alpha: 0.55),
            19.0,
            FontWeight.w500,
            1.6,
          ),
        _LyricLineState.normal => (
            Colors.white.withValues(alpha: 0.30),
            17.0,
            FontWeight.w400,
            1.6,
          ),
      };

  List<Shadow> get _shadows => state == _LyricLineState.highlighted
      ? [
          Shadow(
            color: Colors.white.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: Offset.zero,
          ),
        ]
      : [];

  @override
  Widget build(BuildContext context) {
    final (color, fontSize, fontWeight, lineHeight) = _style;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: // ────────────────────────────────────────────
          // 【改善 1】上下 Padding で行間の「呼吸」を確保。
          //   highlighted 行は大きめのパディングでさらに目立たせます。
          // ────────────────────────────────────────────
          AnimatedPadding(
        duration: _kAnimDuration,
        curve: _kAnimCurve,
        padding: EdgeInsets.symmetric(
          vertical: state == _LyricLineState.highlighted ? 12.0 :7.0,
        ),
        child: AnimatedDefaultTextStyle(
          duration: _kAnimDuration,
          curve: _kAnimCurve,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: fontWeight,
            // ──────────────────────────────────────────
            // 【改善 1】height で行間を拡張（1.55〜1.6）。
            //   デフォルト（≈1.2）より広く設定することで
            //   折り返し行でも窮屈に見えなくなります。
            // ──────────────────────────────────────────
            height: lineHeight,
            letterSpacing: state == _LyricLineState.highlighted ? 0.2 : 0.0,
            shadows: _shadows,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              lyricLine.text.isEmpty ? '・' : lyricLine.text,
              textAlign: TextAlign.center,
              // ────────────────────────────────────────
              // 【改善 3】softWrap + maxLines なしで
              //   長いフレーズが自然に折り返されます。
              //   横 Padding は ListView の padding で
              //   一括指定しているため、ここでは不要です。
              // ────────────────────────────────────────
              softWrap: true,
            ),
          ),
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
