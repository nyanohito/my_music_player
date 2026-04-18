// ============================================================
// screens/now_playing_screen.dart
// ★ 再生画面：アルバムアート・歌詞・再生コントロール
// ============================================================

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:audio_session/audio_session.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/lyric_view.dart';
import '../models/lyric_line.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  double _playbackSpeed = 1.0;
  double _volume = 1.0;

  // ★ BugFix: Color は非 null 型のため「== null チェック」は常に false。
  //   代わりに「最後に色を抽出した曲 ID」で変化を検知する。
  Color _dominantColor = const Color(0xFF1E1E2E);
  String? _lastExtractedSongId;

  final ScrollController _inlineScrollController = ScrollController();

  // ──────────────────────────────────────────────────────────
  // ドミナントカラー抽出（曲 ID が変わったときだけ実行）
  // ──────────────────────────────────────────────────────────

  Future<void> _maybeExtractDominantColor(
      String songId, Uint8List? imageBytes) async {
    if (_lastExtractedSongId == songId) return;
    _lastExtractedSongId = songId;

    if (imageBytes == null) {
      if (mounted) setState(() => _dominantColor = const Color(0xFF1E1E2E));
      return;
    }

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(imageBytes),
        maximumColorCount: 8,
      );
      final extracted = palette.darkVibrantColor?.color ??
          palette.vibrantColor?.color ??
          palette.dominantColor?.color ??
          const Color(0xFF1E1E2E);
      if (mounted) setState(() => _dominantColor = extracted);
    } catch (_) {
      if (mounted) setState(() => _dominantColor = const Color(0xFF1E1E2E));
    }
  }

  // ──────────────────────────────────────────────────────────
  // 現在の歌詞インデックス（インライン用）
  // ──────────────────────────────────────────────────────────

  int _getCurrentLyricIndex(List<LyricLine> lyrics, Duration position) {
    for (int i = 0; i < lyrics.length; i++) {
      if (lyrics[i].position > position) return i > 0 ? i - 1 : 0;
    }
    return lyrics.isNotEmpty ? lyrics.length - 1 : 0;
  }

  // ──────────────────────────────────────────────────────────
  // 再生速度ボトムシート
  // ──────────────────────────────────────────────────────────

  void _showAudioSettingsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '再生速度: ${_playbackSpeed.toStringAsFixed(1)}x',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Slider(
                  value: _playbackSpeed,
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  activeColor: AppColors.accent,
                  inactiveColor: AppColors.surfaceVariant,
                  onChanged: (v) => setModalState(() => _playbackSpeed = v),
                  onChangeEnd: (v) {
                    setState(() => _playbackSpeed = v);
                    ref.read(audioPlayerProvider.notifier).player.setSpeed(v);
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('閉じる'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // ★ フルスクリーン歌詞モーダル（Spotify カラオケ UI）
  // ──────────────────────────────────────────────────────────

  void _showLyricsFullScreen(BuildContext context) {
    final darkBase = Color.lerp(_dominantColor, Colors.black, 0.65) ?? Colors.black;
    final darkerBase = Color.lerp(_dominantColor, Colors.black, 0.88) ?? Colors.black;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        maxChildSize: 1.0,
        minChildSize: 0.5,
        builder: (context, _) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [darkBase, darkerBase, Colors.black],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: SafeArea(
              child: _FullScreenLyricsSheet(dominantColor: _dominantColor),
            ),
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // iOS 出力先ピッカー
  // ──────────────────────────────────────────────────────────

  void _showAudioRoutePicker(BuildContext context) async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('iOSの設定で出力先を変更してください'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('出力先の変更に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ──────────────────────────────────────────────────────────
  // ★ インライン歌詞カード（再生画面下部）
  // ──────────────────────────────────────────────────────────

  Widget _buildInlineLyricsCard(List<LyricLine> lyrics) {
    final cardBg = Color.lerp(
      _dominantColor.withValues(alpha: 0.55),
      Colors.black,
      0.58,
    )!;

    return GestureDetector(
      onTap: () => _showLyricsFullScreen(context),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー: 「Lyrics」(左上) + 拡大アイコン(右上)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Lyrics',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                Icon(
                  Icons.open_in_full,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 15,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 歌詞プレビュー（現在行 + 周辺数行）
            SizedBox(
              height: 116,
              child: StreamBuilder<Duration>(
                stream: ref.read(audioPlayerProvider.notifier).positionStream,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? Duration.zero;
                  final ci = _getCurrentLyricIndex(lyrics, position);

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_inlineScrollController.hasClients && ci > 0) {
                      _inlineScrollController.animateTo(
                        (ci * 29.0).clamp(
                          _inlineScrollController.position.minScrollExtent,
                          _inlineScrollController.position.maxScrollExtent,
                        ),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  });

                  return ListView.builder(
                    controller: _inlineScrollController,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: lyrics.length,
                    itemExtent: 29,
                    itemBuilder: (context, index) {
                      if (index < ci - 1 || index > ci + 2) {
                        return const SizedBox.shrink();
                      }
                      final isCurrent = index == ci;
                      return Text(
                        lyrics[index].text.isEmpty ? '・' : lyrics[index].text,
                        style: TextStyle(
                          color: isCurrent
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.38),
                          fontSize: isCurrent ? 15 : 13,
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.normal,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // build
  // ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(audioPlayerProvider);
    final notifier = ref.read(audioPlayerProvider.notifier);
    final currentSong = playerState.currentSong;

    if (currentSong == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(
          child: Text('Playback Screen',
              style: TextStyle(color: AppColors.textPrimary)),
        ),
      );
    }

    // 曲 ID が変わったときだけドミナントカラーを再抽出
    _maybeExtractDominantColor(currentSong.id, currentSong.albumArt);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _dominantColor.withValues(alpha: 0.85),
              _dominantColor.withValues(alpha: 0.4),
              Colors.black,
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── App Bar ─────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down,
                          color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text(
                      'Now Playing',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings,
                          color: Colors.white, size: 24),
                      onPressed: () =>
                          _showAudioSettingsBottomSheet(context),
                    ),
                  ],
                ),
              ),

              // ── Main Content ─────────────────────────────
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isSmallScreen = constraints.maxHeight < 600;
                    return SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                          horizontal: constraints.maxWidth * 0.08),
                      child: Column(
                        children: [
                          SizedBox(height: isSmallScreen ? 8 : 24),

                          // ── アルバムアートワーク ──────────
                          Container(
                            width: constraints.maxWidth * 0.78,
                            height: constraints.maxWidth * 0.78,
                            constraints: const BoxConstraints(
                                maxWidth: 340, maxHeight: 340),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: _dominantColor
                                      .withValues(alpha: 0.55),
                                  blurRadius: 45,
                                  offset: const Offset(0, 22),
                                  spreadRadius: -4,
                                ),
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.5),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: currentSong.albumArt != null
                                  ? Image.memory(currentSong.albumArt!,
                                      fit: BoxFit.cover)
                                  : Container(
                                      color: AppColors.surfaceVariant,
                                      child: Icon(
                                        Icons.music_note,
                                        size: 80,
                                        color: _dominantColor
                                            .withValues(alpha: 0.8),
                                      ),
                                    ),
                            ),
                          ),

                          SizedBox(height: isSmallScreen ? 16 : 32),

                          // ── 曲情報 ───────────────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20),
                            child: Column(
                              children: [
                                Text(
                                  currentSong.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                // UI でも Unknown Artist を二重ガード
                                Text(
                                  () {
                                    final a = currentSong.artist ?? '';
                                    return (a.isEmpty ||
                                            a
                                                .toLowerCase()
                                                .contains('unknown'))
                                        ? 'Mrs. GREEN APPLE'
                                        : a;
                                  }(),
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.7),
                                    fontSize: 18,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: isSmallScreen ? 16 : 28),

                          // ── プログレスバー ────────────────
                          StreamBuilder<Duration>(
                            stream: notifier.positionStream,
                            builder: (context, snapshot) {
                              final position =
                                  snapshot.data ?? Duration.zero;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                                child: ProgressBar(
                                  progress: position,
                                  total:
                                      playerState.duration ?? position,
                                  progressBarColor: Colors.white,
                                  baseBarColor: Colors.white
                                      .withValues(alpha: 0.3),
                                  thumbColor: Colors.white,
                                  timeLabelTextStyle: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.7),
                                    fontSize: 12,
                                  ),
                                  onSeek: (d) => notifier.seekTo(d),
                                ),
                              );
                            },
                          ),

                          SizedBox(height: isSmallScreen ? 16 : 24),

                          // ── 再生コントロール ──────────────
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: Icon(Icons.shuffle,
                                    color:
                                        playerState.isShuffleModeEnabled
                                            ? Colors.white
                                            : Colors.white
                                                .withValues(alpha: 0.5)),
                                onPressed: notifier.toggleShuffle,
                              ),
                              IconButton(
                                icon: const Icon(Icons.skip_previous,
                                    size: 36, color: Colors.white),
                                onPressed: notifier.playPrevious,
                              ),
                              Container(
                                decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white),
                                child: IconButton(
                                  icon: Icon(
                                    playerState.isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    size: 40,
                                    color: Colors.black,
                                  ),
                                  onPressed: notifier.togglePlayPause,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.skip_next,
                                    size: 36, color: Colors.white),
                                onPressed: notifier.playNext,
                              ),
                              IconButton(
                                icon: Icon(Icons.repeat,
                                    color:
                                        playerState.repeatMode !=
                                                PlaylistMode.off
                                            ? Colors.white
                                            : Colors.white
                                                .withValues(alpha: 0.5)),
                                onPressed: notifier.toggleRepeat,
                              ),
                            ],
                          ),

                          SizedBox(height: isSmallScreen ? 8 : 16),

                          // ── 音量スライダー ────────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16),
                            child: Column(
                              children: [
                                Text(
                                  '音量: ${(_volume * 100).toInt()}%',
                                  style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.7),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Slider(
                                  value: _volume,
                                  min: 0.0,
                                  max: 1.0,
                                  divisions: 20,
                                  activeColor: Colors.white,
                                  inactiveColor: Colors.white
                                      .withValues(alpha: 0.3),
                                  onChanged: (v) {
                                    setState(() => _volume = v);
                                    notifier.player.setVolume(v);
                                  },
                                ),
                              ],
                            ),
                          ),

                          if (Platform.isIOS) ...[
                            SizedBox(height: isSmallScreen ? 4 : 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.speaker_group,
                                      color: Colors.white),
                                  onPressed: () =>
                                      _showAudioRoutePicker(context),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Output',
                                  style: TextStyle(
                                      color: Colors.white
                                          .withValues(alpha: 0.7),
                                      fontSize: 14),
                                ),
                              ],
                            ),
                          ],

                          SizedBox(height: isSmallScreen ? 8 : 16),

                          // ★ インライン歌詞カード（歌詞がある場合のみ表示）
                          if (currentSong.lyrics.isNotEmpty)
                            _buildInlineLyricsCard(currentSong.lyrics),

                          const SizedBox(height: 16),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _inlineScrollController.dispose();
    super.dispose();
  }
}

// ============================================================
// ★ フルスクリーン歌詞シート（内部 StatefulWidget）
//   動的スクロール ⇔ 静的全文 のトグルを持つ
// ============================================================

class _FullScreenLyricsSheet extends ConsumerStatefulWidget {
  final Color dominantColor;
  const _FullScreenLyricsSheet({required this.dominantColor});

  @override
  ConsumerState<_FullScreenLyricsSheet> createState() =>
      _FullScreenLyricsSheetState();
}

class _FullScreenLyricsSheetState
    extends ConsumerState<_FullScreenLyricsSheet> {
  // false = 動的スクロール（Spotify カラオケ）
  // true  = 静的全文表示
  bool _isStaticMode = false;

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(audioPlayerProvider).currentSong;
    final lyrics = song?.lyrics ?? [];

    return Column(
      children: [
        // ── ドラッグハンドル ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // ── ヘッダー：曲名 + モード切替 + 閉じる ───────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  song?.title ?? '',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // ★ 動的 ⇔ 静的 トグル
              Tooltip(
                message: _isStaticMode ? '動的歌詞に切り替え' : '静的歌詞に切り替え',
                child: IconButton(
                  icon: Icon(
                    _isStaticMode ? Icons.sync : Icons.text_snippet,
                    color: Colors.white54,
                    size: 22,
                  ),
                  onPressed: () =>
                      setState(() => _isStaticMode = !_isStaticMode),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down,
                    color: Colors.white38, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),

        // ── 歌詞エリア ────────────────────────────────────────
        Expanded(
          child: _isStaticMode
              ? _StaticLyricsView(
                  lyrics: lyrics, dominantColor: widget.dominantColor)
              : _DynamicLyricsView(lyrics: lyrics),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
// ★ 動的歌詞ビュー（Spotify カラオケ UI）
// ──────────────────────────────────────────────────────────────

class _DynamicLyricsView extends ConsumerStatefulWidget {
  final List<LyricLine> lyrics;
  const _DynamicLyricsView({required this.lyrics});

  @override
  ConsumerState<_DynamicLyricsView> createState() =>
      _DynamicLyricsViewState();
}

class _DynamicLyricsViewState extends ConsumerState<_DynamicLyricsView> {
  final ScrollController _sc = ScrollController();
  int _lastIndex = -1;
  static const double _lineH = 56.0;

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  void _scrollTo(int index) {
    if (!_sc.hasClients || index < 0) return;
    final vp = _sc.position.viewportDimension;
    final topPad = vp * 0.35;
    final target =
        topPad + index * _lineH - vp / 2 + _lineH / 2;
    _sc.animateTo(
      target.clamp(
          _sc.position.minScrollExtent, _sc.position.maxScrollExtent),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(audioPlayerProvider);
    final notifier = ref.read(audioPlayerProvider.notifier);
    final lyrics = widget.lyrics;
    final currentIndex = playerState.currentLyricIndex;

    if (currentIndex != _lastIndex && currentIndex >= 0) {
      _lastIndex = currentIndex;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollTo(currentIndex));
    }

    if (lyrics.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lyrics_outlined, color: Colors.white24, size: 52),
            SizedBox(height: 16),
            Text('歌詞がありません',
                style: TextStyle(color: Colors.white38, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _sc,
      itemCount: lyrics.length,
      padding: EdgeInsets.symmetric(
        vertical: MediaQuery.of(context).size.height * 0.3,
        horizontal: 28,
      ),
      itemBuilder: (context, index) {
        final isCurrent = index == currentIndex;
        final isNear = (index - currentIndex).abs() == 1;

        return GestureDetector(
          onTap: () => notifier.seekTo(lyrics[index].position),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            style: TextStyle(
              // ★ 現在行 → 純白・Bold・26pt
              // ★ 隣接行 → 白42%
              // ★ 遠い行  → 白25%
              color: isCurrent
                  ? Colors.white
                  : isNear
                      ? Colors.white.withValues(alpha: 0.42)
                      : Colors.white.withValues(alpha: 0.25),
              fontSize: isCurrent ? 26.0 : 22.0,
              fontWeight:
                  isCurrent ? FontWeight.bold : FontWeight.w500,
              height: 1.5,
            ),
            child: SizedBox(
              height: _lineH,
              width: double.infinity,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  lyrics[index].text.isEmpty ? '・' : lyrics[index].text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────
// ★ 静的歌詞ビュー（全文スクロール）
// ──────────────────────────────────────────────────────────────

class _StaticLyricsView extends ConsumerWidget {
  final List<LyricLine> lyrics;
  final Color dominantColor;

  const _StaticLyricsView(
      {required this.lyrics, required this.dominantColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(audioPlayerProvider.notifier);

    if (lyrics.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lyrics_outlined, color: Colors.white24, size: 52),
            SizedBox(height: 16),
            Text('歌詞がありません',
                style: TextStyle(color: Colors.white38, fontSize: 16)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lyrics.map((lyric) {
          return GestureDetector(
            onTap: () => notifier.seekTo(lyric.position),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                lyric.text.isEmpty ? '・' : lyric.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  height: 1.6,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}