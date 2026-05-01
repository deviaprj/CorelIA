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

  /// Supprime les emojis d’un texte pour le TTS.
  static String stripEmojis(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (!_isEmoji(rune)) buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  static bool _isEmoji(int rune) {
    return (rune >= 0x1F600 && rune <= 0x1F64F) || // emoticons
        (rune >= 0x1F300 && rune <= 0x1F5FF) || // symbols & pictographs
        (rune >= 0x1F680 && rune <= 0x1F6FF) || // transport & map
        (rune >= 0x1F1E0 && rune <= 0x1F1FF) || // flags
        (rune >= 0x2600 && rune <= 0x26FF) || // misc symbols
        (rune >= 0x2700 && rune <= 0x27BF) || // dingbats
        (rune >= 0xFE00 && rune <= 0xFE0F) || // variation selectors
        (rune >= 0x1F900 && rune <= 0x1F9FF) || // supplemental symbols
        (rune >= 0x1F000 && rune <= 0x1F02F) || // mahjong, domino
        (rune >= 0x1F0A0 && rune <= 0x1F0FF) || // playing cards
        (rune >= 0x1F100 && rune <= 0x1F1FF) || // enclosed alphanum
        (rune >= 0x1F700 && rune <= 0x1F77F) || // alchemical
        (rune >= 0x1F780 && rune <= 0x1F7FF) || // geometric
        (rune >= 0x1F800 && rune <= 0x1F8FF) || // arrows
        (rune >= 0x1FA00 && rune <= 0x1FA6F) || // chess etc
        (rune >= 0x1FA70 && rune <= 0x1FAFF) || // symbols extended-A
        (rune >= 0x2300 && rune <= 0x23FF) || // misc technical
        (rune == 0x00A9) || (rune == 0x00AE) || // copyright, registered
        (rune == 0x2122) || (rune == 0x3030) || // trademark, wavy dash
        (rune == 0x303D) || (rune == 0x3297) || // part alternation, congrats
        (rune == 0x3299) || // secret
        (rune >= 0x2B50 && rune <= 0x2B55); // stars
  }

  /// Nettoie le markdown pour le rendu TTS.
  /// Conserve la structure (paragraphes, listes) pour que le moteur natif
  /// fasse les pauses aux retours à la ligne et ponctuations.
  static String cleanMarkdown(String text) {
    // 1. Supprimer la section Sources et tout ce qui suit le séparateur final
    var working = _stripSourcesSection(text);

    // 2. Supprimer les citations entre crochets [1], [2], etc.
    working = working.replaceAll(RegExp(r'\[\d+\]'), '');

    return stripEmojis(working)
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

  /// Supprime la section Sources de la fin du texte.
  /// Reconnait les patterns : ---\n**Sources :**\n... ou \n\nSources :\n...
  static String _stripSourcesSection(String text) {
    // Pattern 1 : séparateur markdown --- suivi de Sources
    final sepPattern = RegExp(
      r'\n?\s*---+\s*\n?\s*\*\*Sources\s*:\*\*.*',
      caseSensitive: false,
      dotAll: true,
    );
    var result = text.replaceFirst(sepPattern, '');

    // Pattern 2 : Sources: sans séparateur (dernier recours)
    final plainPattern = RegExp(
      r'\n\n\s*Sources\s*:.*',
      caseSensitive: false,
      dotAll: true,
    );
    result = result.replaceFirst(plainPattern, '');

    return result;
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
