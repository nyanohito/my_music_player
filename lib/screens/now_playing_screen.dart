import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:audio_session/audio_session.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';
import '../utils/database_helper.dart';
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
  Color _dominantColor = AppColors.background;
  final ScrollController _scrollController = ScrollController();

  Future<Color> _extractDominantColor(Uint8List? imageBytes) async {
    if (imageBytes == null) return AppColors.background;
    
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(imageBytes),
      );
      
      if (palette.colors.isNotEmpty) {
        return palette.colors.first;
      }
    } catch (e) {
      print('Failed to extract dominant color: $e');
    }
    
    return AppColors.background;
  }

  int _getCurrentLyricIndex(List<LyricLine> lyrics, Duration position) {
    for (int i = 0; i < lyrics.length; i++) {
      if (lyrics[i].position > position) {
        return i > 0 ? i - 1 : 0;
      }
    }
    return lyrics.isNotEmpty ? lyrics.length - 1 : 0;
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
                },
                onChangeEnd: (value) {
                  ref.read(audioPlayerProvider.notifier).player.setSpeed(value);
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
  final playerState = ref.read(audioPlayerProvider);
  
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 1.0,
      minChildSize: 0.5,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF81C784),
              const Color(0xFF4A7C59),
              const Color(0xFF2D4A2B),
            ],
            stops: const [0.0, 0.6, 1.0],
          ),
        ),
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
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: const LyricView(),
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
        body: const Center(child: Text('Playback Screen', style: TextStyle(color: AppColors.textPrimary))),
      );
    }

    // Extract dominant color from album art
    if (_dominantColor == null && currentSong.albumArt != null) {
      _extractDominantColor(currentSong.albumArt).then((color) {
        if (mounted) {
          setState(() => _dominantColor = color);
        }
      });
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _dominantColor?.withValues(alpha: 0.8) ?? AppColors.background,
              _dominantColor?.withValues(alpha: 0.4) ?? AppColors.background,
              Colors.black,
            ],
            stops: const [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text(
                      'Now Playing',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings, color: Colors.white, size: 24),
                      onPressed: () => _showAudioSettingsBottomSheet(context),
                      tooltip: 'Audio Settings',
                    ),
                  ],
                ),
              ),
              
              // Main Content
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isSmallScreen = constraints.maxHeight < 600;
                    return SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: constraints.maxWidth * 0.08),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: isSmallScreen ? 10 : 30),
                          
                          // Album Artwork
                          Container(
                            width: constraints.maxWidth * 0.8,
                            height: constraints.maxWidth * 0.8,
                            constraints: const BoxConstraints(maxWidth: 360, maxHeight: 360),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 30,
                                  offset: const Offset(0, 15),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: currentSong.albumArt != null
                                  ? Image.memory(
                                      currentSong.albumArt!,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: AppColors.surfaceVariant,
                                      child: const Icon(
                                        Icons.music_note,
                                        size: 80,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                            ),
                          ),
                          
                          SizedBox(height: isSmallScreen ? 20 : 40),
                          
                          // Song Info
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
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
                                Text(
                                  currentSong.artist,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 18,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          
                          SizedBox(height: isSmallScreen ? 20 : 30),
                          
                          // Progress Bar
                          StreamBuilder<Duration>(
                            stream: notifier.positionStream,
                            builder: (context, snapshot) {
                              final position = snapshot.data ?? Duration.zero;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: ProgressBar(
                                  progress: position,
                                  total: playerState.duration ?? position,
                                  progressBarColor: Colors.white,
                                  baseBarColor: Colors.white.withValues(alpha: 0.3),
                                  thumbColor: Colors.white,
                                  timeLabelTextStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                                  onSeek: (duration) => notifier.seekTo(duration),
                                ),
                              );
                            },
                          ),
                          
                          SizedBox(height: isSmallScreen ? 20 : 30),
                          
                          // Control Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: Icon(Icons.shuffle, color: playerState.isShuffleModeEnabled ? Colors.white : Colors.white.withValues(alpha: 0.5)),
                                onPressed: notifier.toggleShuffle,
                              ),
                              IconButton(
                                icon: const Icon(Icons.skip_previous, size: 36, color: Colors.white),
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
                                icon: const Icon(Icons.skip_next, size: 36, color: Colors.white),
                                onPressed: notifier.playNext
                              ),
                              IconButton(
                                icon: Icon(Icons.repeat, color: playerState.repeatMode != PlaylistMode.off ? Colors.white : Colors.white.withValues(alpha: 0.5)),
                                onPressed: notifier.toggleRepeat,
                              ),
                            ],
                          ),
                          
                          SizedBox(height: isSmallScreen ? 10 : 20),
                          
                          // Volume Control
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              children: [
                                Text(
                                  '音量: ${(_volume * 100).toInt()}%',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
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
                                  inactiveColor: Colors.white.withValues(alpha: 0.3),
                                  onChanged: (value) {
                                    setState(() => _volume = value);
                                    ref.read(audioPlayerProvider.notifier).player.setVolume(value);
                                  },
                                ),
                              ],
                            ),
                          ),
                          
                          SizedBox(height: isSmallScreen ? 10 : 20),
                          
                          // Output Button (iOS only)
                          if (Platform.isIOS)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.speaker_group, color: Colors.white),
                                  onPressed: () => _showAudioRoutePicker(context),
                                  tooltip: 'Change Output',
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Output',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                                ),
                              ],
                            ),
                          
                          SizedBox(height: isSmallScreen ? 10 : 20),
                        ],
                      ),
                    );
                  },
                ),
              ),
              
              // Lyrics Preview Card
              if (currentSong.lyrics.isNotEmpty)
                GestureDetector(
                  onTap: () => _showLyricsFullScreen(context),
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Lyrics',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Icon(Icons.fullscreen, color: Colors.white.withValues(alpha: 0.9)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 150,
                          child: StreamBuilder<Duration>(
                            stream: ref.read(audioPlayerProvider.notifier).positionStream,
                            builder: (context, snapshot) {
                              final position = snapshot.data ?? Duration.zero;
                              final currentIndex = _getCurrentLyricIndex(currentSong.lyrics, position);
                              
                              // Auto-scroll to current lyric
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (currentIndex > 0 && currentIndex < currentSong.lyrics.length) {
                                  _scrollController.animateTo(
                                    currentIndex * 30.0, // item height
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                }
                              });
                              
                              return ListView.builder(
                                physics: const ClampingScrollPhysics(),
                                controller: _scrollController,
                                itemCount: currentSong.lyrics.length,
                                itemExtent: 30,
                                itemBuilder: (context, index) {
                                  final lyric = currentSong.lyrics[index];
                                  final isCurrent = index == currentIndex;
                                  
                                  // Show only lyrics around current position
                                  if (index < currentIndex - 2 || index > currentIndex + 3) {
                                    return const SizedBox.shrink();
                                  }
                                  
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Text(
                                      lyric.text,
                                      style: TextStyle(
                                        color: isCurrent 
                                            ? Colors.white 
                                            : Colors.white.withValues(alpha: 0.4),
                                        fontSize: isCurrent ? 16 : 14,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                        height: 1.2,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}