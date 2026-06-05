/// Intention detectee lors d'un barge-in (interruption vocale).
enum BargeInIntent {
  /// Pas d'intention explicite detectee — probable bruit ou parole sans sens.
  none,

  /// Demande d'arret immediat.
  stop,

  /// Changement de sujet explicite.
  topicChange,

  /// Correction de ce qui vient d'etre dit.
  correction,

  /// Demande de repetition.
  repeat,
}

/// Classificateur d'intention pour le barge-in vocal.
///
/// Utilise des heuristiques regex (pas d'appel LLM) pour detecter si
/// l'utilisateur interrompt explicitement avec une intention claire.
/// Cela evite de couper l'IA sur un simple bruit ou une parole sans sens.
class BargeInIntentClassifier {
  static final _stopPatterns = RegExp(
    r'\b(stop|chut|tais-toi|tais toi|arrête|arrete|pause|silence|coupe|terminé|termine|fini|ça suffit|ca suffit)\b',
    caseSensitive: false,
  );

  static final _topicChangePatterns = RegExp(
    r"\b(changement de sujet|autre chose|nouveau sujet|parle-moi de|parle moi de|autre topic|passons à|passons a|on parle d'|parlons d')\b",
    caseSensitive: false,
  );

  static final _correctionPatterns = RegExp(
    r"\b(non|attends|une seconde|pas ça|pas ca|c'est pas ça|c'est pas ca|corrige|j'ai fait une erreur|je me trompe)\b",
    caseSensitive: false,
  );

  static final _repeatPatterns = RegExp(
    r"\b(répète|repete|redis|dis-le encore|dis le encore|encore|quoi\?|pardon|je n'ai pas compris|j'ai pas compris|tu peux répéter)\b",
    caseSensitive: false,
  );

  /// Classifie le transcript d'une interruption vocale.
  ///
  /// Retourne [BargeInIntent.none] pour :
  /// - Les entrees d'un seul mot (sauf "stop" ou "non")
  /// - Les transcripts qui ne matchent aucun pattern
  static BargeInIntent classify(String transcript) {
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) return BargeInIntent.none;

    final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    // Single-word shortcut
    if (words.length == 1) {
      final lower = words.first.toLowerCase();
      if (lower == 'stop' || lower == 'chut') return BargeInIntent.stop;
      if (lower == 'non') return BargeInIntent.correction;
      if (lower == 'encore' || lower == 'pardon' || lower == 'quoi') {
        return BargeInIntent.repeat;
      }
      return BargeInIntent.none;
    }

    // Multi-word : tester les patterns par priorite
    final lowerTranscript = trimmed.toLowerCase();

    if (_stopPatterns.hasMatch(lowerTranscript)) {
      return BargeInIntent.stop;
    }
    if (_topicChangePatterns.hasMatch(lowerTranscript)) {
      return BargeInIntent.topicChange;
    }
    if (_correctionPatterns.hasMatch(lowerTranscript)) {
      return BargeInIntent.correction;
    }
    if (_repeatPatterns.hasMatch(lowerTranscript)) {
      return BargeInIntent.repeat;
    }

    return BargeInIntent.none;
  }
}
