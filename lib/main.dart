// ============================================================
// main.dart
// アプリの起動点
// ============================================================
//
// 【初心者向けメモ】
//   main() は Dart プログラムの「最初に呼ばれる関数」です。
//   Flutter アプリは runApp() でウィジェットツリーを起動します。
//   ProviderScope で全体をラップすることで Riverpod が使えるようになります。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:metadata_god/metadata_god.dart'; // ✅ 追加

import 'app.dart';

Future<void> main() async {
  // Flutter エンジンの初期化を確実に行う（非同期処理の前に必要）
  WidgetsFlutterBinding.ensureInitialized();
  MetadataGod.initialize(); // ✅ 追加：音楽メタデータ読み込みの準備

  // Initialize SQLite for Windows/Linux desktop platforms
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // ── バックグラウンド再生の初期化 ─────────────────────────────
  // just_audio_background の初期化（モバイル環境のみ）
  // → iOS のロック画面・コントロールセンター・CarPlay に対応するために必要
  //
  // ※ iOS の Info.plist に UIBackgroundModes: audio の設定も必要！
  //   詳細は STRUCTURE.md を参照してください。
  if (Platform.isAndroid || Platform.isIOS) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.localmusicplayer.channel.audio',
      androidNotificationChannelName: '音楽プレイヤー',
      androidNotificationOngoing: true,
      // iOS ではこの設定だけで自動的にバックグラウンド対応される
    );
  }

  // ── アプリの起動 ──────────────────────────────────────────────
  runApp(
    // ProviderScope: Riverpod の状態管理を有効にするラッパー
    // アプリ全体をこれで包むことで、どこからでも Provider にアクセスできる
    const ProviderScope(
      child: MusicPlayerApp(),
    ),
  );
}