// ============================================================
// widgets/lyric_view.dart
// 歌詞表示ウィジェット
//
// [修正内容 - 2025]
// 1. TweenAnimationBuilder(begin==end) を AnimatedOpacity/AnimatedScale/
//    AnimatedDefaultTextStyle に刷新 → 正しい補間アニメーション
// 2. height: 1.5 → 1.9 (iOS Hiragino Sans のディセンダー保護)
// 3. 各行に bottomPadding を追加してクリップを物理的に防止
// 4. Opacity ウィジェットを除去して Metal コンポジットレイヤー問題を解消
// 5. デバッグオーバーレイ追加（歌詞画面を長押しで ON/OFF）
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/lyric_line.dart';
import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';

// ── 定数 ────────────────────────────────────────────────────
const double _kHorizontalPadding = 24.0;
const Duration _kAnimDuration    = Duration(milliseconds: 400);
const Curve    _kAnimCurve       = Curves.easeOutCubic;

/// 歌詞テキストの基準フォントサイズ。
/// Transform.scale で見た目だけを縮小するため、常にこのサイズで描画する。
const double _kBaseFontSize = 32.0;

/// ディセンダー（ー, ぱ 等の下突き出し）がクリップされないよう、
/// iOS Hiragino Sans の実測メトリクスに合わせて十分な行間を確保する。
/// height: 1.5 → 1.9 に変更。
const double _kLineHeight = 1.9;

/// スケール縮小時の視覚的な下端余白。
/// Transform.scale は layout サイズを変えないため、縮小後に
/// 「本来の layout 下端」より内側に収まるが、
/// iOS フォントのサブピクセルレンダリングで1〜2px はみ出すことがある。
/// これを吸収するための追加パディング。
const double _kDescenderGuard = 6.0;

// ── 歌詞行の状態 ────────────────────────────────────────────
enum _LyricLineState { highlighted, near, normal }

// ── 文字列サニタイザ ─────────────────────────────────────────
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

// ════════════════════════════════════════════════════════════
// LyricView（メイン）
// ════════════════════════════════════════════════════════════
class LyricView extends ConsumerStatefulWidget {
  const LyricView({super.key});

  @override
  ConsumerState<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends ConsumerState<LyricView> {
  final ItemScrollController  _scrollController  = ItemScrollController();
  final ItemPositionsListener _positionsListener = ItemPositionsListener.create();

  int    _lastHighlightedIndex = -1;
  String? _lastSongId;
  bool   _isInitialScroll = true;

  // ── デバッグオーバーレイ制御 ──────────────────────────────
  bool _debugMode = false;

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

    // ハイライト行が変わったら自動スクロール
    if (currentIdx != _lastHighlightedIndex &&
        currentIdx >= 0 &&
        currentIdx < lyrics.length) {
      _lastHighlightedIndex = currentIdx;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToIndex(currentIdx);
      });
    }

    if (lyrics.isEmpty) return const _EmptyLyricView();

    return GestureDetector(
      // 長押しでデバッグオーバーレイを ON/OFF
      onLongPress: kDebugMode
          ? () => setState(() => _debugMode = !_debugMode)
          : null,
      child: Stack(
        children: [
          ScrollablePositionedList.builder(
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
              final lineState = _resolveState(index, currentIdx);
              return _LyricLineItem(
                key: ValueKey('lyric_$index'),
                lyricLine: lyrics[index],
                state: lineState,
                debugMode: _debugMode,
                onTap: () => notifier.seekTo(lyrics[index].position),
              );
            },
          ),

          // ── デバッグオーバーレイ ──────────────────────────
          if (_debugMode && kDebugMode)
            _DebugOverlay(
              currentIndex: currentIdx,
              totalLines: lyrics.length,
              songId: songId,
            ),
        ],
      ),
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

// ════════════════════════════════════════════════════════════
// _LyricLineItem
//
// ── 修正ポイント ──
// Before: TweenAnimationBuilder(begin: target, end: target)
//         → begin == end のため補間ゼロ。即座ジャンプ + 文字崩壊
//
// After : AnimatedOpacity   → opacity を正しく補間
//         AnimatedScale      → scale を正しく補間
//         AnimatedDefaultTextStyle → shadow を正しく補間
//
// ── クリップ修正 ──
// height: 1.5 → _kLineHeight(1.9)
// bottom padding に _kDescenderGuard(6px) を追加
// ════════════════════════════════════════════════════════════
class _LyricLineItem extends StatelessWidget {
  const _LyricLineItem({
    super.key,
    required this.lyricLine,
    required this.state,
    required this.onTap,
    this.debugMode = false,
  });

  final LyricLine       lyricLine;
  final _LyricLineState state;
  final VoidCallback    onTap;
  final bool            debugMode;

  @override
  Widget build(BuildContext context) {
    final text = lyricLine.text.isEmpty
        ? '♪'
        : _LyricSanitizer.clean(lyricLine.text);

    final isHigh = state == _LyricLineState.highlighted;
    final isNear = state == _LyricLineState.near;

    // スケール比（layout サイズは固定 _kBaseFontSize=32px）
    final double targetScale = isHigh
        ? 1.0
        : (isNear ? 28.0 / _kBaseFontSize : 24.0 / _kBaseFontSize);

    // 不透明度
    final double targetOpacity = isHigh ? 1.0 : (isNear ? 0.55 : 0.38);

    // 上下パディング
    // bottom に _kDescenderGuard を加算してディセンダーの下端が
    // リストアイテムの境界でクリップされるのを防ぐ
    final double topPad    = isHigh ? 16.0 : 8.0;
    final double bottomPad = (isHigh ? 16.0 : 8.0) + _kDescenderGuard;

    // テキストスタイル（シャドウだけ状態によって変わる）
    final TextStyle targetStyle = TextStyle(
      color: Colors.white,
      fontSize: _kBaseFontSize,
      fontWeight: FontWeight.w800,
      height: _kLineHeight,
      letterSpacing: -0.3,
      // シャドウはハイライト時のみ
      shadows: isHigh
          ? [Shadow(
              color: Colors.white.withValues(alpha: 0.3),
              blurRadius: 16,
            )]
          : const [],
    );

    Widget child = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedPadding(
        duration: _kAnimDuration,
        curve: _kAnimCurve,
        padding: EdgeInsets.only(top: topPad, bottom: bottomPad),
        child: AnimatedOpacity(
          opacity: targetOpacity,
          duration: _kAnimDuration,
          curve: _kAnimCurve,
          // ──────────────────────────────────────────────────
          // AnimatedScale は内部で Matrix4 を使い、
          // 新しいコンポジットレイヤーを強制しない。
          // Opacity ウィジェット (旧実装) はレイヤーを強制し、
          // iOS Metal で文字崩壊の原因となっていた。
          // ──────────────────────────────────────────────────
          child: AnimatedScale(
            scale: targetScale,
            duration: _kAnimDuration,
            curve: _kAnimCurve,
            alignment: Alignment.centerLeft,
            child: AnimatedDefaultTextStyle(
              style: targetStyle,
              duration: _kAnimDuration,
              curve: _kAnimCurve,
              child: Text(
                text,
                textAlign: TextAlign.left,
                // 万一 layout を超えても「硬くクリップ」しない
                overflow: TextOverflow.visible,
                softWrap: false,
              ),
            ),
          ),
        ),
      ),
    );

    // デバッグ時：各行のバウンディングボックスを赤枠で表示
    if (debugMode && kDebugMode) {
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red.withValues(alpha: 0.6), width: 1),
                ),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                color: Colors.red.withValues(alpha: 0.8),
                child: Text(
                  'sc:${targetScale.toStringAsFixed(2)} '
                  'op:${targetOpacity.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return child;
  }
}

// ════════════════════════════════════════════════════════════
// デバッグオーバーレイパネル
// kDebugMode == true (デバッグビルド) のときのみ表示される。
// 画面長押しで ON/OFF。
// ════════════════════════════════════════════════════════════
class _DebugOverlay extends StatelessWidget {
  const _DebugOverlay({
    required this.currentIndex,
    required this.totalLines,
    required this.songId,
  });

  final int     currentIndex;
  final int     totalLines;
  final String? songId;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      right: 8,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.yellow, width: 1),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.yellow,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
              fontFamily: 'monospace',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('── LyricView DEBUG ──'),
                Text('songId   : ${songId ?? "null"}'),
                Text('lyricIdx : $currentIndex / $totalLines'),
                Text('fontSize : $_kBaseFontSize'),
                Text('height   : $_kLineHeight'),
                Text('guard    : $_kDescenderGuard px'),
                Text('animMs   : ${_kAnimDuration.inMilliseconds}'),
                const SizedBox(height: 4),
                const Text('■ 赤枠 = 各行のlayout box'),
                const Text('■ sc = scale, op = opacity'),
                const Text('長押しで非表示'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 歌詞なし表示
// ════════════════════════════════════════════════════════════
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