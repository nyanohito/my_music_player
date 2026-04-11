// ============================================================
// app.dart
// アプリのルート Widget・テーマ・ルート設定
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/library_screen.dart';
import 'theme/app_theme.dart';

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Music Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      // ホーム画面はライブラリ
      home: const LibraryScreen(),
    );
  }
}
