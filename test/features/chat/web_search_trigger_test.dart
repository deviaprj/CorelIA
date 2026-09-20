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
}
