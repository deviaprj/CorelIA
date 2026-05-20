import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/platform/platform_service.dart';
import '../data/openrouter_tts_service.dart';
import '../data/tts_cache_service.dart';
import 'audio_player_factory.dart';
import 'emotion_parser.dart';
import 'tts_emotion.dart';

/// Moteur TTS sélectionné.
enum TtsEngine {
  openRouter,
  flutterTts,
}

/// Service TTS — OpenRouter TTS (voix réalistes) en priorité,
/// flutter_tts (native platform) en dernier recours.
///
/// Architecture :
/// - Mobile : OpenRouter TTS (gpt-4o-mini-tts → kokoro-82m) → flutter_tts
/// - Web/Extension : flutter_tts (via Web SpeechSynthesis) uniquement
class TtsNaturalService {
  // ── Audio player (mobile uniquement) ───────────────────────────────────────
  Object? _audioPlayer;

  // ── flutter_tts (fallback universel) ───────────────────────────────────────
  final FlutterTts _flutterTts = FlutterTts();
  bool _flutterTtsReady = false;

  // ── Cache TTS ────────────────────────────────────────────────────────────
  final TtsCacheService _cache = TtsCacheService();

  // ── État commun ─────────────────────────────────────────────────────────
  static const double _openRouterTtsSpeed = 0.65;
  bool _isSpeaking = false;
  TtsEngine _activeEngine = TtsEngine.flutterTts;
  TtsEmotion _currentEmotion = TtsEmotion.neutral;
  double _speechRate = 0.45;
  double _pitch = 1.10;
  String _language = 'fr-FR';

  bool get isSpeaking => _isSpeaking;
  TtsEngine get activeEngine => _activeEngine;
  TtsEmotion get currentEmotion => _currentEmotion;

  Future<void> init() async {
    await _initFlutterTts();
    await _cache.init();

    if (PlatformService.isMobile) {
      _audioPlayer ??= AudioPlayerFactory.create();
    }
  }

  Future<void> _initFlutterTts() async {
    try {
      await _flutterTts.setLanguage(_language);
      await _flutterTts.setSpeechRate(_speechRate);
      await _flutterTts.setPitch(_pitch);
      await _flutterTts.setVolume(1.0);
      _flutterTtsReady = true;
    } catch (e) {
      debugPrint('[TtsNaturalService] flutter_tts init failed: $e');
    }
  }

  Future<void> setSpeed(double rate) async {
    _speechRate = rate.clamp(0.35, 1.30);
    if (_flutterTtsReady) {
      await _flutterTts.setSpeechRate(_speechRate);
    }
  }

  double get speed => _speechRate;

  Future<void> setPitch(double pitch) async {
    _pitch = pitch.clamp(0.5, 2.0);
    if (_flutterTtsReady) {
      await _flutterTts.setPitch(_pitch);
    }
  }

  void setEmotion(TtsEmotion emotion) {
    _currentEmotion = emotion;
  }

  // ── Nettoyage markdown ──────────────────────────────────────────────────

  static String stripEmojis(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (!_isEmoji(rune)) buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  static bool _isEmoji(int rune) {
    return (rune >= 0x1F600 && rune <= 0x1F64F) ||
        (rune >= 0x1F300 && rune <= 0x1F5FF) ||
        (rune >= 0x1F680 && rune <= 0x1F6FF) ||
        (rune >= 0x1F1E0 && rune <= 0x1F1FF) ||
        (rune >= 0x2600 && rune <= 0x26FF) ||
        (rune >= 0x2700 && rune <= 0x27BF) ||
        (rune >= 0xFE00 && rune <= 0xFE0F) ||
        (rune >= 0x1F900 && rune <= 0x1F9FF) ||
        (rune >= 0x1F000 && rune <= 0x1F02F) ||
        (rune >= 0x1F0A0 && rune <= 0x1F0FF) ||
        (rune >= 0x1F100 && rune <= 0x1F1FF) ||
        (rune >= 0x1F700 && rune <= 0x1F77F) ||
        (rune >= 0x1F780 && rune <= 0x1F7FF) ||
        (rune >= 0x1F800 && rune <= 0x1F8FF) ||
        (rune >= 0x1FA00 && rune <= 0x1FA6F) ||
        (rune >= 0x1FA70 && rune <= 0x1FAFF) ||
        (rune >= 0x2300 && rune <= 0x23FF) ||
        (rune == 0x00A9) ||
        (rune == 0x00AE) ||
        (rune == 0x2122) ||
        (rune == 0x3030) ||
        (rune == 0x303D) ||
        (rune == 0x3297) ||
        (rune == 0x3299) ||
        (rune >= 0x2B50 && rune <= 0x2B55);
  }

  static final _urlPattern = RegExp(
    r'https?://(?:www\.)?([a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+)',
    caseSensitive: false,
  );
  static final _citationPattern = RegExp(r'\[\d+\]');

  static String stripUrls(String text) {
    return text.replaceAllMapped(_urlPattern, (match) {
      final domain = match.group(1);
      return domain ?? '';
    });
  }

  static String stripCitations(String text) {
    return text.replaceAll(_citationPattern, '');
  }

  static String cleanMarkdown(String text) {
    var working = _stripSourcesSection(text);
    working = stripUrls(working);
    working = stripCitations(working);
    working = stripEmojis(working);
    working = working
        .replaceAllMapped(RegExp(r'\*\*\*(.+?)\*\*\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'_(.+?)_'), (m) => m.group(1) ?? '');
    working = working.replaceAllMapped(
      RegExp(r'^#{1,6}\s+(.+)$', multiLine: true),
      (m) => '${m.group(1) ?? ''}\n\n',
    );
    working = working.replaceAllMapped(
      RegExp(r'`{3}[\s\S]*?`{3}'),
      (_) => ' [bloc de code] .\n\n',
    );
    working = working.replaceAllMapped(RegExp(r'`(.+?)`'), (m) => m.group(1) ?? '');
    working = working.replaceAll(RegExp(r'^-{3,}\s*$', multiLine: true), '\n\n');
    working = working.replaceAllMapped(RegExp(r'\[(.+?)\]\(.+?\)'), (m) => m.group(1) ?? '');
    working = working.replaceAllMapped(RegExp(r'!\[(.*?)\]\(.+?\)'), (m) {
      final alt = m.group(1);
      return alt != null && alt.isNotEmpty ? ' [image: $alt] ' : ' [image] ';
    });
    working = working.replaceAllMapped(
      RegExp(r'^\s*[-*+]\s+(.+)$', multiLine: true),
      (m) => '${m.group(1) ?? ''}\n',
    );
    working = working.replaceAllMapped(
      RegExp(r'^\s*\d+\.\s+(.+)$', multiLine: true),
      (m) => '${m.group(1) ?? ''}\n',
    );
    working = working.replaceAll(RegExp(r'^>\s+', multiLine: true), '');
    working = working.replaceAll(RegExp(r'<[^>]+>'), '');
    working = working.replaceAll(RegExp(r'[ \t]+'), ' ');
    working = working.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return working.trim();
  }

  static String _stripSourcesSection(String text) {
    final sepPattern = RegExp(
      r'\n?\s*---+\s*\n?\s*\*\*Sources\s*:\*\*.*',
      caseSensitive: false,
      dotAll: true,
    );
    var result = text.replaceFirst(sepPattern, '');
    final plainPattern = RegExp(
      r'\n\n\s*Sources\s*:.*',
      caseSensitive: false,
      dotAll: true,
    );
    result = result.replaceFirst(plainPattern, '');
    return result;
  }

  // ── Synthèse vocale ─────────────────────────────────────────────────────

  Future<void> speakNaturally(String text) async {
    if (_isSpeaking) await stop();

    final parseResult = EmotionParser.parse(text);
    final emotion = parseResult.hasEmotionTag ? parseResult.emotion : _currentEmotion;
    final cleanText = parseResult.hasEmotionTag ? parseResult.cleanText : cleanMarkdown(text);

    if (cleanText.trim().isEmpty) return;

    _isSpeaking = true;
    _currentEmotion = emotion;

    // OpenRouter TTS (mobile, si clé API disponible)
    if (PlatformService.isMobile && OpenRouterTtsService.isAvailable) {
      try {
        _activeEngine = TtsEngine.openRouter;
        await _speakWithOpenRouterTts(cleanText, emotion);
        return;
      } catch (e) {
        debugPrint('[TtsNaturalService] OpenRouter TTS failed, falling back: $e');
      }
    }

    // flutter_tts (fallback universel)
    _activeEngine = TtsEngine.flutterTts;
    await _speakWithFlutterTts(cleanText);
  }

  Future<void> _speakWithOpenRouterTts(String text, TtsEmotion emotion) async {
    if (_audioPlayer == null) {
      _audioPlayer = AudioPlayerFactory.create();
    }

    final voice = emotionVoiceMap[emotion.name] ?? TtsVoice.nova;

    // Vérifier le cache d'abord
    final cachedPath = await _cache.get(
      text,
      voice: voice.name,
      rate: _openRouterTtsSpeed,
      pitch: 1.0,
      format: 'openrouter',
    );

    String? audioPath;

    if (cachedPath != null) {
      audioPath = cachedPath;
    } else {
      final bytes = await OpenRouterTtsService.synthesize(
        text,
        voice: voice,
        speed: _openRouterTtsSpeed,
      );
      if (bytes == null) {
        throw StateError('OpenRouter TTS returned no audio');
      }

      final cached = await _cache.putBytes(
        text,
        bytes,
        voice: voice.name,
        rate: _openRouterTtsSpeed,
        pitch: 1.0,
        format: 'openrouter',
      );
      audioPath = cached;
    }

    if (audioPath == null) {
      throw StateError('OpenRouter TTS: no audio path');
    }

    try {
      await AudioPlayerFactory.setFilePath(_audioPlayer!, audioPath);
      await AudioPlayerFactory.play(_audioPlayer!);
      await AudioPlayerFactory.waitForCompletion(_audioPlayer!);
    } finally {
      await AudioPlayerFactory.stop(_audioPlayer!);
    }
  }

  Future<void> _speakWithFlutterTts(String text) async {
    if (!_flutterTtsReady) {
      await _initFlutterTts();
    }

    final config = emotionTtsConfigs[_currentEmotion] ?? emotionTtsConfigs[TtsEmotion.neutral]!;
    try {
      await _flutterTts.setSpeechRate(config.rate * _speechRate / 0.65);
      await _flutterTts.setPitch(config.pitch * _pitch / 1.10);
    } catch (e) {
      debugPrint('[TtsNaturalService] flutter_tts emotion params failed: $e');
    }

    try {
      final chunks = _splitForNaturalSpeech(text);
      for (var i = 0; i < chunks.length; i++) {
        if (!_isSpeaking) break;
        final completer = Completer<void>();
        _flutterTts.setCompletionHandler(() {
          if (!completer.isCompleted) completer.complete();
        });
        _flutterTts.setErrorHandler((_) {
          if (!completer.isCompleted) completer.complete();
        });

        await _flutterTts.speak(chunks[i]);
        await completer.future.timeout(
          const Duration(seconds: 25),
          onTimeout: () {},
        );

        if (i < chunks.length - 1) {
          await Future<void>.delayed(const Duration(milliseconds: 140));
        }
      }
    } catch (e) {
      debugPrint('[TtsNaturalService] flutter_tts error: $e');
    } finally {
      _flutterTts.setCompletionHandler(() {});
      _flutterTts.setErrorHandler((_) {});
      try {
        await _flutterTts.setSpeechRate(_speechRate);
        await _flutterTts.setPitch(_pitch);
      } catch (_) {}
    }
  }

  List<String> _splitForNaturalSpeech(String text) {
    final normalized = text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return const [];

    const maxChunkLength = 220;
    final sentenceChunks = normalized.split(RegExp(r'(?<=[\.!?;:])\s+'));
    final chunks = <String>[];
    final current = StringBuffer();

    void flush() {
      if (current.isNotEmpty) {
        chunks.add(current.toString().trim());
        current.clear();
      }
    }

    for (final sentence in sentenceChunks) {
      if (sentence.length > maxChunkLength) {
        flush();
        for (var i = 0; i < sentence.length; i += maxChunkLength) {
          final end = math.min(i + maxChunkLength, sentence.length);
          chunks.add(sentence.substring(i, end).trim());
        }
        continue;
      }

      final nextLength = current.length + (current.isNotEmpty ? 1 : 0) + sentence.length;
      if (nextLength > maxChunkLength) {
        flush();
      }
      if (current.isNotEmpty) current.write(' ');
      current.write(sentence);
    }

    flush();
    return chunks.where((c) => c.isNotEmpty).toList(growable: false);
  }

  Future<void> stop() async {
    _isSpeaking = false;
    if (_activeEngine == TtsEngine.openRouter && _audioPlayer != null) {
      await AudioPlayerFactory.stop(_audioPlayer!);
    } else {
      await _flutterTts.stop();
    }
  }

  void dispose() {
    _isSpeaking = false;
    if (_audioPlayer != null) {
      AudioPlayerFactory.dispose(_audioPlayer!);
    }
    _flutterTts.stop();
  }
}