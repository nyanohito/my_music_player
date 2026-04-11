// ============================================================
// widgets/playlist_selection_dialog.dart
// プレイリスト選択ダイアログ
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';
import '../utils/database_helper.dart';
import '../models/song.dart';

class PlaylistSelectionDialog extends ConsumerWidget {
  final String songId;

  const PlaylistSelectionDialog({required this.songId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(audioPlayerProvider);
    final notifier = ref.read(audioPlayerProvider.notifier);
    final playlists = playerState.playlists;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'プレイリストを選択',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            if (playlists.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.playlist_add,
                      color: AppColors.accent,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'プレイリストがありません',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '先にプレイリストを作成してください',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _showCreatePlaylistDialog(context, notifier, songId);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('新規作成'),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...playlists.map((playlist) => FutureBuilder<List<Song>>(
                    future: DatabaseHelper().getPlaylistSongs(playlist['id']),
                    builder: (context, snapshot) {
                      final isSongInPlaylist = snapshot.hasData && 
                          snapshot.data!.any((song) => song.id == songId);
                      
                      return ListTile(
                        title: Text(playlist['name'] as String? ?? 'Untitled'),
                        trailing: isSongInPlaylist
                            ? const Icon(
                                Icons.check_circle,
                                color: AppColors.accent,
                                size: 24,
                              )
                            : null,
                        onTap: () async {
                          Navigator.of(context).pop();
                          if (isSongInPlaylist) {
                            // Remove from playlist
                            await DatabaseHelper().removeSongFromPlaylist(songId, playlist['id'] as String);
                          } else {
                            // Add to playlist
                            await notifier.addSongToPlaylist(songId, playlist['id'] as String);
                          }
                        },
                      );
                    },
                  )),
          ],
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, dynamic notifier, String songId) {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '新しいプレイリスト',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'プレイリスト名',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('キャンセル'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (controller.text.isNotEmpty) {
                        notifier.createPlaylist(controller.text);
                        Navigator.of(context).pop();
                        // Add song to newly created playlist
                        notifier.addSongToPlaylist(songId, controller.text);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('作成'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
