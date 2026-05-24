import 'tts_emotion.dart';

/// Parse les balises prosodiques du texte LLM et extrait l'émotion + le texte nettoyé.
///
/// Balises supportées : [joyeux], [triste], [sérieux], [excité], [neutre], [joyeux], [amical], [enthousiaste]
///
/// Exemple d'entrée : "[joyeux] Salut ! Comment ça va aujourd'hui ?"
/// Sortie : EmotionParseResult(emotion: TtsEmotion.joyful, cleanText: "Salut ! Comment ça va aujourd'hui ?")
class EmotionParser {
  /// Mapping balise → émotion.
  static const _tagToEmotion = {
    '[joyeux]': TtsEmotion.joyful,
    '[heureux]': TtsEmotion.joyful,
    '[content]': TtsEmotion.joyful,
    '[amusé]': TtsEmotion.joyful,
    '[rires]': TtsEmotion.joyful,
    '[riant]': TtsEmotion.joyful,
    '[sourire]': TtsEmotion.joyful,
    '[souriant]': TtsEmotion.joyful,
    '[triste]': TtsEmotion.sad,
    '[melancolique]': TtsEmotion.sad,
    '[sérieux]': TtsEmotion.serious,
    '[grave]': TtsEmotion.serious,
    '[excité]': TtsEmotion.excited,
    '[enthousiaste]': TtsEmotion.excited,
    '[neutre]': TtsEmotion.neutral,
    '[calme]': TtsEmotion.neutral,
    '[amical]': TtsEmotion.friendly,
    '[chaleureux]': TtsEmotion.friendly,
  };

  /// Pattern regex pour capturer toutes les balises entre crochets.
  static final _tagPattern = RegExp(r'\[([^\]]+)\]');

  /// Parse le texte et retourne l'émotion détectée + le texte nettoyé.
  static EmotionParseResult parse(String text) {
    TtsEmotion? detectedEmotion;
    var cleanText = text;

    // Chercher toutes les balises dans le texte
    for (final match in _tagPattern.allMatches(text)) {
      final tag = '[${match.group(1)?.toLowerCase().trim()}]';
      final emotion = _tagToEmotion[tag];
      if (emotion != null) {
        // Garder uniquement la première émotion trouvée
        detectedEmotion ??= emotion;
      }
    }

    // Retirer toutes les balises du texte
    cleanText = _tagPattern.allMatches(text).fold<String>(text, (acc, match) {
      final tag = '[${match.group(1)?.toLowerCase().trim()}]';
      if (_tagToEmotion.containsKey(tag)) {
        return acc.replaceAll(tag, '');
      }
      return acc;
    });

    // Nettoyer les espaces multiples et les espaces en début
    cleanText = cleanText.replaceAll(RegExp(r'\s+'), ' ').trim();

    return EmotionParseResult(
      emotion: detectedEmotion ?? TtsEmotion.neutral,
      cleanText: cleanText,
      hasEmotionTag: detectedEmotion != null,
    );
  }

  /// Déduit l'émotion à partir du contenu du texte (sans balises).
  /// Heuristique simple basée sur la ponctuation et les mots-clés.
  static TtsEmotion inferFromText(String text) {
    final lower = text.toLowerCase();

    // Mots-clés positifs
    if (_containsAny(lower, ['super', 'génial', 'excellent', 'bravo', 'fantastique', 'magnifique'])) {
      return TtsEmotion.excited;
    }
    if (_containsAny(lower, ['bonjour', 'salut', 'bienvenue', 'bon', 'merci', 'joli'])) {
      return TtsEmotion.joyful;
    }
    if (_containsAny(lower, ['désolé', 'malheureusement', 'triste', 'regret', 'perte', 'douleur'])) {
      return TtsEmotion.sad;
    }
    if (_containsAny(lower, ['attention', 'important', 'urgent', 'danger', 'avertissement'])) {
      return TtsEmotion.serious;
    }

    // Ponctuation expressive
    if (text.contains('!!!') || text.contains('??')) {
      return TtsEmotion.excited;
    }
    if (text.contains('...') && text.length < 100) {
      return TtsEmotion.sad;
    }

    return TtsEmotion.neutral;
  }

  static bool _containsAny(String text, List<String> keywords) {
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  /// Mapping balise émotion → emoji pour l'affichage UI.
  static const _tagToEmoji = {
    '[joyeux]': '😊',
    '[heureux]': '😊',
    '[content]': '🙂',
    '[amusé]': '😄',
    '[rires]': '😂',
    '[riant]': '😆',
    '[sourire]': '😊',
    '[souriant]': '😊',
    '[triste]': '😢',
    '[melancolique]': '😔',
    '[sérieux]': '😐',
    '[grave]': '😐',
    '[excité]': '🤩',
    '[enthousiaste]': '🎉',
    '[neutre]': '',
    '[calme]': '😌',
    '[amical]': '🤗',
    '[chaleureux]': '🔥',
  };

  /// Remplace les balises émotionnelles par des emojis pour l'affichage UI.
  static String toUiText(String text) {
    var result = text;
    for (final match in _tagPattern.allMatches(text)) {
      final rawTag = match.group(1)?.toLowerCase().trim() ?? '';
      final tag = '[$rawTag]';
      final emoji = _tagToEmoji[tag];
      if (emoji != null) {
        result = result.replaceFirst(tag, emoji);
      }
    }
    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Retire les balises émotionnelles du texte pour l'affichage UI (legacy).
  static String stripEmotionTags(String text) {
    return _tagPattern.allMatches(text).fold<String>(text, (acc, match) {
      final tag = '[${match.group(1)?.toLowerCase().trim()}]';
      if (_tagToEmotion.containsKey(tag)) {
        return acc.replaceAll(tag, '');
      }
      return acc;
    }).replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

/// Résultat du parsing d'émotion.
class EmotionParseResult {
  final TtsEmotion emotion;
  final String cleanText;
  final bool hasEmotionTag;

  const EmotionParseResult({
    required this.emotion,
    required this.cleanText,
    required this.hasEmotionTag,
  });
}