import '../../../../core/language/language_service.dart' as lang;

/// Extracteur de paramètres de voyage (vols + météo) depuis le langage naturel.
///
/// Source unique (ADR-029) pour l'analyse des requêtes de vol (villes +
/// dates) et météo (ville + code postal). Unifie les deux implémentations
/// parallèles qui existaient avant le Bloc 3 :
///
/// - `ChatNotifier` (presentation/chat_notifier.dart) — regex mois FR/EN
///   seulement, mais `_normalizeDate` sûr (`int.parse` + try/catch →
///   retourne la chaîne brute sur entrée invalide).
/// - `SearchIntentExtractor` (data/search_intent_extractor.dart) — regex
///   mois 6 langues (FR/EN/ES/DE/IT/PT), mais `_normalizeDate` non sûr
///   (string padLeft → produisait `'date-0a-not'` pour `'not-a-date'`).
///
/// La version unifiée conserve le meilleur des deux : regex 6 langues
/// (surensemble — les cas FR/EN passent à l'identique) et `_normalizeDate`
/// sûr. Les stop-words sont l'union des deux listes (45 de `ChatNotifier`
/// + `'un'` de `SearchIntentExtractor`) pour ne régresser aucun des deux
/// chemins.
///
/// Toutes les méthodes sont statiques et pures (aucun état, aucune IO) →
/// testable isolément, sans `ProviderContainer` ni `ChatNotifier`.
class TravelParamsParser {
  TravelParamsParser._(); // classe utilitaire — pas d'instances

  /// Motif regex des noms de mois (FR/EN/ES/DE/IT/PT) pour la capture dans
  /// les regex de dates textuelles. **Source unique** (ADR-029) —
  /// `SearchIntentExtractor._getMonthPattern` délègue vers cette constante
  /// pour éviter la duplication des deux regex parallèles (l'ancienne copie
  /// dans `chat_notifier` était FR/EN seulement ; celle de
  /// `search_intent_extractor` était complète mais dupliquée).
  static const String monthPattern = r'[Jj]anvier|[Ff]évrier|[Ff]evrier|'
      r'[Mm]ars|[Aa]vril|[Mm]ai|[Jj]uin|'
      r'[Jj]uillet|[Aa]oût|[Aa]out|[Ss]eptembre|[Oo]ctobre|[Nn]ovembre|'
      r'[Dd]écembre|[Dd]ecembre|'
      r'[Jj]anuary|[Ff]ebruary|[Mm]arch|[Aa]pril|[Mm]ay|[Jj]une|[Jj]uly|'
      r'[Aa]ugust|[Ss]eptember|[Oo]ctober|[Nn]ovember|[Dd]ecember|'
      r'[Ee]nero|[Ff]ebrero|[Mm]arzo|[Aa]bril|[Mm]ayo|[Jj]unio|[Jj]ulio|'
      r'[Aa]gosto|[Ss]eptiembre|[Oo]ctubre|[Nn]oviembre|[Dd]iciembre|'
      r'[Jj]anuar|[Ff]ebruar|[Mm]arz|[Aa]pril|[Mm]ai|[Jj]uni|[Jj]uli|'
      r'[Aa]ugust|[Ss]eptember|[Oo]ktober|[Nn]ovember|[Dd]ezember|'
      r'[Gg]ennaio|[Ff]ebbraio|[Mm]arzo|[Aa]prile|[Mm]aggio|[Gg]iugno|'
      r'[Ll]uglio|[Aa]gosto|[Ss]ettembre|[Oo]ttobre|[Nn]ovembre|[Dd]icembre|'
      r'[Jj]aneiro|[Ff]evereiro|[Mm]arço|[Mm]arco|[Aa]bril|[Mm]aio|'
      r'[Jj]unho|[Jj]ulho|[Aa]gosto|[Ss]etembro|[Oo]utubro|[Nn]ovembro|'
      r'[Dd]ezembro';

  /// Valider que deux noms extraits ressemblent à des villes, pas des mots
  /// parasites de la requête (vol, billet, aller, retour, etc.). Les noms
  /// de villes font 1-3 mots (ex. « New York », « Sao Paulo »).
  static bool isValidCityPair(String from, String to) {
    const garbageTerms = [
      'trouve', 'trouver', 'cherche', 'chercher', 'billet', 'billets',
      'vol', 'vols', 'avion', 'aller', 'retour', 'direct', 'recherche',
      'reservation', 'reserver', 'partir', 'depart', 'arrivee',
      'flight', 'flights', 'ticket', 'find', 'search', 'cheap',
    ];
    final fromWords = from.split(' ').length;
    final toWords = to.split(' ').length;
    if (fromWords > 3 || toWords > 3) return false;
    final fromLower = from.toLowerCase();
    final toLower = to.toLowerCase();
    for (final term in garbageTerms) {
      if (fromLower == term || toLower == term) return false;
      if (fromLower.contains(' $term ') || toLower.contains(' $term ')) {
        return false;
      }
      if (fromLower.startsWith('$term ') || toLower.startsWith('$term ')) {
        return false;
      }
      if (fromLower.endsWith(' $term') || toLower.endsWith(' $term')) {
        return false;
      }
    }
    return true;
  }

  /// Mots-clés de voyage multilingues (FR/EN/ES/DE/IT/PT) susceptibles d'être
  /// capitalisés en tête de requête et capturés à tort dans le nom de ville par
  /// la regex `cityName` (ex. « Flug Berlin Hamburg » → `from` capturé
  /// « Flug Berlin »). Retirés en post-traitement du résultat. Les variantes
  /// minuscules ('vol', 'direct'…) ne sont jamais capturées par `cityName`
  /// ([A-ZÀ-Ÿ]…), donc ce strip ne touche que les mots-clés capitalisés.
  static const Set<String> _travelKeywords = {
    // FR
    'vol', 'vols', 'billet', 'billets', 'avion', 'avions',
    'aller', 'retour', 'direct', 'directs',
    // EN
    'flight', 'flights', 'ticket', 'tickets',
    // ES
    'vuelo', 'vuelos', 'billete', 'billetes',
    // DE
    'flug', 'flüge',
    // IT
    'volo', 'voli', 'biglietto', 'biglietti',
    // PT
    'voo', 'voos', 'passagem', 'passagens',
  };

  /// Retire itérativement les mots-clés de voyage capitalisés en tête du nom
  /// de ville capturé (ex. « Flug Berlin » → « Berlin »). S'arrête au premier
  /// mot qui n'est pas un mot-clé pour préserver les villes composées
  /// (« New York », « Sao Paulo »). Un seul mot sans espace → retourné tel
  /// quel (« Paris », « Zagreb »).
  static String _stripLeadingKeyword(String city) {
    var c = city.trim();
    while (true) {
      final i = c.indexOf(' ');
      if (i <= 0) break; // un seul mot (ou vide) → on garde tel quel
      final first = c.substring(0, i).toLowerCase();
      if (!_travelKeywords.contains(first)) break;
      c = c.substring(i + 1).trim();
    }
    return c;
  }

  /// Capitalise la première lettre de chaque mot (délimiteurs : début, espace,
  /// tiret) sans toucher aux accents internes. Utilisé par les replis de
  /// `parseFlightParams` et `extractCity` pour normaliser les requêtes
  /// minuscules (« météo paris » → « Météo Paris », « paris-londre » →
  /// « Paris-Londre »).
  ///
  /// **Pourquoi pas `\b([a-zà-ÿ])` ?** En Dart (regex ECMAScript), `\w` ne
  /// couvre que `[A-Za-z0-9_]` — les accents sont des caractères non-mot, donc
  /// `\b` marque une frontière à **chaque** accent. « météo » devient alors
  /// « MÉTÉO » (chaque `é` capitalisé), et le mot-clé `[Mm]étéo` (sensible à la
  /// casse) ne matche plus (`É` ≠ `é`) → l'extraction échouait silencieusement
  /// (bug ADR-029, cas « météo paris »). Le motif `(^|[\s-])` ne déclenche la
  /// capitalisation qu'après un délimiteur réel (début / espace / tiret), donc
  /// « météo » → « Météo », « août » → « Août », et « paris-londre » →
  /// « Paris-Londre » (le tiret reste un délimiteur — requis par les tests
  /// de vol à trait d'union).
  static String _capitalizeWords(String s) {
    return s.replaceAllMapped(
      RegExp(r'(^|[\s-])([a-zà-ÿ])'),
      (m) => '${m.group(1)}${m.group(2)!.toUpperCase()}',
    );
  }

  /// Parse les paramètres de vol depuis le langage naturel.
  ///
  /// Gère : « Paris-Zagreb du 29 mai au 2 juin »,
  /// « vol Paris-Zagreb du 29/05 au 02/06 »,
  /// « billet avion Paris Zagreb 15 juin », etc.
  ///
  /// Retourne `{'from', 'to', 'departDate'[, 'returnDate']}` ou `null`.
  static Map<String, String>? parseFlightParams(String message) {
    // Essayer le message original d'abord (gère l'entrée déjà capitalisée).
    var result = _tryParseFlightParams(message);
    if (result == null) {
      // Repli : nettoyer les stop-words + capitaliser pour les requêtes
      // minuscules (« vol paris-londre » → « Paris-Londre »).
      final cleaned = _sanitizeFlightQuery(message);
      final capitalized = _capitalizeWords(cleaned);
      if (capitalized != cleaned) {
        result = _tryParseFlightParams(capitalized);
      }
    }
    if (result == null) return null;
    // Post-traitement : retire les mots-clés de voyage capitalisés capturés à
    // tort en tête du nom de ville (ex. « Flug Berlin » → « Berlin »). Appliqué
    // sur les deux chemins (original + repli) au même endroit → DRY. Fix ADR-029.
    result['from'] = _stripLeadingKeyword(result['from']!);
    result['to'] = _stripLeadingKeyword(result['to']!);
    return result;
  }

  /// Supprimer les stop-words liés au vol qui interfèrent avec l'extraction
  /// des villes. Union des listes historiques `ChatNotifier` (45) +
  /// `SearchIntentExtractor` (+ `'un'`).
  static String _sanitizeFlightQuery(String msg) {
    const stopWords = [
      'vol', 'vols', 'billet', 'billets', 'avion', 'avions',
      'aller', 'retour', 'direct', 'directs', 'cher', 'chers',
      'moins', 'trouver', 'trouve', 'cherche', 'chercher',
      'recherche', 'rechercher', 'depart', 'arrivee', 'reservation',
      'reserver', 'partir', 'pour', 'via', 'avec', 'sur',
      'flight', 'flights', 'ticket', 'tickets', 'cheap', 'find',
      'search', 'one', 'way', 'round', 'trip', 'from', 'and',
      'pas', 'les', 'des', 'un', 'une', 'mon', 'mes', 'ton', 'tes',
      'son', 'ses', 'notre', 'nos', 'votre', 'vos', 'leur', 'leurs',
      'quel', 'quels', 'quelle', 'quelles', 'est', 'sont',
      'me', 'le', 'la', 'du', 'de', 'au', 'aux',
    ];
    var cleaned = msg;
    for (final w in stopWords) {
      cleaned = cleaned.replaceAll(RegExp('\\b$w\\b', caseSensitive: false), ' ');
    }
    // Coller les espaces multiples.
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Map<String, String>? _tryParseFlightParams(String message) {
    const cityName = r'[A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?';
    const numericDate = r'\d{1,2}[/.-]\d{1,2}(?:[/.-]\d{2,4})?';

    // Pattern A : « City1-City2 du DD mois au DD mois » (tiret, dates textuelles)
    // Ex. « Paris-Zagreb du 29 mai au 2 juin »
    final hyphenTextDates = RegExp(
      '($cityName)\\s*-\\s*($cityName)\\b'
      r'.{0,30}?'
      r'(?:d[ue]|le|départ\s+le)\s+(\d{1,2})\s+'
      '($monthPattern)'
      r'(?:\s*(?:au|retour(?:\s+le)?)\s+(\d{1,2})\s+(' + monthPattern + r'))?',
    );
    final matchA = hyphenTextDates.firstMatch(message);
    if (matchA != null) {
      final d1 = int.parse(matchA.group(3)!);
      final m1 = lang.parseMonth(matchA.group(4)!);
      final y = DateTime.now().year;
      final departDate =
          '$y-${m1.toString().padLeft(2, '0')}-${d1.toString().padLeft(2, '0')}';
      String? returnDate;
      if (matchA.group(5) != null) {
        final d2 = int.parse(matchA.group(5)!);
        final m2 = lang.parseMonth(matchA.group(6)!);
        returnDate =
            '$y-${m2.toString().padLeft(2, '0')}-${d2.toString().padLeft(2, '0')}';
      }
      return {
        'from': matchA.group(1)!.trim(),
        'to': matchA.group(2)!.trim(),
        'departDate': departDate,
        if (returnDate != null) 'returnDate': returnDate,
      };
    }

    // Pattern B : « City1-City2 [du/le] date1 [au date2] » (tiret, dates numériques).
    // Ex. « Paris-Zagreb du 29/05/2026 au 02/06/2026 », mais aussi « Paris-Londre 29/05 »
    // (sans « du »/« le ») — cas issu du repli sanitize+capitalize qui retire les
    // stop-words dont « du » (ADR-029 : « trouve un billet paris-londre direct du 29/05 »).
    // « du »/« le » est optionnel, comme dans pattern D (symétrie avec le cas espace).
    final hyphenNumDates = RegExp(
      '($cityName)\\s*-\\s*($cityName)\\b'
      r'.{0,20}?'
      '(?:d[ue]|le)?\\s*(' + numericDate + r')'
      r'(?:\s+(?:au|retour)\s+(' + numericDate + r'))?',
    );
    final matchB = hyphenNumDates.firstMatch(message);
    if (matchB != null) {
      return {
        'from': matchB.group(1)!.trim(),
        'to': matchB.group(2)!.trim(),
        'departDate': normalizeDate(matchB.group(3)!),
        if (matchB.group(4) != null)
          'returnDate': normalizeDate(matchB.group(4)!),
      };
    }

    // Pattern C : « City1 City2 du DD mois au DD mois » (espace, dates textuelles)
    // Ex. « vol Paris Zagreb du 29 mai au 2 juin », « vol direct Paris Zagreb 29 mai 2026 »
    final spaceTextDates = RegExp(
      '($cityName)\\s+'
      r'(?:à|vers|pour|-)?\s*'
      '($cityName)\\b'
      r'.{0,30}?'
      r'(?:d[ue]|le\s+)?(\d{1,2})\s+'
      '($monthPattern)'
      r'(?:\s*(?:au|retour)\s+(\d{1,2})\s+(' + monthPattern + r'))?',
    );
    final matchC = spaceTextDates.firstMatch(message);
    if (matchC != null) {
      final d1 = int.parse(matchC.group(3)!);
      final m1 = lang.parseMonth(matchC.group(4)!);
      final y = DateTime.now().year;
      final departDate =
          '$y-${m1.toString().padLeft(2, '0')}-${d1.toString().padLeft(2, '0')}';
      String? returnDate;
      if (matchC.group(5) != null) {
        final d2 = int.parse(matchC.group(5)!);
        final m2 = lang.parseMonth(matchC.group(6)!);
        returnDate =
            '$y-${m2.toString().padLeft(2, '0')}-${d2.toString().padLeft(2, '0')}';
      }
      return {
        'from': matchC.group(1)!.trim(),
        'to': matchC.group(2)!.trim(),
        'departDate': departDate,
        if (returnDate != null) 'returnDate': returnDate,
      };
    }

    // Pattern D : « City1-City2 date » ou « City1 City2 date » — compact,
    // sans « du »/« le » requis. Ex. « de Paris à Marseille le 15/06/2026 ».
    final compactNumDates = RegExp(
      '(?:de\\s+)?($cityName)\\s+'
      r'(?:à|vers|pour|-)?\s*'
      '($cityName)\\b'
      r'.{0,20}?'
      '(?:d[ue]|le)?\\s*(' + numericDate + r')',
    );
    final matchD = compactNumDates.firstMatch(message);
    if (matchD != null) {
      return {
        'from': matchD.group(1)!.trim(),
        'to': matchD.group(2)!.trim(),
        'departDate': normalizeDate(matchD.group(3)!),
      };
    }

    return null;
  }

  /// Extrait le nom de ville d'un message météo.
  /// Ex. « météo Paris », « temps à Lyon », « weather in London ».
  static String? extractCity(String message) {
    var result = _tryExtractCity(message);
    if (result != null) return result;

    // Repli : capitaliser la première lettre de chaque mot pour les
    // requêtes minuscules (« météo paris » → « Météo Paris »). `_capitalizeWords`
    // préserve les accents internes (voir sa doc) — l'ancien `\b` capitalisait
    // chaque accent (« météo » → « MÉTÉO ») et cassait le match du mot-clé.
    final capitalized = _capitalizeWords(message);
    if (capitalized != message) {
      return _tryExtractCity(capitalized);
    }
    return null;
  }

  static String? _tryExtractCity(String message) {
    // Patterns : « météo Paris », « temps à Lyon », « weather in London »…
    const city = r'([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?)';
    final patterns = [
      // Patterns 1 & 2 : mot-clé météo insensible à la casse (ex. « Météo » issu
      // du repli de capitalisation) + ville toujours capitalisée ([A-ZÀ-Ÿ]).
      // On n'active PAS `caseSensitive: false` sur tout le motif : cela ferait
      // matcher des mots minuscules comme ville (ex. « temps fait » dans
      // « quel temps fait-il à Marseille » → capturerait « Fait »). Fix ADR-029
      // (le repli cassait pour les requêtes minuscules « météo paris » car la
      // capitalisation de « météo » en « Météo » cassait le mot-clé sensible
      // à la casse).
      RegExp(r'(?:[Mm]étéo|[Mm]eteo|[Tt]emps|[Pp]leuvoir|[Tt]empérature|[Tt]emperature|[Ww]eather|[Cc]lima|[Tt]empo|[Ww]etter)\s+(?:à|de|pour|sur|in|en|a|em|bei)\s+' + city),
      RegExp(r'(?:[Mm]étéo|[Mm]eteo|[Tt]emps|[Pp]leuvoir|[Tt]empérature|[Tt]emperature|[Ww]eather|[Cc]lima|[Tt]empo|[Ww]etter)\s+' + city),
      // Pattern 3 & 4 : phrases plus longues (fait-il / va-t-il / how is the
      // weather…). Non couverts par le repli minuscule (la capitalisation de
      // tous les mots casserait la phrase) — limitation documentée.
      RegExp(r'(?:fait-il|fera-t-il|how is the weather|como está el clima|wie ist das wetter)\s+(?:à|de|pour|sur|in|en|a|em|bei)\s+' + city),
      RegExp(r"(?:est-ce qu'il|va-t-il)\s+\w+\s+(?:à|de|pour|sur|in|en|a|em|bei)\s+" + city),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(message);
      if (match != null) return match.group(1)!.trim();
    }
    return null;
  }

  /// Extrait le code postal (5 chiffres) d'un message météo.
  static String? extractZipCode(String message) {
    final match = RegExp(r'\b(\d{5})\b').firstMatch(message);
    if (match != null) return match.group(1);
    return null;
  }

  /// Normalise une date `dd/mm[/yyyy]`, `dd-mm[-yyyy]`, `dd.mm[.yyyy]` vers
  /// `yyyy-mm-dd`. Retourne la chaîne brute si non parsable (implémentation
  /// sûre — `int.parse` + try/catch). Préserve le comportement
  /// `normalizeDate('not-a-date') == 'not-a-date'`.
  static String normalizeDate(String raw) {
    final parts = raw.trim().split(RegExp(r'[/.-]'));
    if (parts.length >= 2) {
      try {
        final d = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        var y = DateTime.now().year;
        if (parts.length >= 3) {
          y = int.parse(parts[2]);
          if (y < 100) y += 2000;
        }
        return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }

  /// Convertit un nom de mois (FR/EN/ES/DE/IT/PT) en entier 1-12. Délègue à
  /// `parseMonth` de `language_service` (source unique déjà partagée par
  /// `ChatNotifier` et `SearchIntentExtractor`). Retourne 1 pour un mois
  /// inconnu.
  static int parseMonth(String name) => lang.parseMonth(name);
}
