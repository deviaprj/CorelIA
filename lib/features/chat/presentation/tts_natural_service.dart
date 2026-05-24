import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/platform/platform_service.dart';
import '../data/openrouter_tts_service.dart';
import '../data/tts_cache_service.dart';
import 'audio_player_factory.dart';
import 'emotion_parser.dart';
import 'phonetic_liaison_service.dart';
import 'prosody_learning_service.dart';
import 'tts_emotion.dart';
import 'vocal_hesitation_injector.dart';

/// Moteur TTS selectionne.
enum TtsEngine {
  openRouter,
  edgeTts,
  flutterTts,
}

/// Service TTS simplifie — parle le texte complet d'un bloc.
/// Pas de streaming par phrases.
class TtsNaturalService {
  // ── Audio player (mobile uniquement) ───────────────────────────────────────
  Object? _audioPlayer;

  // ── flutter_tts (fallback universel) ───────────────────────────────────────
  final FlutterTts _flutterTts = FlutterTts();
  bool _flutterTtsReady = false;

  // ── Cache TTS ────────────────────────────────────────────────────────────
  final TtsCacheService _cache = TtsCacheService();

  // ── Etat commun ─────────────────────────────────────────────────────────
  static const double _openRouterTtsSpeed = 1.0;
  bool _isSpeaking = false;
  TtsEngine _activeEngine = TtsEngine.flutterTts;
  TtsEmotion _currentEmotion = TtsEmotion.neutral;
  double _speechRate = 0.45;
  double _pitch = 1.15;
  String _language = 'fr-FR';

  bool get isSpeaking => _isSpeaking;
  TtsEngine get activeEngine => _activeEngine;
  TtsEmotion get currentEmotion => _currentEmotion;

  // ── Prosody learning ─────────────────────────────────────────────────────
  final ProsodyLearningService _prosodyLearning = ProsodyLearningService();
  /// True si une voix premium (neural/premium/enhanced) a ete detectee.
  bool get hasPremiumVoice => _hasPremiumVoice;
  bool _hasPremiumVoice = false;

  Future<void> init() async {
    await _initFlutterTts();
    await _cache.init();

    if (PlatformService.isMobile) {
      _audioPlayer ??= AudioPlayerFactory.create();
    }

    // Prechauffer le moteur TTS pour reduire la latence de la premiere phrase
    if (_flutterTtsReady) {
      try {
        await _flutterTts.speak('');
      } catch (_) {}
    }
  }

  Future<void> _initFlutterTts() async {
    try {
      await _flutterTts.setLanguage(_language);
      await _selectBestVoice();
      await _flutterTts.setSpeechRate(_speechRate);
      await _flutterTts.setPitch(_pitch);
      await _flutterTts.setVolume(1.0);
      _flutterTtsReady = true;
    } catch (e) {
      debugPrint('[TtsNaturalService] flutter_tts init failed: $e');
    }
  }

  /// Selectionne dynamiquement la meilleure voix fr-FR disponible.
  Future<void> _selectBestVoice() async {
    try {
      final voices = await _flutterTts.getVoices;
      if (voices is! List) return;

      final frVoices = voices.where((v) {
        final map = v as Map<dynamic, dynamic>? ?? {};
        final locale = (map['locale'] ?? map['language'] ?? '').toString();
        return locale.toLowerCase().startsWith('fr');
      }).toList();

      if (frVoices.isEmpty) return;

      final premiumPatterns = ['neural', 'premium', 'enhanced', 'siri'];
      final fallbackPatterns = ['local', 'c1', 'c2', 'c3', 'network'];
      String? bestName;
      for (final pattern in premiumPatterns) {
        for (final v in frVoices) {
          final map = v as Map<dynamic, dynamic>? ?? {};
          final name = (map['name'] ?? '').toString().toLowerCase();
          if (name.contains(pattern)) {
            bestName = map['name'] as String?;
            _hasPremiumVoice = true;
            break;
          }
        }
        if (bestName != null) break;
      }
      if (bestName == null) {
        for (final pattern in fallbackPatterns) {
          for (final v in frVoices) {
            final map = v as Map<dynamic, dynamic>? ?? {};
            final name = (map['name'] ?? '').toString().toLowerCase();
            if (name.contains(pattern)) {
              bestName = map['name'] as String?;
              break;
            }
          }
          if (bestName != null) break;
        }
      }
      bestName ??= ((frVoices.first as Map<dynamic, dynamic>)['name'] as String?);

      if (bestName != null) {
        await _flutterTts.setVoice({'name': bestName, 'locale': 'fr-FR'});
      }
    } catch (e) {
      debugPrint('[TtsNaturalService] Voice selection failed: $e');
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

  /// Parle le texte complet d'un bloc (pas de streaming par phrases).
  Future<void> speakNaturally(String text) async {
    if (_isSpeaking) await stop();

    final parseResult = EmotionParser.parse(text);
    final emotion = parseResult.hasEmotionTag ? parseResult.emotion : _currentEmotion;
    // CRITICAL: always run cleanMarkdown, even when emotion tags were detected,
    // so that markdown artifacts (asterisks, pipes, citations, URLs) are stripped.
    var cleanText = cleanMarkdown(parseResult.cleanText);

    // Apply phonetic liaisons for natural prosody
    cleanText = PhoneticLiaisonService.apply(cleanText, _language);

    // Inject natural hesitations based on learned intensity
    final hesitationIntensity = await _prosodyLearning.getHesitationIntensity();
    cleanText = VocalHesitationInjector.inject(cleanText, intensity: hesitationIntensity);

    if (cleanText.trim().isEmpty) return;

    _isSpeaking = true;
    _currentEmotion = emotion;

    // OpenRouter TTS (mobile, si cle API disponible)
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

    final config = await _prosodyLearning.getConfigForEmotion(_currentEmotion);
    final adaptiveRate = text.length < 150
        ? config.rate * 1.05
        : config.rate * 0.95;
    try {
      await _flutterTts.setSpeechRate(adaptiveRate.clamp(0.35, 1.00));
      await _flutterTts.setPitch(config.pitch * _pitch / 1.10);
    } catch (e) {
      debugPrint('[TtsNaturalService] flutter_tts emotion params failed: $e');
    }

    try {
      final chunks = _splitForNaturalSpeech(text);
      for (var i = 0; i < chunks.length; i++) {
        if (!_isSpeaking) break;
        final chunk = chunks[i];

        // Paragraph break: longer pause instead of speaking
        if (chunk.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }

        final completer = Completer<void>();
        _flutterTts.setCompletionHandler(() {
          if (!completer.isCompleted) completer.complete();
        });
        _flutterTts.setErrorHandler((_) {
          if (!completer.isCompleted) completer.complete();
        });

        await _flutterTts.speak(chunk);
        await completer.future.timeout(
          const Duration(seconds: 25),
          onTimeout: () {},
        );

        if (i < chunks.length - 1) {
          // Longer pause between sentences for natural prosody
          await Future<void>.delayed(const Duration(milliseconds: 250));
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

    // 1. Strip reasoning / thinking blocks (DeepSeek R1, etc.)
    working = working.replaceAllMapped(
      RegExp(r'\<think\>[\s\S]*?\<\/think\>'),
      (_) => '',
    );
    working = working.replaceAllMapped(
      RegExp(r'\`\`\`\s*reasoning[\s\S]*?\`\`\`'),
      (_) => '',
    );

    // 2. Strip URLs, citations, emojis early
    working = stripUrls(working);
    working = stripCitations(working);
    working = stripEmojis(working);

    // 3. Bold / italic / underline
    working = working
        .replaceAllMapped(RegExp(r'\*\*\*(.+?)\*\*\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'_(.+?)_'), (m) => m.group(1) ?? '');

    // 4. Headings
    working = working.replaceAllMapped(
      RegExp(r'^#{1,6}\s+(.+)$', multiLine: true),
      (m) => '${m.group(1) ?? ''}\n\n',
    );

    // 5. Code blocks → hint, inline code → raw
    working = working.replaceAllMapped(
      RegExp(r'`{3}[\s\S]*?`{3}'),
      (_) => ' bloc de code. \n\n',
    );
    working = working.replaceAllMapped(RegExp(r'`(.+?)`'), (m) => m.group(1) ?? '');

    // 6. Horizontal rules
    working = working.replaceAll(RegExp(r'^-{3,}\s*$', multiLine: true), '\n\n');

    // 7. Links → text only, images → alt
    working = working.replaceAllMapped(RegExp(r'\[(.+?)\]\(.+?\)'), (m) => m.group(1) ?? '');
    working = working.replaceAllMapped(RegExp(r'!\[(.*?)\]\(.+?\)'), (m) {
      final alt = m.group(1);
      return alt != null && alt.isNotEmpty ? ' [image: $alt] ' : ' [image] ';
    });

    // 8. Markdown tables → plain text (remove pipes, header separator)
    working = working.replaceAllMapped(
      RegExp(r'^\s*\|?(.+?)\|?\s*$', multiLine: true),
      (m) {
        final raw = m.group(1) ?? '';
        // Only process lines that actually contain table pipes
        if (!raw.contains('|')) return m.group(0) ?? '';
        // Skip table header separator lines like |---|---|
        if (RegExp(r'^\s*[|:-\s]+\|\s*[|:-\s]+\s*$').hasMatch(raw)) {
          return '\n';
        }
        final cells = raw.split('|').where((c) => c.trim().isNotEmpty).join(', ');
        return cells.isNotEmpty ? '$cells. ' : '\n';
      },
    );

    // 9. Lists (bullets + numbered)
    working = working.replaceAllMapped(
      RegExp(r'^\s*[-*+]\s+(.+)$', multiLine: true),
      (m) => '${m.group(1) ?? ''}\n',
    );
    working = working.replaceAllMapped(
      RegExp(r'^\s*\d+\.\s+(.+)$', multiLine: true),
      (m) => '${m.group(1) ?? ''}\n',
    );

    // 10. Blockquotes
    working = working.replaceAll(RegExp(r'^>\s+', multiLine: true), '');

    // 11. HTML tags
    working = working.replaceAll(RegExp(r'<[^>]+>'), '');

    // 12. Punctuation normalization for speech
    working = working.replaceAll(RegExp(r'(?<=\w);(?=\s|$)'), '. ');
    working = working.replaceAll(RegExp(r'(?<=\w):(?=\s|$)'), '. ');
    working = working.replaceAll(RegExp(r'\s+#\s+'), ' ');
    working = working.replaceAll(RegExp(r'\s+##+\s+'), ' ');
    working = working.replaceAll(RegExp(r'(?<=\w)\/(?=\w)'), ' ');
    working = working.replaceAll(RegExp(r'(?<=\w)\\(?=\w)'), ' ');

    // 14. Final aggressive pass — remove stray markdown artifacts
    // Any remaining *, -, _, |, #, >, ~, ` at line start that are NOT part of words
    working = working.replaceAllMapped(
      RegExp(r'^\s*[-*_#>|~`]+\s*', multiLine: true),
      (_) => '',
    );
    // Remove stray brackets that weren't links (but keep link text handled above)
    working = working.replaceAll(RegExp(r'(?<!\w)\[(\d+)\](?!\w)'), ' '); // citations missed earlier
    working = working.replaceAll(RegExp(r'\[|\]'), ' ');
    // Remove stray asterisks / underscores / tildes inside text
    working = working.replaceAll(RegExp(r'(?<!\w)[*_~`]+(?!\w)'), ' ');
    // Remove stray pipes and hash signs
    working = working.replaceAll(RegExp(r'(?<!\w)[|#]+(?!\w)'), ' ');
    // Remove stray parentheses left from broken links
    working = working.replaceAll(RegExp(r'\(\s*\)'), ' ');
    // Remove any remaining single backticks
    working = working.replaceAll('`', ' ');

    // 15. Collapse whitespace BUT preserve paragraph breaks (\n\n) for natural pauses
    working = working.replaceAll(RegExp(r'[ \t]+'), ' ');
    working = working.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    // Keep \n\n as paragraph markers; replace single \n with space
    working = working.replaceAllMapped(
      RegExp(r'(?<!\n)\n(?!\n)'),
      (_) => ' ',
    );

    return working.trim();
  }

  static String _stripSourcesSection(String text) {
    // Patterns pour "Sources", "Références", "Liens", "References", "Links"
    final patterns = [
      // Separator + bold Sources
      RegExp(
        r'\n?\s*---+\s*\n?\s*\*\*Sources\s*:\*\*.*',
        caseSensitive: false,
        dotAll: true,
      ),
      // Plain Sources (English)
      RegExp(
        r'\n\n\s*Sources\s*:.*',
        caseSensitive: false,
        dotAll: true,
      ),
      // Références (French)
      RegExp(
        r'\n\n\s*Références\s*:.*',
        caseSensitive: false,
        dotAll: true,
      ),
      // Liens (French)
      RegExp(
        r'\n\n\s*Liens\s*:.*',
        caseSensitive: false,
        dotAll: true,
      ),
      // Links (English)
      RegExp(
        r'\n\n\s*Links\s*:.*',
        caseSensitive: false,
        dotAll: true,
      ),
      // References (English variant)
      RegExp(
        r'\n\n\s*References\s*:.*',
        caseSensitive: false,
        dotAll: true,
      ),
      // Inline reference markers like [1], [2], [3] at end of text
      RegExp(
        r'\n?\s*\*\*Références?\s*:\*\*.*',
        caseSensitive: false,
        dotAll: true,
      ),
      RegExp(
        r'\n?\s*\*\*Liens?\s*:\*\*.*',
        caseSensitive: false,
        dotAll: true,
      ),
    ];
    var result = text;
    for (final pattern in patterns) {
      result = result.replaceFirst(pattern, '');
    }
    return result;
  }

  List<String> _splitForNaturalSpeech(String text) {
    // Preserve paragraph breaks (\n\n) for natural pauses between sections
    final cleaned = text
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (cleaned.isEmpty) return const [];

    const maxChunkLength = 120;
    final chunks = <String>[];
    final current = StringBuffer();

    void flush() {
      if (current.isNotEmpty) {
        chunks.add(current.toString().trim());
        current.clear();
      }
    }

    final paragraphs = cleaned.split('\n\n');
    for (var pIdx = 0; pIdx < paragraphs.length; pIdx++) {
      final para = paragraphs[pIdx].trim();
      if (para.isEmpty) continue;

      final sentenceChunks = para.split(RegExp(r'(?<=[\.!?;:])\s+'));
      for (final sentence in sentenceChunks) {
        final trimmed = sentence.trim();
        if (trimmed.isEmpty) continue;

        if (trimmed.length > maxChunkLength) {
          flush();
          for (var i = 0; i < trimmed.length; i += maxChunkLength) {
            final end = math.min(i + maxChunkLength, trimmed.length);
            chunks.add(trimmed.substring(i, end).trim());
          }
          continue;
        }

        final nextLength = current.length + (current.isNotEmpty ? 1 : 0) + trimmed.length;
        if (nextLength > maxChunkLength) {
          flush();
        }
        if (current.isNotEmpty) current.write(' ');
        current.write(trimmed);
      }

      flush();
      // Insert a paragraph-break marker (empty chunk) between paragraphs
      // so that _speakWithFlutterTts can insert a longer pause.
      if (pIdx < paragraphs.length - 1) {
        chunks.add('');
      }
    }

    return chunks.where((c) => c.isNotEmpty || c == '').toList(growable: false);
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
