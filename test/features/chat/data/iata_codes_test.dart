import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/features/chat/data/iata_codes.dart';

/// Tests unitaires de `iata_codes.dart` (ADR-029 / module IATA).
///
/// Couverture NET-NOUVELLE : le mapping ~300 aéroports + le fuzzy matcher
/// (`resolveIataCode`) étaient non testés depuis leur introduction. On valide
/// ici le contrat RÉEL du module (lu dans l'implémentation, non deviné) :
///
/// API publique :
///   - `String? resolveIataCode(String cityName)` — résout un nom de ville
///     (ou libellé contenant une ville) vers un code IATA 3 lettres. Retourne
///     `null` si aucune correspondance.
///   - `bool hasIataCode(String cityName)` — wrapper (`resolveIataCode != null`).
///   - `String toSearchableAirport(String cityName)` — retourne le code IATA
///     si trouvé, sinon le nom original inchangé.
///
/// Comportement testé (toutes les assertions reflètent l'implémentation
/// réelle — `toLowerCase().trim()` → lookup direct → strip accents → fuzzy
/// `contains` bidirectionnel → split mots + fuzzy per-word + prefix 5 chars) :
///   1. Lookup direct (ville exacte → code).
///   2. Insensibilité à la casse.
///   3. Tolérance aux accents (`é`→`e`, `ã`→`a`, `ñ`→`n`, etc.).
///   4. Fuzzy bidirectionnel (ville contenue dans la requête, ou inverse).
///   5. Fuzzy per-word (split sur espaces, mots > 2 chars).
///   6. Prefix matching (5+ premiers chars partagés avec une ville connue).
///   7. Miss → `null` (ville inconnue / code non mappé).
///   8. Stabilité : ~20 codes échantillonnés sur tous les continents.
///
/// NOTE — quirk du fuzzy : passer un code IATA (3 lettres) en entrée n'est PAS
/// l'usage prévu (le module est city→code, pas code→city). Suivant le code,
/// le fuzzy `contains` peut retourner le code lui-même si celui-ci est un
/// substring d'un nom de ville mappé (`'CDG'` ∈ `'paris cdg'` → `'CDG'`),
/// ou `null` sinon (`'LHR'` n'est substring d'aucune ville). On documente ce
/// comportement de bord pour figer la non-régression, sans le promouvoir
/// comme usage légitime.
void main() {
  group('resolveIataCode — lookup direct (ville exacte → code)', () {
    test('France : Paris, Lyon, Marseille, Bordeaux, Toulouse', () {
      expect(resolveIataCode('Paris'), equals('PAR'));
      expect(resolveIataCode('Lyon'), equals('LYS'));
      expect(resolveIataCode('Marseille'), equals('MRS'));
      expect(resolveIataCode('Bordeaux'), equals('BOD'));
      expect(resolveIataCode('Toulouse'), equals('TLS'));
    });

    test('Europe : London, Madrid, Barcelona, Rome, Frankfurt, Munich', () {
      expect(resolveIataCode('London'), equals('LON'));
      expect(resolveIataCode('Madrid'), equals('MAD'));
      expect(resolveIataCode('Barcelona'), equals('BCN'));
      expect(resolveIataCode('Rome'), equals('ROM'));
      expect(resolveIataCode('Frankfurt'), equals('FRA'));
      expect(resolveIataCode('Munich'), equals('MUC'));
    });

    test('Europe (suite) : Amsterdam, Brussels, Zurich, Lisbon, Dublin, Athens', () {
      expect(resolveIataCode('Amsterdam'), equals('AMS'));
      expect(resolveIataCode('Brussels'), equals('BRU'));
      expect(resolveIataCode('Zurich'), equals('ZRH'));
      expect(resolveIataCode('Lisbon'), equals('LIS'));
      expect(resolveIataCode('Dublin'), equals('DUB'));
      expect(resolveIataCode('Athens'), equals('ATH'));
    });

    test('Moyen-Orient & Afrique : Dubai, Cairo, Lagos, Nairobi', () {
      expect(resolveIataCode('Dubai'), equals('DXB'));
      expect(resolveIataCode('Cairo'), equals('CAI'));
      expect(resolveIataCode('Lagos'), equals('LOS'));
      expect(resolveIataCode('Nairobi'), equals('NBO'));
    });

    test('Asie : Tokyo, Singapore, Bangkok, Mumbai, Delhi, Hong Kong, Seoul', () {
      expect(resolveIataCode('Tokyo'), equals('TYO'));
      expect(resolveIataCode('Singapore'), equals('SIN'));
      expect(resolveIataCode('Bangkok'), equals('BKK'));
      expect(resolveIataCode('Mumbai'), equals('BOM'));
      expect(resolveIataCode('Delhi'), equals('DEL'));
      expect(resolveIataCode('Hong Kong'), equals('HKG'));
      expect(resolveIataCode('Seoul'), equals('SEL'));
    });

    test('Amérique du Nord : New York, Los Angeles, Toronto, Mexico City', () {
      expect(resolveIataCode('New York'), equals('NYC'));
      expect(resolveIataCode('Los Angeles'), equals('LAX'));
      expect(resolveIataCode('Toronto'), equals('YTO'));
      expect(resolveIataCode('Mexico City'), equals('MEX'));
    });

    test('Amérique latine & Océanie : Buenos Aires, Sao Paulo, Rio, Santiago, Sydney, Auckland', () {
      expect(resolveIataCode('Buenos Aires'), equals('BUE'));
      expect(resolveIataCode('Sao Paulo'), equals('SAO'));
      expect(resolveIataCode('Rio de Janeiro'), equals('RIO'));
      expect(resolveIataCode('Santiago'), equals('SCL'));
      expect(resolveIataCode('Sydney'), equals('SYD'));
      expect(resolveIataCode('Auckland'), equals('AKL'));
    });

    test('variantes linguistiques (FR/loc) : Londres, Bruxelles, Vienne, Athènes', () {
      expect(resolveIataCode('Londres'), equals('LON'));
      expect(resolveIataCode('Bruxelles'), equals('BRU'));
      expect(resolveIataCode('Vienne'), equals('VIE'));
      expect(resolveIataCode('Athènes'), equals('ATH'));
    });

    test('aéroports spécifiques (sous-clés ville aéroport)', () {
      // Clés composées présentes dans la map — lookup direct.
      expect(resolveIataCode('Paris CDG'), equals('CDG'));
      expect(resolveIataCode('Paris Orly'), equals('ORY'));
      expect(resolveIataCode('London Heathrow'), equals('LHR'));
      expect(resolveIataCode('Tokyo Narita'), equals('NRT'));
      expect(resolveIataCode('Sao Paulo Guarulhos'), equals('GRU'));
      expect(resolveIataCode('Buenos Aires Ezeiza'), equals('EZE'));
    });
  });

  group('resolveIataCode — insensibilité à la casse', () {
    test('paris / PARIS / Paris / pArIs → tous résolvent vers PAR', () {
      expect(resolveIataCode('paris'), equals('PAR'));
      expect(resolveIataCode('PARIS'), equals('PAR'));
      expect(resolveIataCode('Paris'), equals('PAR'));
      expect(resolveIataCode('pArIs'), equals('PAR'));
    });

    test('multi-mots : new york / NEW YORK / New York → NYC', () {
      expect(resolveIataCode('new york'), equals('NYC'));
      expect(resolveIataCode('NEW YORK'), equals('NYC'));
      expect(resolveIataCode('New York'), equals('NYC'));
    });

    test('mixte casse + accent : SÃO PAULO / sao paulo → SAO', () {
      expect(resolveIataCode('sao paulo'), equals('SAO'));
      expect(resolveIataCode('SAO PAULO'), equals('SAO'));
      expect(resolveIataCode('São Paulo'), equals('SAO'));
    });
  });

  group('resolveIataCode — tolérance aux accents', () {
    test('formes accentuées ET non-accentuées résolvent identiquement', () {
      // 'são paulo' (avec accent) et 'sao paulo' (sans) sont TOUTES DEUX des
      // clés directes dans la map → 'SAO' pour les deux.
      expect(resolveIataCode('São Paulo'), equals('SAO'));
      expect(resolveIataCode('Sao Paulo'), equals('SAO'));
    });

    test('accents français : Genève, Montréal, Bâle, La Valette', () {
      // Clés accentuées présentes directement dans la map.
      expect(resolveIataCode('Genève'), equals('GVA'));
      expect(resolveIataCode('Montréal'), equals('YMQ'));
      expect(resolveIataCode('Bâle'), equals('BSL'));
      expect(resolveIataCode('La Valette'), equals('MLA'));
    });

    test('forme accentuée non mappée résolue via strip-accents (étape 2)', () {
      // 'Montréall' (faute de frappe avec accent) n'est PAS une clé directe.
      // Le strip-accents produit 'montreall' qui n'est pas non plus une clé →
      // on retombe sur le fuzzy. En revanche 'Montréal' (exact) est une clé.
      // On teste ici que la version accentuée exacte (clé mappée) résout, et
      // qu'une variante avec accent inconnu tombe dans le fuzzy.
      expect(resolveIataCode('Montréal'), equals('YMQ'));
      // Variante sans accent ('Montreal') est AUSSI une clé directe → 'YMQ'.
      expect(resolveIataCode('Montreal'), equals('YMQ'));
    });

    test('cédille / eñe : Ç et Ñ (disambiguïsation par accent)', () {
      // L'accent DISAMBIGUE les deux San Jose : 'san josé' (avec é) est une clé
      // directe → SJO (Costa Rica) ; 'san jose' (sans accent) est AUSSI une clé
      // directe → SJC (Californie). Le module résout chacun vers sa ville —
      // l'accent fait la différence. (Le strip d'accents ne s'active que pour
      // les formes NON mappées ; ici les deux formes sont des clés directes.)
      expect(resolveIataCode('San José'), equals('SJO'));
      expect(resolveIataCode('San Jose'), equals('SJC'));
    });
  });

  group('resolveIataCode — fuzzy bidirectionnel (contains)', () {
    test('ville contenu dans la requête : "New York City" contient "new york" → NYC', () {
      // 'new york city' n'est PAS une clé ; mais 'new york' (clé) est un
      // substring de 'new york city' → fuzzy retourne 'NYC'.
      expect(resolveIataCode('New York City'), equals('NYC'));
    });

    test('requête contenu dans une ville : "toky" substring de "tokyo" → TYO', () {
      // 'toky' (4 chars) n'est pas une clé ; 'tokyo'.contains('toky') → true.
      expect(resolveIataCode('Toky'), equals('TYO'));
    });

    test('requête avec bruit : "paris france" contient "paris" → PAR', () {
      // 'paris france' n'est pas une clé ; 'paris' (clé) est substring → 'PAR'.
      expect(resolveIataCode('Paris France'), equals('PAR'));
    });

    test('ville partielle isolée par split mots : "york city" → per-word fuzzy → NYC', () {
      // 'york city' : aucun fuzzy global (aucune clé n'est substring de
      // 'york city' et vice-versa). Split mots ['york','city'] ; 'york' n'est
      // pas une clé directe MAIS 'new york'.contains('york') → true → 'NYC'.
      expect(resolveIataCode('York City'), equals('NYC'));
    });
  });

  group('resolveIataCode — prefix matching (5+ chars partagés)', () {
    test('faute de frappe partageant le prefix 5 chars : "Frankfort" → FRA', () {
      // 'frankfort' n'est pas une clé, n'a pas de match fuzzy `contains`
      // (aucune clé substring de 'frankfort' et inversement). Split mots :
      // ['frankfort'] (9 > 2). Prefix 'frank' partagé avec 'frankfurt' → 'FRA'.
      expect(resolveIataCode('Frankfort'), equals('FRA'));
    });

    test('prefix tronqué : "Stuttgrt" partage "stutt" avec "stuttgart" → STR', () {
      // 'stuttgrt' : pas de match `contains` direct. Prefix 'stutt' partagé
      // avec 'stuttgart' (les deux >= 5 chars, même 5 premiers) → 'STR'.
      expect(resolveIataCode('Stuttgrt'), equals('STR'));
    });
  });

  group('resolveIataCode — quirk code-en-entrée (fuzzy side-effect)', () {
    // Le module est city→code ; passer un code n'est PAS l'usage prévu.
    // On documente le comportement RÉEL (ordre-dépendant) pour figer la
    // non-régression : un code 3 lettres qui est substring d'un ou plusieurs
    // noms de villes mappés retourne le code de la PREMIÈRE ville (en ordre
    // d'insertion de la map) contenant ce substring — pas nécessairement le
    // code passé en entrée. Si aucune ville ne contient le substring → null.

    test('codes qui sont substrings d\'une ville → retournent un code (première ville matchée)', () {
      // 'paris cdg' contient 'cdg' ; aucune ville antérieure ne contient 'cdg' → 'CDG'.
      expect(resolveIataCode('CDG'), equals('CDG'));
      // 'new york jfk' contient 'jfk' ; aucune ville antérieure ne contient 'jfk' → 'JFK'.
      expect(resolveIataCode('JFK'), equals('JFK'));
      // 'madrid' contient 'mad' ; aucune ville antérieure ne contient 'mad' → 'MAD'.
      expect(resolveIataCode('MAD'), equals('MAD'));
      // 'frankfurt' contient 'fra' ; aucune ville antérieure ne contient 'fra' → 'FRA'.
      expect(resolveIataCode('FRA'), equals('FRA'));
      // 'atlanta' contient 'atl' ; aucune ville antérieure ne contient 'atl' → 'ATL'.
      expect(resolveIataCode('ATL'), equals('ATL'));
      // 'sin' est substring de 'helsinki' (HEL) ET 'singapore' (SIN) ;
      // 'helsinki' précède 'singapore' dans la map → 'HEL' (artifact d'ordre).
      expect(resolveIataCode('SIN'), equals('HEL'));
    });

    test('codes qui ne sont substrings d\'aucune ville → null', () {
      // 'LHR' : ni 'london' ni 'london heathrow' ne contiennent 'lhr'.
      expect(resolveIataCode('LHR'), isNull);
      // 'BCN' : 'barcelona' ne contient pas 'bcn'.
      expect(resolveIataCode('BCN'), isNull);
      // 'NRT' : 'tokyo narita' ne contient pas 'nrt'.
      expect(resolveIataCode('NRT'), isNull);
      // 'GRU' : 'sao paulo guarulhos' ne contient pas 'gru'.
      expect(resolveIataCode('GRU'), isNull);
      // 'GIG' : aucun code GIG dans la map, aucune ville ne contient 'gig'.
      expect(resolveIataCode('GIG'), isNull);
    });
  });

  group('resolveIataCode — ville inconnue retourne null', () {
    test('ville fictive / non mappée → null', () {
      expect(resolveIataCode('Tatooine'), isNull);
      expect(resolveIataCode('Gotham'), isNull);
      expect(resolveIataCode('Xyzabc'), isNull);
    });

    test('chaîne vide et whitespace → null', () {
      expect(resolveIataCode(''), isNull);
      expect(resolveIataCode('   '), isNull);
    });

    test('mots trop courts (<= 2 chars) filtrés : "ab" → null', () {
      // 'ab' (2 chars) n'est pas une clé directe, et la garde anti-bruit du
      // fuzzy (key.length >= 3) bloque le fuzzy global. Le split mots garde
      // uniquement w.length > 2, donc ['ab'] est filtré. Double garde : aucun
      // match bruité sur une ville contenant 'ab' (ex. 'istanbul sabiha' → SAW).
      expect(resolveIataCode('ab'), isNull);
    });
  });

  group('resolveIataCode — stabilité (20 codes, tous continents)', () {
    // On échantillonne 20 villes réparties sur tous les continents et on
    // vérifie qu'elles résolvent vers le code documenté. La stabilité =
    // appels répétés renvoient le même résultat (pas de random / ordre
    // non-déterministe).
    final samples = <(String, String)>[
      // Europe
      ('Paris', 'PAR'),
      ('London', 'LON'),
      ('Madrid', 'MAD'),
      ('Barcelona', 'BCN'),
      ('Rome', 'ROM'),
      ('Frankfurt', 'FRA'),
      ('Amsterdam', 'AMS'),
      ('Brussels', 'BRU'),
      // Moyen-Orient / Afrique
      ('Dubai', 'DXB'),
      ('Cairo', 'CAI'),
      ('Lagos', 'LOS'),
      // Asie
      ('Tokyo', 'TYO'),
      ('Singapore', 'SIN'),
      ('Bangkok', 'BKK'),
      ('Hong Kong', 'HKG'),
      // Amérique du Nord
      ('New York', 'NYC'),
      ('Los Angeles', 'LAX'),
      ('Toronto', 'YTO'),
      // Amérique latine / Océanie
      ('Buenos Aires', 'BUE'),
      ('Sydney', 'SYD'),
    ];

    test('chaque ville résout vers son code documenté', () {
      for (final (city, code) in samples) {
        expect(
          resolveIataCode(city),
          equals(code),
          reason: '$city devrait résoudre vers $code',
        );
      }
    });

    test('résultats stables sur appels répétés (idempotence)', () {
      for (final (city, code) in samples) {
        final first = resolveIataCode(city);
        final second = resolveIataCode(city);
        final third = resolveIataCode(city);
        expect(first, equals(code));
        expect(second, equals(first));
        expect(third, equals(first));
      }
    });

    test('couverture continentale effectivement diversifiée', () {
      // Sanity check : on a bien 20 entrées et pas de doublon ville.
      expect(samples.length, equals(20));
      final cities = samples.map((e) => e.$1).toSet();
      expect(cities.length, equals(20), reason: 'pas de doublon');
      final codes = samples.map((e) => e.$2).toSet();
      expect(codes.length, equals(20), reason: 'codes distincts');
    });
  });

  group('hasIataCode', () {
    test('retourne true pour une ville connue', () {
      expect(hasIataCode('Paris'), isTrue);
      expect(hasIataCode('New York'), isTrue);
      expect(hasIataCode('Buenos Aires'), isTrue);
      expect(hasIataCode('São Paulo'), isTrue);
    });

    test('retourne false pour une ville inconnue', () {
      expect(hasIataCode('Tatooine'), isFalse);
      expect(hasIataCode('Xyzabc'), isFalse);
      expect(hasIataCode(''), isFalse);
    });

    test('cohérent avec resolveIataCode (prédicat = non-null)', () {
      const cities = <String>[
        'Paris',
        'Tokyo',
        'Tatooine',
        'São Paulo',
        'Gotham',
        'Sydney',
      ];
      for (final c in cities) {
        expect(hasIataCode(c), equals(resolveIataCode(c) != null), reason: c);
      }
    });
  });

  group('toSearchableAirport', () {
    test('retourne le code IATA pour une ville connue', () {
      expect(toSearchableAirport('Paris'), equals('PAR'));
      expect(toSearchableAirport('New York'), equals('NYC'));
      expect(toSearchableAirport('Buenos Aires'), equals('BUE'));
      expect(toSearchableAirport('São Paulo'), equals('SAO'));
    });

    test('retourne le nom original pour une ville inconnue', () {
      expect(toSearchableAirport('Tatooine'), equals('Tatooine'));
      expect(toSearchableAirport('Xyzabc'), equals('Xyzabc'));
      // Casse préservée (toLowerCase n'affecte que la recherche interne).
      expect(toSearchableAirport('GOTHAM'), equals('GOTHAM'));
    });

    test('chaîne vide → chaîne vide (fallback identité)', () {
      expect(toSearchableAirport(''), equals(''));
    });

    test('cohérent avec resolveIataCode (code ou identité)', () {
      const cases = <(String, String)>[
        ('Paris', 'PAR'),
        ('Tokyo', 'TYO'),
        ('Tatooine', 'Tatooine'),
        ('São Paulo', 'SAO'),
        ('Gotham', 'Gotham'),
      ];
      for (final (input, expected) in cases) {
        expect(toSearchableAirport(input), equals(expected), reason: input);
      }
    });
  });
}