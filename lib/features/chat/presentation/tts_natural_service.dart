import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Service TTS 100 % autonome — lit tout le texte d’un coup
/// et attend réellement la fin avant de rendre la main.
class TtsNaturalService {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  double _speechRate = 0.50;
  double _pitch = 1.0;
  String _language = 'fr-FR';

  Future<void> init() async {
    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
    await _tts.setVolume(1.0);
  }

  Future<void> setSpeed(double rate) async {
    _speechRate = rate.clamp(0.5, 2.0);
    await _tts.setSpeechRate(_speechRate);
  }

  double get speed => _speechRate;

  Future<void> setPitch(double pitch) async {
    _pitch = pitch.clamp(0.5, 2.0);
    await _tts.setPitch(_pitch);
  }

  /// Nettoie le markdown pour le rendu TTS.
  /// Conserve la structure (paragraphes, listes) pour que le moteur natif
  /// fasse les pauses aux retours à la ligne et ponctuations.
  static String cleanMarkdown(String text) {
    return text
        // Gras et italique → texte brut
        .replaceAllMapped(RegExp(r'\*\*\*(.+?)\*\*\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'_(.+?)_'), (m) => m.group(1) ?? '')
        // Titres → texte + double saut de ligne (pause forte TTS)
        .replaceAllMapped(
          RegExp(r'^#{1,6}\s+(.+)$', multiLine: true),
          (m) => '${m.group(1) ?? ''}\n\n',
        )
        // Blocs de code → mention vocale
        .replaceAllMapped(
          RegExp(r'`{3}[\s\S]*?`{3}'),
          (_) => ' [bloc de code] .\n\n',
        )
        // Code inline → texte brut
        .replaceAllMapped(RegExp(r'`(.+?)`'), (m) => m.group(1) ?? '')
        // Séparateurs → pause
        .replaceAll(RegExp(r'^-{3,}\s*$', multiLine: true), '\n\n')
        // Liens markdown → texte seul
        .replaceAllMapped(RegExp(r'\[(.+?)\]\(.+?\)'), (m) => m.group(1) ?? '')
        // Images → description
        .replaceAllMapped(RegExp(r'!\[(.*?)\]\(.+?\)'), (m) {
          final alt = m.group(1);
          return alt != null && alt.isNotEmpty ? ' [image: $alt] ' : ' [image] ';
        })
        // Listes à puces → item seul sur sa ligne (pause natuelle au \n)
        .replaceAllMapped(
          RegExp(r'^\s*[-*+]\s+(.+)$', multiLine: true),
          (m) => '${m.group(1) ?? ''}\n',
        )
        // Listes numérotées → item seul sur sa ligne
        .replaceAllMapped(
          RegExp(r'^\s*\d+\.\s+(.+)$', multiLine: true),
          (m) => '${m.group(1) ?? ''}\n',
        )
        // Citations → texte brut
        .replaceAll(RegExp(r'^>\s+', multiLine: true), '')
        // HTML basique
        .replaceAll(RegExp(r'<[^>]+>'), '')
        // Nettoyage espaces multiples
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        // Normaliser sauts de ligne
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Lit tout le texte d’une traite et attend la fin réelle de la parole.
  Future<void> speakNaturally(String text) async {
    if (_isSpeaking) await stop();

    final cleaned = cleanMarkdown(text);
    if (cleaned.trim().isEmpty) return;

    _isSpeaking = true;
    final completer = Completer<void>();

    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });

    try {
      await _tts.speak(cleaned);
      // Attendre que la parole se termine ou que stop() soit appelé
      while (_isSpeaking && !completer.isCompleted) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      debugPrint('[TtsNaturalService] Error during speech: $e');
    } finally {
      _tts.setCompletionHandler(() {});
      _isSpeaking = false;
    }
  }

  Future<void> stop() async {
    _isSpeaking = false;
    await _tts.stop();
  }

  bool get isSpeaking => _isSpeaking;

  void dispose() {
    _isSpeaking = false;
    _tts.stop();
  }
}
