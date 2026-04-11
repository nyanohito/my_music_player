import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';
import '../utils/database_helper.dart';
import '../widgets/lyric_view.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('再生中', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        centerTitle: true,
      ),
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