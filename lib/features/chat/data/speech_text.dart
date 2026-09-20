import 'dart:ui';

/// Préparation du texte et détection de langue pour la lecture à voix haute.
///
/// Fonctions pures, testables sans moteur de synthèse vocale.

/// Emojis, pictogrammes et symboles non prononçables.
///
/// Dart ne propose pas les classes Unicode `\p{Emoji}` : on cible les plages
/// concernées, plus les sélecteurs de variation, le liant ZWJ et les marques
/// combinantes utilisées par les séquences emoji.
final _emojiRanges = RegExp(
  '['
  r'\u{1F000}-\u{1FAFF}' // pictogrammes, visages, drapeaux, symboles
  r'\u{2600}-\u{27BF}' // symboles divers, dingbats (☀ ✅ ✨ ➜…)
  r'\u{2B00}-\u{2BFF}' // flèches et symboles divers
  r'\u{2190}-\u{21FF}' // flèches
  r'\u{20D0}-\u{20FF}' // marques combinantes
  r'\u{20E3}' // touche encadrante (1️⃣)
  r'\u{FE0E}\u{FE0F}' // sélecteurs de variation
  r'\u{200D}' // liant ZWJ (👨‍👩‍👧)
  ']',
  unicode: true,
);

/// Retire la syntaxe Markdown et les emojis : on ne lit que le prononçable.
String stripMarkdownForSpeech(String markdown) {
  var text = markdown;

  // Blocs de code : le code n'est pas lu.
  text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  text = text.replaceAll(RegExp(r'~~~[\s\S]*?~~~'), ' ');
  // Code en ligne : on garde le contenu.
  text = text.replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m.group(1) ?? '');
  // Images puis liens : on garde le libellé.
  text = text.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );
  // Références de liens et notes de bas de page.
  text = text.replaceAll(RegExp(r'\[[^\]]*\]\[[^\]]*\]'), ' ');
  text = text.replaceAll(RegExp(r'\[\^[^\]]*\]'), ' ');
  // Titres, citations, listes.
  text = text.replaceAll(RegExp(r'^ {0,3}#{1,6} *', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^ {0,3}> ?', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^ {0,3}[-*+] +', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^ {0,3}\d+[.)] +', multiLine: true), '');
  // Règles horizontales.
  text = text.replaceAll(RegExp(r'^ {0,3}([-*_] *){3,}$', multiLine: true), ' ');
  // Emphase, gras, barré.
  text = text.replaceAll(RegExp(r'\*\*|__|\*|_|~~'), '');
  // Délimiteurs de tableaux.
  text = text.replaceAll(RegExp(r'^\s*\|.*\|\s*$', multiLine: true), ' ');
  // Emojis : jamais lus à voix haute.
  text = text.replaceAll(_emojiRanges, ' ');
  // Espaces et lignes excédentaires.
  text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
  text = text.replaceAll(RegExp(r'\n{2,}'), '\n');
  // Espaces restés en début/fin de ligne après suppression.
  text = text.replaceAll(RegExp(r' *\n *'), '\n');

  return text.trim();
}

/// Indices de français (mots outils entourés d'espaces).
const _frenchWords = [
  ' le ',
  ' la ',
  ' les ',
  ' un ',
  ' une ',
  ' des ',
  ' du ',
  ' est ',
  ' sont ',
  ' pour ',
  ' avec ',
  ' dans ',
  ' sur ',
  ' pas ',
  ' plus ',
  ' vous ',
  ' nous ',
  ' que ',
  ' qui ',
  ' cette ',
  ' votre ',
  ' au ',
  ' aux ',
  ' par ',
];

/// Indices d'anglais.
const _englishWords = [
  ' the ',
  ' and ',
  ' of ',
  ' to ',
  ' is ',
  ' are ',
  ' for ',
  ' with ',
  ' this ',
  ' that ',
  ' you ',
  ' your ',
  ' not ',
  ' in ',
  ' on ',
  ' have ',
  ' will ',
  ' can ',
];

final _frenchAccents = RegExp(r'[àâäçéèêëîïôöùûüœ]');

/// Langue de lecture : celle du texte, sinon celle de l'appareil.
///
/// Évite de lire une réponse française avec une voix anglaise (et inversement).
String resolveSpeechLanguage(String text, {Locale? deviceLocale}) {
  final locale = deviceLocale ?? PlatformDispatcher.instance.locale;
  final fallback = languageTag(locale);

  final padded = ' ${text.toLowerCase()} ';
  final accents = _frenchAccents.allMatches(padded).length;
  final frenchHits = _frenchWords.where(padded.contains).length;
  final englishHits = _englishWords.where(padded.contains).length;

  if (accents > 0 || frenchHits >= 2) return 'fr-FR';
  if (frenchHits > englishHits) return 'fr-FR';
  if (englishHits >= 2 && englishHits > frenchHits) return 'en-US';
  return fallback.isEmpty ? 'fr-FR' : fallback;
}

/// Balise BCP-47 (`fr-FR`) à partir d'une [Locale].
String languageTag(Locale locale) {
  final country = locale.countryCode;
  if (country == null || country.isEmpty) return locale.languageCode;
  return '${locale.languageCode}-$country';
}
