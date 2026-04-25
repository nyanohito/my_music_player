// ============================================================
// widgets/song_info_sheet.dart
// 曲情報シート（ファイルサイズ・形式等）
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/song.dart';
import '../theme/app_theme.dart';

class SongInfoSheet extends StatelessWidget {
  final Song song;

  const SongInfoSheet._({required this.song});

  static void show(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SongInfoSheet._(song: song),
    );
  }

  Future<Map<String, String>> _loadFileInfo() async {
    final info = <String, String>{};
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fullPath = p.join(appDir.path, song.filePath);
      final file = File(fullPath);

      if (await file.exists()) {
        final stat = await file.stat();
        final bytes = stat.size;
        info['ファイルサイズ'] = _formatBytes(bytes);
        info['更新日時'] = _formatDate(stat.modified);
        info['ファイル名'] = song.filePath;

        // 拡張子からコーデックを推定
        final ext = song.filePath.split('.').last.toUpperCase();
        info['形式'] = ext;
      }
    } catch (_) {
      info['エラー'] = 'ファイル情報を取得できませんでした';
    }
    return info;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return SafeArea(
          child: Column(
            children: [
              // ── ハンドル ───────────────────────────────
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textDisabled,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── ヘッダー ───────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    // ミニアルバムアート
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: song.albumArt != null
                          ? Image.memory(song.albumArt!,
                              width: 52, height: 52, fit: BoxFit.cover)
                          : Container(
                              width: 52,
                              height: 52,
                              color: AppColors.surfaceVariant,
                              child: const Icon(Icons.music_note_rounded,
                                  color: AppColors.textDisabled),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            song.artist,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.surfaceVariant, height: 1),

              // ── 情報リスト ─────────────────────────────
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  children: [
                    // 基本タグ情報
                    _InfoRow(
                        label: 'タイトル',
                        value: song.title.isEmpty ? '不明' : song.title),
                    _InfoRow(
                        label: 'アーティスト',
                        value: song.artist.isEmpty ? '不明' : song.artist),
                    if (song.lyrics.isNotEmpty)
                      _InfoRow(label: '歌詞', value: '${song.lyrics.length}行'),

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(color: AppColors.surfaceVariant),
                    ),

                    // ファイル情報（非同期ロード）
                    FutureBuilder<Map<String, String>>(
                      future: _loadFileInfo(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                color: AppColors.accent,
                                strokeWidth: 2,
                              ),
                            ),
                          );
                        }
                        final info = snapshot.data ?? {};
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ファイル情報',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...info.entries.map((e) => _InfoRow(
                                  label: e.key,
                                  value: e.value,
                                  copyable: e.key == 'ファイル名',
                                )),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── 情報行 ───────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;

  const _InfoRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onLongPress: copyable
                  ? () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('コピーしました'),
                          duration: Duration(seconds: 1),
                          backgroundColor: AppColors.accent,
                        ),
                      );
                    }
                  : null,
              child: Text(
                value,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  decoration:
                      copyable ? TextDecoration.underline : null,
                  decorationColor: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}