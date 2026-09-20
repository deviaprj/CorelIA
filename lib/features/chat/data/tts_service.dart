import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'speech_text.dart';

/// Lecture à voix haute des réponses de l'assistant.
///
/// S'appuie sur le moteur de synthèse vocale du système (Google TTS sur
/// Android) : aucune clé, aucun coût, disponible hors ligne. La langue est
/// choisie d'après le texte lu, avec la langue de l'appareil en repli.
class TtsService {
  TtsService({FlutterTts? engine}) : _engine = engine ?? FlutterTts();

  final FlutterTts _engine;
  bool _ready = false;

  /// Débit de lecture.
  ///
  /// `flutter_tts` transmet `rate × 2` à Android : 0.5 équivaut donc au débit
  /// normal du système (1.0), et 0.5 est aussi la valeur normale sur iOS.
  /// 0.55 lit environ 10 % plus vite, sans paraître précipité.
  static const speechRate = 0.55;

  /// Déclenché à la fin de la lecture (fin normale, arrêt ou erreur).
  VoidCallback? onDone;

  /// Lit [text] (Markdown nettoyé au préalable).
  Future<void> speak(String text) async {
    final content = stripMarkdownForSpeech(text);
    if (content.isEmpty) {
      onDone?.call();
      return;
    }

    await _prepare();
    await _engine.stop();

    final language = resolveSpeechLanguage(content);
    await _engine.setLanguage(language);
    await _applyBestVoice(language);
    await _engine.speak(content);
  }

  Future<void> stop() => _engine.stop();

  Future<void> _prepare() async {
    if (_ready) return;
    await _engine.setSpeechRate(speechRate);
    await _engine.setPitch(1.0);
    await _engine.setVolume(1.0);
    await _engine.awaitSpeakCompletion(true);
    _engine.setCompletionHandler(() => onDone?.call());
    _engine.setCancelHandler(() => onDone?.call());
    _engine.setErrorHandler((_) => onDone?.call());
    _ready = true;
  }

  /// Préfère une voix de meilleure qualité parmi celles installées.
  Future<void> _applyBestVoice(String language) async {
    try {
      final voices = await _engine.getVoices;
      if (voices is! List) return;

      final wanted = language.replaceAll('_', '-').toLowerCase();
      final prefix = wanted.split('-').first;
      Map<String, String>? match;

      for (final voice in voices) {
        if (voice is! Map) continue;
        final rawLocale = voice['locale']?.toString();
        if (rawLocale == null || rawLocale.isEmpty) continue;

        final locale = rawLocale.replaceAll('_', '-').toLowerCase();
        if (locale != wanted && !locale.startsWith(prefix)) continue;

        final name = voice['name']?.toString() ?? '';
        if (name.isEmpty) continue;

        final candidate = {'name': name, 'locale': rawLocale};
        match ??= candidate;

        final quality =
            '${voice['quality'] ?? ''} ${voice['features'] ?? ''}'.toLowerCase();
        if (quality.contains('veryhigh') ||
            quality.contains('high') ||
            quality.contains('enhanced') ||
            quality.contains('network')) {
          match = candidate;
          break;
        }
      }

      if (match != null) await _engine.setVoice(match);
    } catch (e) {
      // Certains moteurs n'exposent pas leurs voix : la voix par défaut suffit.
      debugPrint('[TTS] Voix indisponible, voix par défaut utilisée : $e');
    }
  }
}
