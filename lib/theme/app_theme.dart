// ============================================================
// theme/app_theme.dart
// Spotifyにインスパイアされたダークテーマの定義
// ============================================================

import 'package:flutter/material.dart';

/// アプリ全体で使う色の定数
class AppColors {
  AppColors._(); // インスタンス化を防ぐ

  // ── ベースカラー ──────────────────────────────
  static const background = Color(0xFF121212);      // Spotify 背景色
  static const surface = Color(0xFF1E1E1E);         // カード・プレイヤー背景
  static const surfaceVariant = Color(0xFF282828);  // リスト項目・セクション

  // ── アクセントカラー ─────────────────────────
  static const accent = Color(0xFF1DB954);          // Spotify グリーン
  static const accentLight = Color(0xFF1ED760);     // ハイライト用の明るいグリーン

  // ── テキストカラー ───────────────────────────
  static const textPrimary = Color(0xFFFFFFFF);     // 主要テキスト（白）
  static const textSecondary = Color(0xFFB3B3B3);   // 補助テキスト（グレー）
  static const textDisabled = Color(0xFF535353);    // 無効状態のテキスト

  // ── 歌詞カラー ───────────────────────────────
  static const lyricDefault = Color(0xFF6A6A6A);    // 通常の歌詞（暗いグレー）
  static const lyricHighlight = Color(0xFFFFFFFF);  // ハイライト中の歌詞（白）
  static const lyricNear = Color(0xFFB3B3B3);       // ハイライト周辺の歌詞
}

/// アプリのテーマ設定
class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // カラースキーム
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        onPrimary: AppColors.textPrimary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        background: AppColors.background,
        onBackground: AppColors.textPrimary,
      ),

      // スキャフォールド背景
      scaffoldBackgroundColor: AppColors.background,

      // AppBarのスタイル
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
      ),

      // ボトムナビゲーション
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.textPrimary,
        unselectedItemColor: AppColors.textSecondary,
      ),

      // スライダー（シークバー）
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.textPrimary,
        inactiveTrackColor: AppColors.textDisabled,
        thumbColor: AppColors.textPrimary,
        overlayColor: Color(0x29FFFFFF),
        trackHeight: 3,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      ),

      // アイコン
      iconTheme: const IconThemeData(
        color: AppColors.textPrimary,
      ),

      // リストタイル
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        textColor: AppColors.textPrimary,
        iconColor: AppColors.textSecondary,
      ),

      // テキストスタイル
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        labelSmall: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }
}
