// ============================================================
// screens/equalizer_screen.dart
// イコライザ画面
// ============================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';

class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(audioPlayerProvider);
    final notifier = ref.read(audioPlayerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'イコライザ',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          // Enable/Disable toggle
          Switch(
            value: playerState.isEqualizerEnabled,
            onChanged: (value) {
              notifier.toggleEqualizer();
            },
            activeColor: AppColors.accent,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Platform.isWindows
          ? _buildUnsupportedPlatformMessage()
          : playerState.isEqualizerEnabled
              ? _buildEqualizerControls(context, playerState, notifier) // ✅ context を渡す
              : _buildDisabledMessage(),
    );
  }

  Widget _buildUnsupportedPlatformMessage() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline,
            size: 64,
            color: AppColors.textDisabled,
          ),
          SizedBox(height: 16),
          Text(
            'イコライザはサポートされていません',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Windows環境ではイコライザ機能をご利用いただけません',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisabledMessage() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.tune,
            size: 64,
            color: AppColors.textDisabled,
          ),
          SizedBox(height: 16),
          Text(
            'イコライザが無効です',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '右上のスイッチで有効にしてください',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEqualizerControls(BuildContext context, playerState, notifier) { // ✅ BuildContext context を追加
    final equalizerBands = [
      {'frequency': '60Hz', 'index': 0},
      {'frequency': '230Hz', 'index': 1},
      {'frequency': '910Hz', 'index': 2},
      {'frequency': '3.6kHz', 'index': 3},
      {'frequency': '14kHz', 'index': 4},
    ];

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          // Preset buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPresetButton('Flat', notifier, [0.0, 0.0, 0.0, 0.0, 0.0]),
              _buildPresetButton('Bass', notifier, [8.0, 5.0, 2.0, 0.0, -2.0]),
              _buildPresetButton('Vocal', notifier, [-3.0, 1.0, 4.0, 3.0, 1.0]),
              _buildPresetButton('Rock', notifier, [5.0, 3.0, -1.0, 2.0, 4.0]),
            ],
          ),
          const SizedBox(height: 40),
          
          // Equalizer sliders
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: equalizerBands.map((band) {
                return _buildFrequencySlider(
                  context,
                  band['frequency'] as String,
                  band['index'] as int,
                  playerState.equalizerGains[band['index'] as int],
                  notifier,
                );
              }).toList(),
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Reset button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                for (int i = 0; i < 5; i++) {
                  notifier.setEqualizerGain(i, 0.0);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'リセット',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetButton(String label, notifier, List<double> gains) {
    return ElevatedButton(
      onPressed: () {
        for (int i = 0; i < gains.length; i++) {
          notifier.setEqualizerGain(i, gains[i]);
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildFrequencySlider(BuildContext context, String frequency, int index, double value, notifier) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Frequency label
        Text(
          frequency,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        
        // Vertical slider
        SizedBox(
          height: 200,
          width: 40,
          child: RotatedBox(
            quarterTurns: 3, // Rotate 270 degrees
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: AppColors.surface,
                thumbColor: AppColors.accent,
                overlayColor: AppColors.accent.withOpacity(0.2),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                trackHeight: 4,
              ),
              child: Slider(
                value: value,
                min: -12.0,
                max: 12.0,
                divisions: 24,
                onChanged: (newValue) {
                  notifier.setEqualizerGain(index, newValue);
                },
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 8),
        
        // Gain value label
        Text(
          '${value.toInt()}dB',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}