// ============================================================
// widgets/mini_player_with_progress.dart
// ミニプレイヤーバー（プログレスバー付き）
// ============================================================

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../theme/app_theme.dart';

class MiniPlayerWithProgress extends StatefulWidget {
  final dynamic currentSong; // Song?
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onPlayPause;
  final Stream<Duration>? positionStream;
  final Duration? duration;

  const MiniPlayerWithProgress({
    required this.currentSong,
    required this.isPlaying,
    required this.onTap,
    required this.onPlayPause,
    this.positionStream,
    this.duration,
  });

  @override
  State<MiniPlayerWithProgress> createState() => _MiniPlayerWithProgressState();
}

class _MiniPlayerWithProgressState extends State<MiniPlayerWithProgress> {
  Color _dominantColor = const Color(0xFF81C784);

  @override
  void initState() {
    super.initState();
    _extractDominantColor();
  }

  @override
  void didUpdateWidget(MiniPlayerWithProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSong?.albumArt != widget.currentSong?.albumArt) {
      _extractDominantColor();
    }
  }

  Future<void> _extractDominantColor() async {
    if (widget.currentSong?.albumArt != null) {
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          MemoryImage(widget.currentSong!.albumArt!),
        );
        if (mounted) {
          setState(() {
            _dominantColor = palette.dominantColor?.color ?? const Color(0xFF81C784);
          });
        }
      } catch (e) {
        // Fallback to default color
      }
    } else {
      setState(() {
        _dominantColor = const Color(0xFF81C784);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        children: [
          // Main content
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _dominantColor,
                  _dominantColor.withValues(alpha: 0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                // Mini album artwork
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: widget.currentSong?.albumArt != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            widget.currentSong!.albumArt!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.music_note_rounded,
                                color: Colors.white,
                                size: 24,
                              );
                            },
                          ),
                        )
                      : const Icon(
                          Icons.music_note_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                ),
                const SizedBox(width: 16),

                // Song info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Song title
                      Text(
                        widget.currentSong?.title ?? 'Unknown Song',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Artist name
                      Text(
                        widget.currentSong?.artist ?? 'Mrs. GREEN APPLE',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // Play/Pause button
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      widget.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      size: 24,
                    ),
                    color: _dominantColor,
                    onPressed: widget.onPlayPause,
                  ),
                ),
              ],
            ),
          ),
          
          // Progress bar at bottom
          if (widget.positionStream != null && widget.duration != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                child: StreamBuilder<Duration>(
                  stream: widget.positionStream!,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final progress = widget.duration!.inMilliseconds > 0 
                        ? (position.inMilliseconds / widget.duration!.inMilliseconds).clamp(0.0, 1.0)
                        : 0.0;
                    
                    return LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
