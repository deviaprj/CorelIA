import 'package:corel_ia/features/chat/data/search_service.dart';
import 'package:corel_ia/features/chat/data/web_search_trigger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebSearchTrigger.needsWebSearch', () {
    test('déclenche pour une question factuelle', () {
      expect(WebSearchTrigger.needsWebSearch('quelle est la capitale du Canada ?'), isTrue);
      expect(WebSearchTrigger.needsWebSearch('météo à Lyon demain'), isTrue);
      expect(WebSearchTrigger.needsWebSearch('what is the price of bitcoin'), isTrue);
    });

    test('ne déclenche pas pour une demande créative ou du code', () {
      expect(WebSearchTrigger.needsWebSearch('écris un poème sur la mer'), isFalse);
      expect(WebSearchTrigger.needsWebSearch('code une fonction en Dart'), isFalse);
      expect(WebSearchTrigger.needsWebSearch('donne-moi ton avis'), isFalse);
    });

    test('ne déclenche pas pour une phrase conversationnelle simple', () {
      expect(WebSearchTrigger.needsWebSearch('bonjour'), isFalse);
      expect(WebSearchTrigger.needsWebSearch('merci beaucoup'), isFalse);
    });
  });

  group('WebSearchTrigger.extractSearchQuery', () {
    test('retire les salutations', () {
      expect(
        WebSearchTrigger.extractSearchQuery('bonjour quelle heure est-il'),
        'quelle heure est-il',
      );
      expect(
        WebSearchTrigger.extractSearchQuery('salut, météo à Paris'),
        ', météo à Paris',
      );
    });

    test('tronque les requêtes trop longues', () {
      final long = 'a' * 300;
      final query = WebSearchTrigger.extractSearchQuery(long);
      expect(query.length, lessThanOrEqualTo(203));
      expect(query, endsWith('...'));
    });

    test('conserve une requête normale', () {
      expect(
        WebSearchTrigger.extractSearchQuery('prix du bitcoin'),
        'prix du bitcoin',
      );
    });
  });

  group('WebSearchTrigger.significantTerms', () {
    test('écarte les mots outils et les mots trop courts', () {
      final terms =
          WebSearchTrigger.significantTerms('Quelle est la capitale du Canada');

      expect(terms, containsAll(['capitale', 'canada']));
      expect(terms, isNot(contains('quelle')));
      expect(terms, isNot(contains('est')));
      expect(terms, isNot(contains('la')));
      expect(terms, isNot(contains('du')));
    });

    test('ne retient rien pour une simple salutation', () {
      expect(WebSearchTrigger.significantTerms('Bonjour'), isEmpty);
      expect(WebSearchTrigger.significantTerms('Salut, merci !'), isEmpty);
    });

    test('conserve les accents', () {
      expect(
        WebSearchTrigger.significantTerms('météo à Montréal'),
        containsAll(['météo', 'montréal']),
      );
    });
  });

  group('WebSearchTrigger.relevantResults', () {
    const results = [
      WebSearchResult(
        title: 'Ottawa — Wikipédia',
        url: 'https://fr.wikipedia.org/wiki/Ottawa',
        snippet: 'Ottawa est la capitale du Canada.',
      ),
      WebSearchResult(
        title: 'Crédit renouvelable',
        url: 'https://example.com/credit',
        snippet: 'Carte magasin avec réserve renouvelable.',
      ),
    ];

    test('écarte les résultats hors sujet', () {
      final kept =
          WebSearchTrigger.relevantResults('capitale du Canada', results);

      expect(kept, hasLength(1));
      expect(kept.single.title, contains('Ottawa'));
    });

    test('ne transmet rien pour une salutation', () {
      expect(WebSearchTrigger.relevantResults('Bonjour', results), isEmpty);
    });

    test('ne transmet rien si aucun résultat ne recoupe la question', () {
      expect(
        WebSearchTrigger.relevantResults('recette de crêpes bretonnes', results),
        isEmpty,
      );
    });
  });
}
