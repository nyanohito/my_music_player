import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:audio_session/audio_session.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';
import '../utils/database_helper.dart';
import '../widgets/lyric_view.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  double _playbackSpeed = 1.0;
  double _pitch = 0.0;
  Color? _dominantColor;

  Future<Color> _extractDominantColor(Uint8List? imageBytes) async {
    if (imageBytes == null) return AppColors.background;
    
    try {
      final paletteGenerator = PaletteGenerator.fromImageProvider(
        MemoryImage(imageBytes),
      );
      final palette = await paletteGenerator.generate();
      
      if (palette.colors.isNotEmpty) {
        return palette.colors.first.color;
      }
    } catch (e) {
      print('Failed to extract dominant color: $e');
    }
    
    return AppColors.background;
  }

  void _showAudioSettingsBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 再生速度
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
                onChanged: (value) {
                  setState(() => _playbackSpeed = value);
                  // TODO: just_audioで再生速度を適用
                },
              ),
              const SizedBox(height: 24),
              
              // ピッチ（キー）
              Text(
                'ピッチ: ${_pitch.toStringAsFixed(1)}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Slider(
                value: _pitch,
                min: -6.0,
                max: 6.0,
                divisions: 12,
                activeColor: AppColors.accent,
                inactiveColor: AppColors.surfaceVariant,
                onChanged: (value) {
                  setState(() => _pitch = value);
                  // TODO: just_audioでピッチを適用
                },
              ),
              const SizedBox(height: 24),
              
              // 閉じるボタン
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

void _showLyricsFullScreen(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.black,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 1.0,
      minChildSize: 0.5,
      builder: (context, scrollController) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ヘッダー
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '歌詞',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // 歌詞全文
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: playerState.currentSong?.lyrics.map((lyric) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      lyric.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.6,
                      ),
                    ),
                  )).toList() ?? [],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _showAudioRoutePicker(BuildContext context) async {
    try {
      final session = await AudioSession.instance;
      // iOSの出力先切り替えダイアログを表示
      await session.setActive(true);
      // 注：audio_sessionパッケージには直接のルートピッカー機能がないため
      // 将来的にはPlatform.isIOSの場合に特別な実装が必要
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('iOSの設定で出力先を変更してください'),
          backgroundColor: AppColors.accent,
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(audioPlayerProvider);
    final notifier = ref.read(audioPlayerProvider.notifier);
    final currentSong = playerState.currentSong;

    if (currentSong == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: Text('再生中の曲はありません', style: TextStyle(color: AppColors.textPrimary))),
      );
    }

    // アートワークからドミナントカラーを抽出
    if (_dominantColor == null && currentSong.albumArt != null) {
      _extractDominantColor(currentSong.albumArt).then((color) {
        if (mounted) {
          setState(() => _dominantColor = color);
        }
      });
    }

    return Scaffold(
      backgroundColor: _dominantColor ?? AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('再生中', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, color: AppColors.textPrimary),
            onPressed: () => _showAudioSettingsBottomSheet(context),
            tooltip: '音質・再生設定',
          ),
        ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxHeight < 600;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: constraints.maxWidth * 0.08),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: isSmallScreen ? 10 : 30),
                // アートワーク
                Container(
                  width: constraints.maxWidth * 0.8,
                  height: constraints.maxWidth * 0.8,
                  constraints: const BoxConstraints(maxWidth: 360, maxHeight: 360),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
                  ),
                  child: currentSong.albumArt != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.memory(currentSong.albumArt!, fit: BoxFit.cover),
                        )
                      : Container(
                          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
                          child: const Icon(Icons.music_note_rounded, size: 80, color: AppColors.textDisabled),
                        ),
                ),
                SizedBox(height: isSmallScreen ? 20 : 40),
                
                // 曲名＆アーティスト名 ＆ チェックマーク ＆ お気に入り
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentSong.title,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currentSong.artist,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis
                          ),
                        ],
                      ),
                    ),
                    // 🌟 プレイリスト追加済みチェックマーク
                    FutureBuilder<bool>(
                      future: DatabaseHelper().isSongInAnyPlaylist(currentSong.id),
                      builder: (context, snapshot) {
                        if (snapshot.data == true) {
                          return const Padding(
                            padding: EdgeInsets.only(right: 12.0),
                            child: Icon(Icons.check_circle, color: AppColors.accent, size: 24),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    // 🌟 お気に入りボタン
                    IconButton(
                      icon: Icon(
                        currentSong.isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: currentSong.isFavorite ? Colors.red : AppColors.textSecondary
                      ),
                      onPressed: () => notifier.toggleFavorite(currentSong.id),
                    ),
                  ],
                ),
                SizedBox(height: isSmallScreen ? 10 : 20),
                
                // プログレスバー
                StreamBuilder<Duration>(
                  stream: notifier.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    return ProgressBar(
                      progress: position,
                      total: playerState.duration ?? position,
                      progressBarColor: AppColors.accent,
                      baseBarColor: AppColors.surface,
                      thumbColor: AppColors.accent,
                      timeLabelTextStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      onSeek: (duration) => notifier.seekTo(duration),
                    );
                  },
                ),
                SizedBox(height: isSmallScreen ? 10 : 20),
                
                // 歌詞表示
                if (currentSong.lyrics.isNotEmpty)
                  Container(
                    height: 120,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: LyricView(),
                  ),
                
                // 歌詞カードと拡張ボタン
                if (currentSong.lyrics.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        // 歌詞プレビューカード
                        Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: (_dominantColor ?? AppColors.surface).withOpacity(0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '歌詞プレビュー',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.9),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        currentSong.lyrics.take(3).map((lyric) => lyric.text).join(' '),
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.7),
                                          fontSize: 11,
                                          height: 1.4,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.fullscreen, color: Colors.white.withValues(alpha: 0.9)),
                                onPressed: () => _showLyricsFullScreen(context),
                                tooltip: '歌詞を全画面表示',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                SizedBox(height: isSmallScreen ? 20 : 30),
                
                // 出力先変更ボタン
                if (Platform.isIOS)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.speaker_group, color: AppColors.textSecondary),
                          onPressed: () => _showAudioRoutePicker(context),
                          tooltip: '出力先を変更',
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          '出力先',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                SizedBox(height: isSmallScreen ? 10 : 20),
                
                // コントロールボタン
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: Icon(Icons.shuffle, color: playerState.isShuffleModeEnabled ? AppColors.accent : AppColors.textSecondary),
                      onPressed: notifier.toggleShuffle,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous, size: 36, color: AppColors.textPrimary),
                      onPressed: notifier.playPrevious
                    ),
                    Container(
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      child: IconButton(
                        icon: Icon(playerState.isPlaying ? Icons.pause : Icons.play_arrow, size: 40, color: Colors.black),
                        onPressed: notifier.togglePlayPause,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, size: 36, color: AppColors.textPrimary),
                      onPressed: notifier.playNext
                    ),
                    IconButton(
                      icon: Icon(Icons.repeat, color: playerState.repeatMode != PlaylistMode.off ? AppColors.accent : AppColors.textSecondary),
                      onPressed: notifier.toggleRepeat,
                    ),
                  ],
                ),
                SizedBox(height: isSmallScreen ? 20 : 30),
                
                // 音量スライダー（PC向け、目立たなく配置）
                Opacity(
                  opacity: 0.7,
                  child: Row(
                    children: [
                      const Icon(Icons.volume_down, color: AppColors.textSecondary, size: 18),
                      Expanded(
                        child: StreamBuilder<double>(
                          stream: notifier.volumeStream,
                          builder: (context, snapshot) {
                            return Slider(
                              value: snapshot.data ?? 1.0,
                              onChanged: notifier.setVolume,
                              activeColor: AppColors.accent,
                              inactiveColor: AppColors.surface,
                            );
                          }
                        )
                      ),
                      const Icon(Icons.volume_up, color: AppColors.textSecondary, size: 18),
                    ],
                  ),
                ),
                SizedBox(height: isSmallScreen ? 20 : 40),
                
                // リアルタイム歌詞表示
                SizedBox(
                  height: constraints.maxHeight * 0.4, // 画面の高さの40%を歌詞エリアにする
                  child: const LyricView(),
                ),
                SizedBox(height: isSmallScreen ? 20 : 40),
              ],
            ),
          );
        },
      ),
    );
  }
}