import 'dart:convert';

/// Service d'insertion de liaisons phonétiques pour le TTS.
///
/// En français, les liaisons rendent la parole naturelle :
/// "les amis" → "les zamis", "un ami" → "un nami", etc.
///
/// Ce service est un post-processeur de texte : il reçoit du texte
/// propre (après cleanMarkdown) et réécrit l'orthographe pour que
/// le TTS natif interprète la consonne de liaison comme l'attaque
/// de la syllabe suivante, sans entendre la lettre isolée
/// (ex: "les zétoiles" → [le.ze.twal], jamais [le zɛd e.twal]).
///
/// Approche : on réécrit le mot suivant pour qu'il commence par la
/// consonne de liaison (z, t, n, r) — le TTS applique alors ses
/// règles G2P naturelles sans pause entre les mots.
class PhoneticLiaisonService {
  /// Applique les liaisons phonétiques au [text] selon la [language].
  static String apply(String text, String language) {
    final lang = language.toLowerCase();
    if (lang.startsWith('fr')) {
      return _applyFrench(text);
    }
    if (lang.startsWith('en')) {
      return _applyEnglish(text);
    }
    if (lang.startsWith('es')) {
      return _applySpanish(text);
    }
    if (lang.startsWith('de')) {
      return _applyGerman(text);
    }
    if (lang.startsWith('it')) {
      return _applyItalian(text);
    }
    if (lang.startsWith('pt')) {
      return _applyPortuguese(text);
    }
    return text;
  }

  // ── Français ────────────────────────────────────────────────────────────────

  static String _applyFrench(String text) {
    var result = text;

    // Déterminants + voyelle : liaison obligatoire en [z] ou [n]
    // On réécrit le MOT SUIVANT pour commencer par la consonne de liaison,
    // ce qui force le TTS à l'interpréter comme l'attaque de la syllabe
    // suivante (ex: "les étoiles" → "les zétoiles" → [le.ze.twal]).
    result = result.replaceAllMapped(
      RegExp(r'\bles\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'les z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bun\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'un n${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bmon\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'mon n${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bton\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'ton n${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bson\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'son n${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bvotre\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'votre z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bnos\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'nos z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bmes\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'mes z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bces\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'ces z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bdeux\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'deux z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\btrois\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'trois z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bquatre\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'quatre z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bcinq\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'cinq z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bsix\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'six z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bdix\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'dix z${m.group(1)}',
    );

    // Adjectifs en -t + voyelle : liaison en [t]
    result = result.replaceAllMapped(
      RegExp(r'\bpetit\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'petit t${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bgros\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'gros z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\btout\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'tout t${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bfort\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'fort t${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bgrand\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'grand t${m.group(1)}',
    );

    // Verbes / pronoms + voyelle : liaison en [t] ou [z]
    result = result.replaceAllMapped(
      RegExp(r'\bsont\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'sont t${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bvont\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'vont t${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bfont\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'font t${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bont\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'ont t${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bplus\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'plus z${m.group(1)}',
    );

    // Prépositions + voyelle : liaison en [z] ou [n]
    // NOTE : on évite les liaisons en [ʁ] (sur, pour, par) car elles créent
    // un redoublement consonantique [ʁʁ] artificiel avec flutter_tts.
    result = result.replaceAllMapped(
      RegExp(r'\bdans\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'dans z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bchez\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'chez z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bvers\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'vers z${m.group(1)}',
    );

    // Liaisons avec "en" : "bien aimé", "rien à"
    result = result.replaceAllMapped(
      RegExp(r'\bben\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'bien n${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\brien\s+([aeiouyàâäéèêëîïôöùûüh])', caseSensitive: false),
      (m) => 'rien n${m.group(1)}',
    );

    // "et" ne fait PAS de liaison (règle standard)
    // "ou" ne fait pas de liaison non plus

    // Nettoyer les doubles espaces créés par les remplacements
    result = result.replaceAll(RegExp(r'\s+'), ' ');

    return result;
  }

  // ── Anglais — Linking R et linking sounds ─────────────────────────────────

  static String _applyEnglish(String text) {
    var result = text;

    // Linking R : word ending in -r/-re + vowel-initial word.
    // We rewrite the next word to start with 'r' so the TTS treats it
    // as the onset of the following syllable (e.g. "more apples" →
    // "more rapples" → [mɔːræpəlz]).
    result = result.replaceAllMapped(
      RegExp(r'\b(\w+)(r|re)\s+([aeiouy])', caseSensitive: false),
      (m) => '${m.group(1)}${m.group(2)} r${m.group(3)}',
    );

    // "hot apple" → "hot tapple" — [t] as onset of next syllable.
    result = result.replaceAllMapped(
      RegExp(r'\bhot\s+([aeiouy])', caseSensitive: false),
      (m) => 'hot t${m.group(1)}',
    );

    return result;
  }

  // ── Espagnol — Sinalefa y enlace ──────────────────────────────────────────

  static String _applySpanish(String text) {
    var result = text;

    // Sinalefa : vowel at end + vowel at start → merge (indicated by dash)
    result = result.replaceAllMapped(
      RegExp(r'\b(\w+)([aeiou])\s+([aeiou]\w+)', caseSensitive: false),
      (m) => '${m.group(1)}${m.group(2)}-${m.group(3)}',
    );

    // "los amigos" → "los zamigos"
    result = result.replaceAllMapped(
      RegExp(r'\blos\s+([aeiouy])', caseSensitive: false),
      (m) => 'los z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\blas\s+([aeiouy])', caseSensitive: false),
      (m) => 'las z${m.group(1)}',
    );

    return result;
  }

  // ── Allemand — Fugen-s et liaison ───────────────────────────────────────

  static String _applyGerman(String text) {
    var result = text;

    // "das ist" → liaison douce — make 's' the onset of the next word.
    result = result.replaceAllMapped(
      RegExp(r'\bdas\s+([aeiouyäöü])', caseSensitive: false),
      (m) => 'das s${m.group(1)}',
    );

    // "ein Apfel" → "ein nApfel"
    result = result.replaceAllMapped(
      RegExp(r'\bein\s+([aeiouyäöü])', caseSensitive: false),
      (m) => 'ein n${m.group(1)}',
    );

    return result;
  }

  // ── Italien — Raddoppiamento sintattico ───────────────────────────────────

  static String _applyItalian(String text) {
    var result = text;

    // "da Alessandro" → "da-Alessandro"
    result = result.replaceAllMapped(
      RegExp(r'\bda\s+([aeiou])', caseSensitive: false),
      (m) => 'da-${m.group(1)}',
    );

    return result;
  }

  // ── Portugais ───────────────────────────────────────────────────────────

  static String _applyPortuguese(String text) {
    var result = text;

    // "os amigos" → "os zamigos"
    result = result.replaceAllMapped(
      RegExp(r'\bos\s+([aeiouy])', caseSensitive: false),
      (m) => 'os z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bas\s+([aeiouy])', caseSensitive: false),
      (m) => 'as z${m.group(1)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bum\s+([aeiouy])', caseSensitive: false),
      (m) => 'um m${m.group(1)}',
    );

    return result;
  }
}
