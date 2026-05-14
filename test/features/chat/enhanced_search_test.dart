import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/presentation/chat_notifier.dart';

void main() {
  // ── classifySearchIntent ─────────────────────────────────────────────────

  group('classifySearchIntent', () {
    test('returns weather for pluie/peluvoir messages', () {
      expect(ChatNotifier.classifySearchIntent('va-t-il pleuvoir'),
          equals('weather'));
      expect(ChatNotifier.classifySearchIntent('météo Paris'),
          equals('weather'));
      expect(
          ChatNotifier.classifySearchIntent('quel temps fait-il'),
          equals('weather'));
      expect(ChatNotifier.classifySearchIntent('température Lyon'),
          equals('weather'));
      expect(ChatNotifier.classifySearchIntent('prévisions pour demain'),
          equals('weather'));
    });

    test('returns flights for flight-related messages', () {
      expect(
          ChatNotifier.classifySearchIntent('billet avion Paris Zagreb'),
          equals('flights'));
      expect(ChatNotifier.classifySearchIntent('vol direct Paris Marseille'),
          equals('flights'));
      expect(
          ChatNotifier.classifySearchIntent('vols pas chers pour Barcelone'),
          equals('flights'));
      expect(ChatNotifier.classifySearchIntent('aller-retour Nice Londres'),
          equals('flights'));
    });

    test('returns hotels for accommodation messages', () {
      expect(ChatNotifier.classifySearchIntent('hotel pas cher Paris'),
          equals('hotels'));
      expect(ChatNotifier.classifySearchIntent('airbnb centre ville'),
          equals('hotels'));
      expect(ChatNotifier.classifySearchIntent('logement vacances'),
          equals('hotels'));
      expect(ChatNotifier.classifySearchIntent('booking hotel'),
          equals('hotels'));
      expect(ChatNotifier.classifySearchIntent('séjour à Rome'),
          equals('hotels'));
      expect(ChatNotifier.classifySearchIntent('hébergement pas cher'),
          equals('hotels'));
    });

    test('returns products for shopping messages', () {
      expect(ChatNotifier.classifySearchIntent('trouve le moins cher'),
          equals('products'));
      expect(
          ChatNotifier.classifySearchIntent('meilleur prix pour iPhone'),
          equals('products'));
      expect(ChatNotifier.classifySearchIntent('acheter un vélo'),
          equals('products'));
      expect(
          ChatNotifier.classifySearchIntent('comparer les prix tv 4k'),
          equals('products'));
    });

    test('returns general for non-shopping messages', () {
      expect(ChatNotifier.classifySearchIntent('explique la relativité'),
          equals('general'));
      expect(ChatNotifier.classifySearchIntent('écris un poème'),
          equals('general'));
      expect(ChatNotifier.classifySearchIntent('comment ça va'),
          equals('general'));
    });

    test('weather has priority over flights when mixed', () {
      // "pleuvoir" triggers weather, not general
      expect(
          ChatNotifier.classifySearchIntent(
              'va-t-il pleuvoir pendant mon vol'),
          equals('weather'));
    });
  });

  // ── parseFlightParams ────────────────────────────────────────────────────

  group('parseFlightParams', () {
    test('parses City1-City2 du date1 au date2 format', () {
      final result = ChatNotifier.parseFlightParams(
          'Paris-Zagreb du 29.05.2026 au 02.06.2026');
      expect(result, isNotNull);
      expect(result!['from'], equals('Paris'));
      expect(result['to'], equals('Zagreb'));
      expect(result['departDate'], equals('2026-05-29'));
      expect(result['returnDate'], equals('2026-06-02'));
    });

    test('parses City1 à City2 le date format', () {
      final result = ChatNotifier.parseFlightParams(
          'de Paris à Marseille le 15/06/2026');
      expect(result, isNotNull);
      expect(result!['from'], equals('Paris'));
      expect(result['to'], equals('Marseille'));
      expect(result['departDate'], equals('2026-06-15'));
    });

    test('parses vol direct City1 City2 day month year format', () {
      final result = ChatNotifier.parseFlightParams(
          'vol direct Paris Zagreb 29 mai 2026');
      expect(result, isNotNull);
      expect(result!['from'], equals('Paris'));
      expect(result['to'], equals('Zagreb'));
      expect(result['departDate'], equals('2026-05-29'));
    });

    test('parses billet avion format with month name', () {
      final result = ChatNotifier.parseFlightParams(
          'billet avion de Lyon à Barcelone le 3 juillet 2026');
      expect(result, isNotNull);
      expect(result!['from'], equals('Lyon'));
      expect(result['to'], equals('Barcelone'));
    });

    test('returns null for non-flight messages', () {
      expect(ChatNotifier.parseFlightParams('quelle est la météo'),
          isNull);
      expect(ChatNotifier.parseFlightParams('trouve un hotel pas cher'),
          isNull);
      expect(ChatNotifier.parseFlightParams('bonjour'), isNull);
    });
  });

  // ── extractCity ──────────────────────────────────────────────────────────

  group('extractCity', () {
    test('extracts city after météo', () {
      expect(ChatNotifier.extractCity('météo Paris'), equals('Paris'));
      expect(ChatNotifier.extractCity('meteo Lyon'), equals('Lyon'));
    });

    test('extracts city after temps à', () {
      expect(
          ChatNotifier.extractCity('quel temps fait-il à Marseille'),
          equals('Marseille'));
      expect(
          ChatNotifier.extractCity('temps à Bordeaux'), equals('Bordeaux'));
    });

    test('extracts city after pleuvoir à', () {
      expect(ChatNotifier.extractCity('va-t-il pleuvoir à Lille'),
          equals('Lille'));
    });

    test('extracts city with compound names', () {
      expect(ChatNotifier.extractCity('météo à Saint Étienne'),
          equals('Saint Étienne'));
    });

    test('returns null for non-weather messages', () {
      expect(ChatNotifier.extractCity('bonjour'), isNull);
      expect(ChatNotifier.extractCity('trouve un vol'), isNull);
    });
  });

  // ── extractZipCode ───────────────────────────────────────────────────────

  group('extractZipCode', () {
    test('extracts 5-digit zip code', () {
      expect(ChatNotifier.extractZipCode('météo 75001'), equals('75001'));
      expect(ChatNotifier.extractZipCode('temps pour 69000'), equals('69000'));
    });

    test('returns null when no zip code present', () {
      expect(ChatNotifier.extractZipCode('météo Paris'), isNull);
      expect(ChatNotifier.extractZipCode('bonjour'), isNull);
    });

    test('does not extract 4-digit or 6-digit numbers', () {
      expect(ChatNotifier.extractZipCode('code 1234'), isNull);
      expect(ChatNotifier.extractZipCode('numéro 123456'), isNull);
    });
  });

  // ── normalizeDate ────────────────────────────────────────────────────────

  group('normalizeDate', () {
    test('converts dd/mm/yyyy to yyyy-mm-dd', () {
      expect(ChatNotifier.normalizeDate('29/05/2026'),
          equals('2026-05-29'));
      expect(ChatNotifier.normalizeDate('01/12/2025'),
          equals('2025-12-01'));
    });

    test('converts dd-mm-yyyy', () {
      expect(ChatNotifier.normalizeDate('29-05-2026'),
          equals('2026-05-29'));
    });

    test('converts dd.mm.yyyy', () {
      expect(ChatNotifier.normalizeDate('29.05.2026'),
          equals('2026-05-29'));
    });

    test('handles 2-digit year', () {
      expect(ChatNotifier.normalizeDate('29/05/26'),
          equals('2026-05-29'));
    });

    test('returns raw for unparseable input', () {
      expect(
          ChatNotifier.normalizeDate('not-a-date'), equals('not-a-date'));
    });
  });

  // ── parseMonth ───────────────────────────────────────────────────────────

  group('parseMonth', () {
    test('parses French month names', () {
      expect(ChatNotifier.parseMonth('janvier'), equals(1));
      expect(ChatNotifier.parseMonth('février'), equals(2));
      expect(ChatNotifier.parseMonth('mars'), equals(3));
      expect(ChatNotifier.parseMonth('avril'), equals(4));
      expect(ChatNotifier.parseMonth('mai'), equals(5));
      expect(ChatNotifier.parseMonth('juin'), equals(6));
      expect(ChatNotifier.parseMonth('juillet'), equals(7));
      expect(ChatNotifier.parseMonth('août'), equals(8));
      expect(ChatNotifier.parseMonth('septembre'), equals(9));
      expect(ChatNotifier.parseMonth('octobre'), equals(10));
      expect(ChatNotifier.parseMonth('novembre'), equals(11));
      expect(ChatNotifier.parseMonth('décembre'), equals(12));
    });

    test('parses English month names', () {
      expect(ChatNotifier.parseMonth('january'), equals(1));
      expect(ChatNotifier.parseMonth('december'), equals(12));
      expect(ChatNotifier.parseMonth('august'), equals(8));
    });

    test('is case-insensitive', () {
      expect(ChatNotifier.parseMonth('JANVIER'), equals(1));
      expect(ChatNotifier.parseMonth('Décembre'), equals(12));
    });

    test('returns 1 for unknown month', () {
      expect(ChatNotifier.parseMonth('unknown'), equals(1));
    });
  });
}
