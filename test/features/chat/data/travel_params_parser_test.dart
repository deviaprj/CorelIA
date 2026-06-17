import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/features/chat/data/travel_params_parser.dart';

/// Tests unitaires de `TravelParamsParser` (ADR-029, Bloc 3 cluster 1).
///
/// Couvre l'API directe de la source unique pour l'analyse des requêtes de
/// vol (villes + dates) et météo (ville + code postal). Complète
/// `enhanced_search_test.dart` qui valide les shims `ChatNotifier.*` (qui
/// délèguent vers cette même classe) — ici on teste la source directement.
///
/// Les dates textuelles sans année explicite utilisent `DateTime.now().year`
/// (comportement de production) → les assertions interpolent `y` pour ne pas
/// pourrir au changement d'année (contrairement aux assertions codées en dur
/// `2026-...` de `enhanced_search_test.dart`).
void main() {
  final y = DateTime.now().year;

  group('TravelParamsParser.parseFlightParams', () {
    group('FR/EN — tirets, espaces, dates textuelles et numériques', () {
      test('City1-City2 du date1 au date2 (tiret + dates numériques)', () {
        final r = TravelParamsParser.parseFlightParams(
          'Paris-Zagreb du 29.05.2026 au 02.06.2026',
        );
        expect(r, isNotNull);
        expect(r!['from'], equals('Paris'));
        expect(r['to'], equals('Zagreb'));
        expect(r['departDate'], equals('2026-05-29'));
        expect(r['returnDate'], equals('2026-06-02'));
      });

      test('de City1 à City2 le date (espace + date numérique compacte)', () {
        final r = TravelParamsParser.parseFlightParams(
          'de Paris à Marseille le 15/06/2026',
        );
        expect(r, isNotNull);
        expect(r!['from'], equals('Paris'));
        expect(r['to'], equals('Marseille'));
        expect(r['departDate'], equals('2026-06-15'));
        expect(r.containsKey('returnDate'), isFalse);
      });

      test('vol direct City1 City2 DD mois YYYY (espace + date textuelle)', () {
        final r = TravelParamsParser.parseFlightParams(
          'vol direct Paris Zagreb 29 mai 2026',
        );
        expect(r, isNotNull);
        expect(r!['from'], equals('Paris'));
        expect(r['to'], equals('Zagreb'));
        expect(r['departDate'], equals('$y-05-29'));
      });

      test('billet avion de City1 à City2 le D mois YYYY', () {
        final r = TravelParamsParser.parseFlightParams(
          'billet avion de Lyon à Barcelone le 3 juillet 2026',
        );
        expect(r, isNotNull);
        expect(r!['from'], equals('Lyon'));
        expect(r['to'], equals('Barcelone'));
        expect(r['departDate'], equals('$y-07-03'));
      });

      test('City1-City2 du D mois au D mois (tiret + dates textuelles FR)', () {
        final r = TravelParamsParser.parseFlightParams(
          'Paris-Zagreb du 29 mai au 2 juin',
        );
        expect(r, isNotNull);
        expect(r!['from'], equals('Paris'));
        expect(r['to'], equals('Zagreb'));
        expect(r['departDate'], equals('$y-05-29'));
        expect(r['returnDate'], equals('$y-06-02'));
      });

      test('minuscules + mots parasites : « trouve un billet paris-londre direct du 29/05 »', () {
        // Reproduction ADR-029 : requête minuscule → repli _sanitizeFlightQuery
        // (retire les stop-words, dont « du ») + _capitalizeWords → « Paris-Londre 29/05 ».
        // Aucun pattern ne gérait « tiret + date numérique SANS « du »/« le » » (pattern B
        // exigeait « du »). Pattern B relaxé → « du »/« le » optionnel → ce cas passe.
        final r = TravelParamsParser.parseFlightParams(
          'trouve un billet paris-londre direct du 29/05',
        );
        expect(r, isNotNull);
        expect(r!['from'], equals('Paris'));
        expect(r['to'], equals('Londre'));
        expect(r['departDate'], equals('$y-05-29'));
        expect(r.containsKey('returnDate'), isFalse);
      });
    });

    group('6 langues — reconnaissance des mois ES/DE/IT/PT (ADR-029 fix)', () {
      // Ces cas validaient `null` avant la correction du regex `_months`
      // (tronqué à FR/EN + quelques ES/IT/PT, sans août/avril/março/etc.).
      test('ES : vuelo Madrid Barcelona 15 enero', () {
        final r = TravelParamsParser.parseFlightParams(
          'vuelo Madrid Barcelona 15 enero',
        );
        expect(r, isNotNull);
        expect(r!['from'], equals('Madrid'));
        expect(r['to'], equals('Barcelona'));
        expect(r['departDate'], equals('$y-01-15'));
      });

      test('ES : vuelo Madrid Barcelona 15 agosto (août était absent)', () {
        final r = TravelParamsParser.parseFlightParams(
          'vuelo Madrid Barcelona 15 agosto',
        );
        expect(r, isNotNull);
        expect(r!['departDate'], equals('$y-08-15'));
      });

      test('DE : Flug Berlin Hamburg 15 Januar', () {
        final r = TravelParamsParser.parseFlightParams(
          'Flug Berlin Hamburg 15 Januar',
        );
        expect(r, isNotNull);
        expect(r!['from'], equals('Berlin'));
        expect(r['to'], equals('Hamburg'));
        expect(r['departDate'], equals('$y-01-15'));
      });

      test('DE : Flug Berlin Hamburg 15 August (août était absent)', () {
        final r = TravelParamsParser.parseFlightParams(
          'Flug Berlin Hamburg 15 August',
        );
        expect(r, isNotNull);
        expect(r!['departDate'], equals('$y-08-15'));
      });

      test('IT : volo Roma Milano 15 marzo (marzo IT était absent)', () {
        final r = TravelParamsParser.parseFlightParams(
          'volo Roma Milano 15 marzo',
        );
        expect(r, isNotNull);
        expect(r!['from'], equals('Roma'));
        expect(r['to'], equals('Milano'));
        expect(r['departDate'], equals('$y-03-15'));
      });

      test('PT : voo Lisboa Porto 15 março (março PT était absent)', () {
        final r = TravelParamsParser.parseFlightParams(
          'voo Lisboa Porto 15 março',
        );
        expect(r, isNotNull);
        expect(r!['from'], equals('Lisboa'));
        expect(r['to'], equals('Porto'));
        expect(r['departDate'], equals('$y-03-15'));
      });

      test('PT : voo Lisboa Porto 15 setembro (setembro était absent)', () {
        final r = TravelParamsParser.parseFlightParams(
          'voo Lisboa Porto 15 setembro',
        );
        expect(r, isNotNull);
        expect(r!['departDate'], equals('$y-09-15'));
      });
    });

    group('cas négatifs — retourne null', () {
      test('question météo sans structure vol', () {
        expect(
          TravelParamsParser.parseFlightParams('quelle est la météo'),
          isNull,
        );
      });

      test('recherche hôtel sans structure vol', () {
        expect(
          TravelParamsParser.parseFlightParams('trouve un hotel pas cher'),
          isNull,
        );
      });

      test('salutation seule', () {
        expect(TravelParamsParser.parseFlightParams('bonjour'), isNull);
      });

      test('chaîne vide', () {
        expect(TravelParamsParser.parseFlightParams(''), isNull);
      });
    });
  });

  group('TravelParamsParser.extractCity', () {
    test('météo + ville (FR, pattern 2)', () {
      expect(TravelParamsParser.extractCity('météo Paris'), equals('Paris'));
    });

    test('meteo + ville (FR sans accent)', () {
      expect(TravelParamsParser.extractCity('meteo Lyon'), equals('Lyon'));
    });

    test('temps à + ville (FR, pattern 1)', () {
      expect(
        TravelParamsParser.extractCity('temps à Bordeaux'),
        equals('Bordeaux'),
      );
    });

    test('quel temps fait-il à + ville (FR, pattern 3)', () {
      expect(
        TravelParamsParser.extractCity('quel temps fait-il à Marseille'),
        equals('Marseille'),
      );
    });

    test('va-t-il pleuvoir à + ville (FR, pattern 4)', () {
      expect(
        TravelParamsParser.extractCity('va-t-il pleuvoir à Lille'),
        equals('Lille'),
      );
    });

    test('ville composée « Saint Étienne »', () {
      expect(
        TravelParamsParser.extractCity('météo à Saint Étienne'),
        equals('Saint Étienne'),
      );
    });

    test('weather in + city (EN)', () {
      expect(
        TravelParamsParser.extractCity('weather in London'),
        equals('London'),
      );
    });

    test('clima en + ciudad (ES)', () {
      expect(
        TravelParamsParser.extractCity('clima en Madrid'),
        equals('Madrid'),
      );
    });

    test('wetter in + stadt (DE)', () {
      expect(
        TravelParamsParser.extractCity('wetter in Berlin'),
        equals('Berlin'),
      );
    });

    test('repli minuscules : « météo paris » → Paris', () {
      expect(TravelParamsParser.extractCity('météo paris'), equals('Paris'));
    });

    test('sans mot-clé météo → null', () {
      expect(TravelParamsParser.extractCity('bonjour'), isNull);
      expect(TravelParamsParser.extractCity('trouve un vol'), isNull);
    });
  });

  group('TravelParamsParser.extractZipCode', () {
    test('code postal 5 chiffres isolé', () {
      expect(TravelParamsParser.extractZipCode('météo 75001'), equals('75001'));
      expect(
        TravelParamsParser.extractZipCode('temps pour 69000'),
        equals('69000'),
      );
    });

    test('pas de code postal → null', () {
      expect(TravelParamsParser.extractZipCode('météo Paris'), isNull);
      expect(TravelParamsParser.extractZipCode('bonjour'), isNull);
    });

    test('4 chiffres → null (\\b\\d{5}\\b requiert exactement 5)', () {
      expect(TravelParamsParser.extractZipCode('code 1234'), isNull);
    });

    test('6 chiffres → null (pas de frontière interne)', () {
      expect(TravelParamsParser.extractZipCode('numéro 123456'), isNull);
    });
  });

  group('TravelParamsParser.normalizeDate', () {
    test('format dd/mm/yyyy', () {
      expect(TravelParamsParser.normalizeDate('29/05/2026'), equals('2026-05-29'));
      expect(TravelParamsParser.normalizeDate('01/12/2025'), equals('2025-12-01'));
    });

    test('format dd-mm-yyyy', () {
      expect(TravelParamsParser.normalizeDate('29-05-2026'), equals('2026-05-29'));
    });

    test('format dd.mm.yyyy', () {
      expect(TravelParamsParser.normalizeDate('29.05.2026'), equals('2026-05-29'));
    });

    test('année 2 chiffres → +2000', () {
      expect(TravelParamsParser.normalizeDate('29/05/26'), equals('2026-05-29'));
    });

    test('date à 2 composants → année courante', () {
      final y = DateTime.now().year;
      expect(TravelParamsParser.normalizeDate('15/06'), equals('$y-06-15'));
    });

    test('entrée non parsable → retourne la chaîne brute (impl. sûre)', () {
      // ADR-029 : l'ancien _normalizeDate de SearchIntentExtractor produisait
      // 'date-0a-not' pour 'not-a-date' (padLeft non sûr). L'impl unifiée
      // retourne la chaîne brute via int.parse + try/catch.
      expect(TravelParamsParser.normalizeDate('not-a-date'), equals('not-a-date'));
      expect(TravelParamsParser.normalizeDate('garbage'), equals('garbage'));
    });
  });

  group('TravelParamsParser.parseMonth', () {
    test('mois FR 1-12', () {
      expect(TravelParamsParser.parseMonth('janvier'), equals(1));
      expect(TravelParamsParser.parseMonth('février'), equals(2));
      expect(TravelParamsParser.parseMonth('mars'), equals(3));
      expect(TravelParamsParser.parseMonth('avril'), equals(4));
      expect(TravelParamsParser.parseMonth('mai'), equals(5));
      expect(TravelParamsParser.parseMonth('juin'), equals(6));
      expect(TravelParamsParser.parseMonth('juillet'), equals(7));
      expect(TravelParamsParser.parseMonth('août'), equals(8));
      expect(TravelParamsParser.parseMonth('septembre'), equals(9));
      expect(TravelParamsParser.parseMonth('octobre'), equals(10));
      expect(TravelParamsParser.parseMonth('novembre'), equals(11));
      expect(TravelParamsParser.parseMonth('décembre'), equals(12));
    });

    test('mois EN 1-12', () {
      expect(TravelParamsParser.parseMonth('january'), equals(1));
      expect(TravelParamsParser.parseMonth('february'), equals(2));
      expect(TravelParamsParser.parseMonth('march'), equals(3));
      expect(TravelParamsParser.parseMonth('april'), equals(4));
      expect(TravelParamsParser.parseMonth('may'), equals(5));
      expect(TravelParamsParser.parseMonth('june'), equals(6));
      expect(TravelParamsParser.parseMonth('july'), equals(7));
      expect(TravelParamsParser.parseMonth('august'), equals(8));
      expect(TravelParamsParser.parseMonth('september'), equals(9));
      expect(TravelParamsParser.parseMonth('october'), equals(10));
      expect(TravelParamsParser.parseMonth('november'), equals(11));
      expect(TravelParamsParser.parseMonth('december'), equals(12));
    });

    test('mois ES / DE / IT / PT', () {
      expect(TravelParamsParser.parseMonth('enero'), equals(1));
      expect(TravelParamsParser.parseMonth('febrero'), equals(2));
      expect(TravelParamsParser.parseMonth('marzo'), equals(3));
      expect(TravelParamsParser.parseMonth('agosto'), equals(8));
      expect(TravelParamsParser.parseMonth('januar'), equals(1));
      expect(TravelParamsParser.parseMonth('marz'), equals(3));
      expect(TravelParamsParser.parseMonth('dezember'), equals(12));
      expect(TravelParamsParser.parseMonth('gennaio'), equals(1));
      expect(TravelParamsParser.parseMonth('febbraio'), equals(2));
      expect(TravelParamsParser.parseMonth('luglio'), equals(7));
      expect(TravelParamsParser.parseMonth('janeiro'), equals(1));
      expect(TravelParamsParser.parseMonth('fevereiro'), equals(2));
      expect(TravelParamsParser.parseMonth('março'), equals(3));
      expect(TravelParamsParser.parseMonth('maio'), equals(5));
      expect(TravelParamsParser.parseMonth('dezembro'), equals(12));
    });

    test('insensible à la casse', () {
      expect(TravelParamsParser.parseMonth('JANVIER'), equals(1));
      expect(TravelParamsParser.parseMonth('Décembre'), equals(12));
      expect(TravelParamsParser.parseMonth('JANUARY'), equals(1));
      expect(TravelParamsParser.parseMonth('AGOSTO'), equals(8));
    });

    test('mois inconnu → 1 (défaut)', () {
      expect(TravelParamsParser.parseMonth('unknown'), equals(1));
      expect(TravelParamsParser.parseMonth(''), equals(1));
    });
  });

  group('TravelParamsParser.isValidCityPair', () {
    test('villes valides 1 mot', () {
      expect(TravelParamsParser.isValidCityPair('Paris', 'Zagreb'), isTrue);
      expect(TravelParamsParser.isValidCityPair('Lyon', 'Barcelone'), isTrue);
    });

    test('villes valides 2-3 mots', () {
      expect(
        TravelParamsParser.isValidCityPair('New York', 'Los Angeles'),
        isTrue,
      );
      expect(
        TravelParamsParser.isValidCityPair('Sao Paulo', 'Rio De Janeiro'),
        isTrue,
      );
    });

    test('mot parasite comme ville → false', () {
      expect(TravelParamsParser.isValidCityPair('vol', 'Paris'), isFalse);
      expect(TravelParamsParser.isValidCityPair('trouve', 'Paris'), isFalse);
      expect(TravelParamsParser.isValidCityPair('billet', 'avion'), isFalse);
      expect(TravelParamsParser.isValidCityPair('Paris', 'flight'), isFalse);
    });

    test('plus de 3 mots → false', () {
      expect(
        TravelParamsParser.isValidCityPair('very long city name here', 'X'),
        isFalse,
      );
    });
  });
}