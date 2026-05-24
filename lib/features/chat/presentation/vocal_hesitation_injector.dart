import 'dart:math';

/// Injecte des hesitations naturelles dans le texte destine au TTS
/// pour un rendu plus humain.
///
/// Approche : post-processing deterministe du texte. Cela fonctionne avec
/// n'importe quel moteur TTS (OpenRouter, Edge, flutter_tts) sans dependance
/// a un LLM ou a un moteur specifique.
///
/// Support multilingue : FR, EN, ES, DE, IT, PT.
class VocalHesitationInjector {
  static final _random = Random();

  /// Hesitations par langue.
  static const _prefixesByLang = <String, List<String>>{
    'fr': ['euh, ', 'hmm, ', 'ben, ', 'alors, '],
    'en': ['uh, ', 'um, ', 'well, ', 'so, '],
    'es': ['eh, ', 'este, ', 'bueno, ', 'pues, '],
    'de': ['äh, ', 'hm, ', 'also, ', 'naja, '],
    'it': ['ehm, ', 'beh, ', 'allora, ', 'insomma, '],
    'pt': ['eh, ', 'hum, ', 'então, ', 'bom, '],
  };

  static const _midHesitationsByLang = <String, List<String>>{
    'fr': ['euh', 'hum', 'ben'],
    'en': ['uh', 'um', 'hmm'],
    'es': ['eh', 'este', 'pues'],
    'de': ['äh', 'hm', 'also'],
    'it': ['ehm', 'beh', 'dunque'],
    'pt': ['eh', 'hum', 'então'],
  };

  /// Injecte des hesitations dans [text] avec une probabilite controlee
  /// par [intensity] (0.0 = aucune, 1.0 = tres frequente).
  /// [language] doit etre un code ISO a 2 lettres ('fr', 'en', etc.).
  static String inject(String text, {
    double intensity = 0.25,
    String language = 'fr',
  }) {
    if (text.length < 15) return text;
    if (intensity <= 0) return text;

    final lang = _resolveLang(language);
    final prefixes = _prefixesByLang[lang] ?? _prefixesByLang['fr']!;
    final midHes = _midHesitationsByLang[lang] ?? _midHesitationsByLang['fr']!;

    var result = text;

    // 1. Prefixe hesitant au debut de la premiere phrase
    if (_random.nextDouble() < intensity * 0.4) {
      result = _injectPrefix(result, prefixes);
    }

    // 2. Hesitations apres virgules de clause
    if (_random.nextDouble() < intensity * 0.25) {
      result = _injectAfterCommas(result, midHes);
    }

    // 3. Pauses "..." mid-sentence pour les phrases longues
    if (result.length > 80 && _random.nextDouble() < intensity * 0.2) {
      result = _injectPause(result);
    }

    return result;
  }

  static String _resolveLang(String language) {
    final l = language.toLowerCase();
    if (l.startsWith('fr')) return 'fr';
    if (l.startsWith('en')) return 'en';
    if (l.startsWith('es')) return 'es';
    if (l.startsWith('de')) return 'de';
    if (l.startsWith('it')) return 'it';
    if (l.startsWith('pt')) return 'pt';
    return 'fr';
  }

  static String _injectPrefix(String text, List<String> prefixes) {
    // Ne pas injecter si le texte commence deja par une hesitation
    final allPrefixes = prefixes.expand((p) => [p.trimRight()]).toList();
    final pattern = RegExp(
      '^(${allPrefixes.join('|')})[,.\\s]',
      caseSensitive: false,
    );
    if (text.startsWith(pattern)) return text;
    final prefix = prefixes[_random.nextInt(prefixes.length)];
    return prefix + text[0].toLowerCase() + text.substring(1);
  }

  static String _injectAfterCommas(String text, List<String> hesitations) {
    // Matcher les virgules suivies d'un espace et un mot (pas URLs ni code)
    final regex = RegExp(r', ([a-zA-ZÀ-àÿÀ-ſ]+)');
    final matches = regex.allMatches(text).toList();
    if (matches.isEmpty) return text;

    // Eviter de mettre deux hesitations dans la meme phrase
    final match = matches[_random.nextInt(matches.length)];
    final hesitation = hesitations[_random.nextInt(hesitations.length)];

    // Inserer apres la virgule et l'espace
    final index = match.end - match.group(1)!.length;
    return text.substring(0, index) + '$hesitation ' + text.substring(index);
  }

  static String _injectPause(String text) {
    // Trouver un espace environ au milieu du texte, eviter les URLs et le code
    final mid = text.length ~/ 2;
    final spaceIndex = text.lastIndexOf(' ', mid + 10);
    if (spaceIndex <= 0 || spaceIndex < mid - 10) return text;

    // Ne pas inserer de pause dans une URL ou du markdown
    final before = text.substring(spaceIndex - 5, spaceIndex + 5);
    if (before.contains('http') || before.contains('`') || before.contains('**')) {
      return text;
    }

    return text.substring(0, spaceIndex) + '...' + text.substring(spaceIndex);
  }
}
