// ============================================================
// widgets/lyric_view.dart
// 歌詞の自動スクロール＆ハイライト表示ウィジェット
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lyric_line.dart';
import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';

/// 歌詞リストを表示し、現在の歌詞行を自動スクロール＆ハイライトする
class LyricView extends ConsumerStatefulWidget {
  const LyricView({super.key});

  @override
  ConsumerState<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends ConsumerState<LyricView> {
  final ScrollController _scrollController = ScrollController();

  // 各行のアイテム高さ（スクロール位置の計算に使用）
  static const double _itemHeight = 52.0;

  // 前回のハイライト行インデックス（変化があった時だけスクロール）
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

    // ハイライト行が変わったらスクロール
    if (currentIndex != _lastHighlightedIndex && currentIndex >= 0) {
      _lastHighlightedIndex = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentLyric(currentIndex, lyrics.length);
      });
    }

    // 歌詞がない場合の表示
    if (lyrics.isEmpty) {
      return const _EmptyLyricView();
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: lyrics.length,
      // 上下に余白を設けて、現在行が画面中央に来やすくする
      padding: EdgeInsets.symmetric(
        vertical: MediaQuery.of(context).size.height * 0.25,
      ),
      itemBuilder: (context, index) {
        return InkWell(
          onTap: () {
            // タップで歌詞のタイムスタンプへシーク
            notifier.seekTo(lyrics[index].position);
          },
          child: _LyricLineItem(
            lyricLine: lyrics[index],
            state: _getLineState(index, currentIndex),
          ),
        );
      },
    );
  }

  /// 現在の行を画面中央にスムーズスクロール
  void _scrollToCurrentLyric(int index, int totalLines) {
    if (!_scrollController.hasClients) return;

    // ビューポート高さの半分を引いて「画面中央」に持ってくる
    final viewportHeight = _scrollController.position.viewportDimension;
    final topPadding = viewportHeight * 0.25;

    final targetOffset =
        topPadding + (index * _itemHeight) - (viewportHeight / 2) + (_itemHeight / 2);

    _scrollController.animateTo(
      targetOffset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  /// インデックスに応じて行の表示状態を返す
  _LyricLineState _getLineState(int index, int currentIndex) {
    if (currentIndex < 0) return _LyricLineState.normal;
    if (index == currentIndex) return _LyricLineState.highlighted;
    if ((index - currentIndex).abs() <= 1) return _LyricLineState.near;
    return _LyricLineState.normal;
  }
}

// ─────────────────────────────────────────────
// 歌詞行の表示状態
// ─────────────────────────────────────────────

enum _LyricLineState { highlighted, near, normal }

// ─────────────────────────────────────────────
// 1行分の歌詞ウィジェット
// ─────────────────────────────────────────────

class _LyricLineItem extends StatelessWidget {
  final LyricLine lyricLine;
  final _LyricLineState state;

  const _LyricLineItem({
    required this.lyricLine,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final (color, fontSize, fontWeight) = switch (state) {
      _LyricLineState.highlighted => (
          AppColors.lyricHighlight,
          18.0,
          FontWeight.bold,
        ),
      _LyricLineState.near => (
          AppColors.lyricNear,
          15.0,
          FontWeight.w500,
        ),
      _LyricLineState.normal => (
          AppColors.lyricDefault,
          14.0,
          FontWeight.normal,
        ),
    };

    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: 1.6,
      ),
      child: SizedBox(
        height: _LyricViewState._itemHeight,
        child: Center(
          child: Text(
            lyricLine.text.isEmpty ? '・' : lyricLine.text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
            style: TextStyle(color: AppColors.textDisabled, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'LRCファイルを追加して歌詞を表示しましょう',
            style: TextStyle(color: AppColors.textDisabled, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
