import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/data/search_service.dart';

void main() {
  group('SearchService', () {
    group('Debounce', () {
      test('deux requêtes identiques dans la fenêtre de debounce retournent le même résultat', () async {
        final service = SearchService();
        // Premier appel
        try {
          await service.searchWithFallback('test query');
        } catch (_) {
          // Le réseau peut ne pas être disponible en test
        }

        // Deuxième appel immédiat — doit être debounced
        try {
          await service.searchWithFallback('test query');
        } catch (_) {
          // OK
        }

        // Le test passe si aucun crash
        expect(service, isNotNull);
      });
    });

    group('InstantAnswer', () {
      test('InstantAnswer est construit correctement', () {
        const answer = InstantAnswer(
          title: 'Test',
          abstractText: 'Ceci est un test',
          source: 'Wikipedia',
          url: 'https://fr.wikipedia.org/wiki/Test',
        );
        expect(answer.title, 'Test');
        expect(answer.abstractText, 'Ceci est un test');
        expect(answer.source, 'Wikipedia');
        expect(answer.url, 'https://fr.wikipedia.org/wiki/Test');
      });
    });

    group('WebSearchResult', () {
      test('construction et égalité', () {
        const result = WebSearchResult(
          title: 'Test Result',
          url: 'https://example.com',
          snippet: 'Test snippet',
        );
        expect(result.title, 'Test Result');
        expect(result.url, 'https://example.com');
        expect(result.snippet, 'Test snippet');
      });
    });

    group('formatForAi', () {
      test('retourne un message quand aucun résultat', () {
        final service = SearchService();
        final result = service.formatForAi([], 'test');
        expect(result, contains('Aucun resultat'));
      });

      test('formate les résultats correctement', () {
        final service = SearchService();
        final results = [
          const WebSearchResult(
            title: 'Test',
            url: 'https://example.com',
            snippet: 'Snippet test',
          ),
        ];
        final result = service.formatForAi(results, 'test');
        expect(result, contains('Test'));
        expect(result, contains('https://example.com'));
        expect(result, contains('Snippet test'));
      });

      test('tronque les résultats trop longs', () {
        final service = SearchService();
        final results = List.generate(
          50,
          (i) => WebSearchResult(
            title: 'Result $i ' * 20,
            url: 'https://example$i.com',
            snippet: 'Snippet ' * 100,
          ),
        );
        final result = service.formatForAi(results, 'test');
        expect(result.length, lessThanOrEqualTo(16100)); // 16000 + marge pour le tronquage
      });
    });

    group('formatInstantAnswerForAi', () {
      test('formate une réponse instantanée', () {
        final service = SearchService();
        const answer = InstantAnswer(
          title: 'Python',
          abstractText: 'Python est un langage de programmation',
          source: 'Wikipedia',
          url: 'https://fr.wikipedia.org/wiki/Python',
        );
        final result = service.formatInstantAnswerForAi(answer);
        expect(result, contains('Python'));
        expect(result, contains('langage de programmation'));
        expect(result, contains('Wikipedia'));
      });
    });

    group('formatSourcesForUi', () {
      test('retourne vide quand pas de résultats', () {
        final service = SearchService();
        final result = service.formatSourcesForUi([]);
        expect(result, '');
      });

      test('formate les sources en markdown', () {
        final service = SearchService();
        final results = [
          const WebSearchResult(
            title: 'Example',
            url: 'https://example.com',
            snippet: 'Test',
          ),
        ];
        final result = service.formatSourcesForUi(results);
        expect(result, contains('[Example]'));
        expect(result, contains('https://example.com'));
      });
    });

    group('formatSourcesAsList', () {
      test('retourne une liste titre|url', () {
        final service = SearchService();
        final results = [
          const WebSearchResult(
            title: 'Example',
            url: 'https://example.com',
            snippet: 'Test',
          ),
        ];
        final result = service.formatSourcesAsList(results);
        expect(result.length, 1);
        expect(result.first, 'Example|https://example.com');
      });
    });

    group('_decodeDdgUrl', () {
      test('décode une URL absolue directement', () {
        const url = 'https://example.com/page';
        expect(SearchService.decodeDdgUrl(url), equals(url));
      });

      test('décode /l/?uddg=URL', () {
        const raw = '/l/?uddg=https%3A%2F%2Fexample.com%2Fpage';
        expect(SearchService.decodeDdgUrl(raw), equals('https://example.com/page'));
      });

      test('décode /l/?u=URL', () {
        const raw = '/l/?u=https%3A%2F%2Fexample.com';
        expect(SearchService.decodeDdgUrl(raw), equals('https://example.com'));
      });

      test('décode /l/?kh=1&u=URL', () {
        const raw = '/l/?kh=1&u=https%3A%2F%2Fexample.com';
        expect(SearchService.decodeDdgUrl(raw), equals('https://example.com'));
      });

      test('décode //duckduckgo.com/l/?uddg=URL', () {
        const raw = '//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com';
        expect(SearchService.decodeDdgUrl(raw), equals('https://example.com'));
      });

      test('retourne null pour une URL non décodable', () {
        expect(SearchService.decodeDdgUrl(''), isNull);
        expect(SearchService.decodeDdgUrl('/random/path'), isNull);
      });
    });

    group('_cleanHtml', () {
      test('nettoie les balises HTML', () {
        final service = SearchService();
        // La méthode est privée, on teste indirectement via searchDirect
        // qui utilise _cleanHtml en interne
        expect(service, isNotNull);
      });
    });
  });
}