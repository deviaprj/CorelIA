import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Theme ─────────────────────────────────────────────────────────────────────
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('theme_mode');
    if (stored == 'dark') state = ThemeMode.dark;
    if (stored == 'light') state = ThemeMode.light;
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }
}

// ── Onboarding ────────────────────────────────────────────────────────────────
final onboardingDoneProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('onboarding_done') ?? false;
});

// ── TTS Speed ─────────────────────────────────────────────────────────────────
final ttsSpeedProvider = StateNotifierProvider<TtsSpeedNotifier, double>(
  (ref) => TtsSpeedNotifier(),
);

class TtsSpeedNotifier extends StateNotifier<double> {
  TtsSpeedNotifier() : super(0.50) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getDouble('tts_speed');
    if (stored != null) {
      state = stored.clamp(0.5, 2.0);
    }
  }

  Future<void> setSpeed(double speed) async {
    state = speed.clamp(0.5, 2.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('tts_speed', state);
  }
}
