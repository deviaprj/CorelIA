import 'dart:math';

/// Injecte des hesitations naturelles ("euh", "hmm", pauses "...") dans le texte
/// destine au TTS pour un rendu plus humain.
///
/// Approche : post-processing deterministe du texte. Cela fonctionne avec
/// n'importe quel moteur TTS (OpenRouter, Edge, flutter_tts) sans dependance
/// a un LLM ou a un moteur specifique.
class VocalHesitationInjector {
  static final _random = Random();

  /// Liste de prefixes hesitants pour le debut de phrase.
  static const _prefixes = ['euh, ', 'hmm, ', 'ben, ', 'alors, '];

  /// Liste d'hesitations courtes apres une virgule.
  static const _midHesitations = ['euh', 'hum', 'ben'];

  /// Injecte des hesitations dans [text] avec une probabilite controlee
  /// par [intensity] (0.0 = aucune, 1.0 = tres frequente).
  static String inject(String text, {double intensity = 0.25}) {
    if (text.length < 15) return text;
    if (intensity <= 0) return text;

    var result = text;

    // 1. Prefixe hesitant au debut de la premiere phrase
    if (_random.nextDouble() < intensity * 0.4) {
      result = _injectPrefix(result);
    }

    // 2. Hesitations apres virgules de clause
    if (_random.nextDouble() < intensity * 0.25) {
      result = _injectAfterCommas(result);
    }

    // 3. Pauses "..." mid-sentence pour les phrases longues
    if (result.length > 80 && _random.nextDouble() < intensity * 0.2) {
      result = _injectPause(result);
    }

    return result;
  }

  static String _injectPrefix(String text) {
    // Ne pas injecter si le texte commence deja par une hesitation
    if (text.startsWith(RegExp(r'^(euh|hmm|ben|alors)[,\.\s]', caseSensitive: false))) {
      return text;
    }
    final prefix = _prefixes[_random.nextInt(_prefixes.length)];
    return prefix + text[0].toLowerCase() + text.substring(1);
  }

  static String _injectAfterCommas(String text) {
    // Matcher les virgules suivies d'un espace et un mot (pas URLs ni code)
    final regex = RegExp(r', ([a-zA-ZÀ-àÿ]+)');
    final matches = regex.allMatches(text).toList();
    if (matches.isEmpty) return text;

    // Choisir une virgule au hasard
    final match = matches[_random.nextInt(matches.length)];
    final hesitation = _midHesitations[_random.nextInt(_midHesitations.length)];

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
