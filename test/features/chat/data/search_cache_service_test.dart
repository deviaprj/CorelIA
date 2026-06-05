import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/features/chat/data/search_cache_service.dart';
import 'package:corel_ia/features/chat/data/search_service.dart';

void main() {
  group('SearchCacheService', () {
    test('cache miss retourne null', () {
      final results = searchCache.get('test query');
      expect(results, isNull);
    });

    test('cache hit après put', () {
      final results = [
        const WebSearchResult(
          title: 'Test Result',
          url: 'https://example.com',
          snippet: 'Test snippet',
        ),
      ];
      searchCache.put('test query', results);
      final cached = searchCache.get('test query');
      expect(cached, isNotNull);
      expect(cached!.length, 1);
      expect(cached.first.title, 'Test Result');
      expect(cached.first.url, 'https://example.com');
    });

    test('cache key est sensible à la langue', () {
      final results = [
        const WebSearchResult(
          title: 'Result FR',
          url: 'https://example.fr',
          snippet: 'Résultat',
        ),
      ];
      searchCache.put('query', results, lang: 'fr');
      searchCache.put('query', results, lang: 'en');

      expect(searchCache.get('query', lang: 'fr'), isNotNull);
      expect(searchCache.get('query', lang: 'en'), isNotNull);
      // La requête sans langue est différente
      expect(searchCache.get('query'), isNull);
    });

    test('cache vide après clear', () {
      searchCache.put('test', [
        const WebSearchResult(title: 'A', url: 'https://a.com', snippet: 'a'),
      ]);
      expect(searchCache.get('test'), isNotNull);
      searchCache.clear();
      expect(searchCache.get('test'), isNull);
    });

    test('cache size après ajouts', () {
      searchCache.clear();
      for (var i = 0; i < 5; i++) {
        searchCache.put('query $i', [
          WebSearchResult(title: 'R$i', url: 'https://r$i.com', snippet: 'r$i'),
        ]);
      }
      expect(searchCache.size, 5);
    });

    test('LRU eviction quand limite atteinte', () {
      searchCache.clear();
      // Ajouter 101 entrées pour dépasser la limite de 100
      for (var i = 0; i < 101; i++) {
        searchCache.put('query $i', [
          WebSearchResult(title: 'R$i', url: 'https://r$i.com', snippet: 'r$i'),
        ]);
      }
      // Le cache doit contenir au maximum 100 entrées
      expect(searchCache.size, lessThanOrEqualTo(100));
    });
  });
}