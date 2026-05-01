import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Types de segments pour le TTS naturel.
enum TtsSegmentType {
  phrase,
  paragraphBreak,
  listBreak,
  codeBlock,
}

class TtsSegment {
  final String text;
  final TtsSegmentType type;

  const TtsSegment(this.text, this.type);
}

/// Service TTS naturel avec découpage intelligent et pauses.
/// 100% autonome — utilise flutter_tts natif uniquement.
class TtsNaturalService {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  double _speechRate = 0.55;
  double _pitch = 1.0;
  String _language = 'fr-FR';

  /// Initialise le TTS avec les paramètres par défaut.
  Future<void> init() async {
    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
    await _tts.setVolume(1.0);
  }

  /// Met à jour la vitesse de lecture (0.5 — 2.0).
  Future<void> setSpeed(double rate) async {
    _speechRate = rate.clamp(0.5, 2.0);
    await _tts.setSpeechRate(_speechRate);
  }

  double get speed => _speechRate;

  /// Met à jour la hauteur de voix.
  Future<void> setPitch(double pitch) async {
    _pitch = pitch.clamp(0.5, 2.0);
    await _tts.setPitch(_pitch);
  }

  /// Nettoie le markdown pour le rendu TTS.
  static String cleanMarkdown(String text) {
    return text
        // Gras et italique
        .replaceAllMapped(RegExp(r'\*\*\*(.+?)\*\*\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'_(.+?)_'), (m) => m.group(1) ?? '')
        // Titres
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        // Code inline et blocs
        .replaceAllMapped(RegExp(r'`{3}[\s\S]*?`{3}'), (_) => ' [bloc de code] ')
        .replaceAllMapped(RegExp(r'`(.+?)`'), (m) => m.group(1) ?? '')
        // Séparateurs
        .replaceAll(RegExp(r'^-{3,}\s*$', multiLine: true), '\n')
        // Liens markdown [texte](url)
        .replaceAllMapped(RegExp(r'\[(.+?)\]\(.+?\)'), (m) => m.group(1) ?? '')
        // Images markdown ![alt](url)
        .replaceAllMapped(RegExp(r'!\[(.*?)\]\(.+?\)'), (m) {
          final alt = m.group(1);
          return alt != null && alt.isNotEmpty ? ' [image: $alt] ' : ' [image] ';
        })
        // Listes à puces
        .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
        // Listes numérotées
        .replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '')
        // HTML basique
        .replaceAll(RegExp(r'<[^>]+>'), '')
        // Citations
        .replaceAll(RegExp(r'^>\s+', multiLine: true), '')
        // Nettoyage espaces multiples
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Découpe le texte en segments avec type de pause associé.
  static List<TtsSegment> splitIntoSegments(String text) {
    final cleaned = cleanMarkdown(text);
    final segments = <TtsSegment>[];

    // Découper par paragraphes d'abord
    final paragraphs = cleaned.split(RegExp(r'\n{2,}'));

    for (var p = 0; p < paragraphs.length; p++) {
      final paragraph = paragraphs[p].trim();
      if (paragraph.isEmpty) continue;

      // Détecter si c'est une liste (lignes commençant par des puces ou numéros)
      final lines = paragraph.split('\n');
      if (lines.length > 1) {
        // Traiter chaque élément de liste comme une phrase
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;
          segments.add(TtsSegment(line, TtsSegmentType.phrase));
        }
        if (p < paragraphs.length - 1) {
          segments.add(TtsSegment('', TtsSegmentType.listBreak));
        }
      } else {
        // Découper par phrases
        final sentences = paragraph.split(RegExp(r'(?<=[.!?])\s+'));
        for (var i = 0; i < sentences.length; i++) {
          final sentence = sentences[i].trim();
          if (sentence.isEmpty) continue;
          segments.add(TtsSegment(sentence, TtsSegmentType.phrase));
        }
        if (p < paragraphs.length - 1) {
          segments.add(TtsSegment('', TtsSegmentType.paragraphBreak));
        }
      }
    }

    return segments;
  }

  /// Retourne la durée de pause à appliquer après un segment.
  static Duration pauseFor(TtsSegmentType type) {
    switch (type) {
      case TtsSegmentType.phrase:
        return const Duration(milliseconds: 350);
      case TtsSegmentType.paragraphBreak:
        return const Duration(milliseconds: 900);
      case TtsSegmentType.listBreak:
        return const Duration(milliseconds: 600);
      case TtsSegmentType.codeBlock:
        return const Duration(milliseconds: 400);
    }
  }

  /// Lit le texte de manière naturelle, phrase par phrase avec pauses.
  /// Cette méthode est async et gère l'interruption via [stop].
  Future<void> speakNaturally(String text) async {
    if (_isSpeaking) await stop();
    if (text.trim().isEmpty) return;

    final segments = splitIntoSegments(text);
    _isSpeaking = true;

    try {
      for (final segment in segments) {
        if (!_isSpeaking) break;

        if (segment.type == TtsSegmentType.codeBlock) {
          await _tts.speak(segment.text);
        } else if (segment.text.isNotEmpty) {
          await _tts.speak(segment.text);
        }

        if (!_isSpeaking) break;

        // Pause après chaque segment
        final pause = pauseFor(segment.type);
        if (pause.inMilliseconds > 0) {
          await Future<void>.delayed(pause);
        }
      }
    } catch (e) {
      debugPrint('[TtsNaturalService] Error during speech: $e');
    } finally {
      _isSpeaking = false;
    }
  }

  /// Arrête immédiatement la lecture.
  Future<void> stop() async {
    _isSpeaking = false;
    await _tts.stop();
  }

  bool get isSpeaking => _isSpeaking;

  void dispose() {
    _tts.stop();
  }
}
