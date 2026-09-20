import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Thème ─────────────────────────────────────────────────────────────────────
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  static const _prefsKey = 'theme_mode';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_prefsKey)) {
      case 'dark':
        state = ThemeMode.dark;
      case 'light':
        state = ThemeMode.light;
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}

// ── Prompt système ────────────────────────────────────────────────────────────
const _systemPromptKey = 'corelia_system_prompt';

const kDefaultSystemPrompt =
    'Tu es CorelIA, un assistant IA conversationnel chaleureux et intelligent. '
    'Tu réponds en français par défaut, de façon directe, utile et concise. '
    'Tu tutoies par défaut et tu ne dis jamais « en tant que modèle de langage ».';

final systemPromptProvider = StateNotifierProvider<SystemPromptNotifier, String>(
  (ref) => SystemPromptNotifier(),
);

class SystemPromptNotifier extends StateNotifier<String> {
  SystemPromptNotifier() : super(kDefaultSystemPrompt) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_systemPromptKey);
    if (saved != null && saved.isNotEmpty) state = saved;
  }

  Future<void> save(String prompt) async {
    state = prompt.trim().isEmpty ? kDefaultSystemPrompt : prompt;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_systemPromptKey, state);
  }

  Future<void> reset() async {
    state = kDefaultSystemPrompt;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_systemPromptKey);
  }
}
