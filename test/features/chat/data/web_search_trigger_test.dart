import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/features/chat/data/web_search_trigger.dart';

/// Tests unitaires de `WebSearchTrigger` (ADR-030, Bloc 3 cluster 2).
///
/// Couverture NET-NOUVELLE : `needsWebSearch` et `extractSearchQuery` vivaient
/// en méthodes privées statiques dans le god object `ChatNotifier` — jamais
/// testées (inaccessibles hors de la bibliothèque). L'extraction vers une
/// classe utilitaire publique les rend enfin testables isolément.
///
/// Heuristique testée (multilingue FR/EN/ES/DE/IT/PT) :
/// 1. mot-clé exclusif → `false` (créativité/code/opinion, vérifié AVANT les
///    déclencheurs — un message contenant les deux ne déclenche pas).
/// 2. mot-clé déclencheur → `true` (info factuelle/temporelle).
/// 3. `?` explicite + question courte (≤ 100 chars) → `true`.
/// 4. défaut → `false` (conversation normale).
void main() {
  group('WebSearchTrigger.needsWebSearch', () {
    group('mots-clés déclencheurs → true', () {
      test('FR : météo / quelle est la / combien coûte / billet d\'avion', () {
        expect(WebSearchTrigger.needsWebSearch('quelle est la météo'), isTrue);
        expect(
          WebSearchTrigger.needsWebSearch('combien coûte un billet d\'avion'),
          isTrue,
        );
        expect(WebSearchTrigger.needsWebSearch('prix de l\'iphone 15'), isTrue);
        expect(
          WebSearchTrigger.needsWebSearch('quel temps fait-il à Paris'),
          isTrue,
        );
      });

      test('EN : what is / weather / forecast / price of', () {
        expect(
          WebSearchTrigger.needsWebSearch('what is the capital of France'),
          isTrue,
        );
        expect(
          WebSearchTrigger.needsWebSearch('what is the weather forecast'),
          isTrue,
        );
        expect(WebSearchTrigger.needsWebSearch('price of the iphone'), isTrue);
      });

      test('ES : vuelo / qué es / clima / precio de', () {
        expect(WebSearchTrigger.needsWebSearch('vuelo paris londres'), isTrue);
        expect(WebSearchTrigger.needsWebSearch('qué es la photosynthèse'), isTrue);
      });

      test('DE : wie viel / flug / wetter / preis von', () {
        expect(
          WebSearchTrigger.needsWebSearch('wie viel kostet ein flug'),
          isTrue,
        );
      });

      test('IT : prezzo di / volo / meteo', () {
        expect(
          WebSearchTrigger.needsWebSearch('qual è il prezzo di un volo'),
          isTrue,
        );
      });

      test('PT : preço de / voo / clima', () {
        expect(
          WebSearchTrigger.needsWebSearch('qual o preço de um voo'),
          isTrue,
        );
      });
    });

    group('mots-clés exclusifs → false (vérifiés AVANT les déclencheurs)', () {
      test('FR : écris / poème / imagine', () {
        expect(
          WebSearchTrigger.needsWebSearch('écris un poème sur la lune'),
          isFalse,
        );
        expect(
          WebSearchTrigger.needsWebSearch('imagine un monde sans guerre'),
          isFalse,
        );
        expect(
          WebSearchTrigger.needsWebSearch('qu\'en penses-tu de cette idée'),
          isFalse,
        );
      });

      test('EN : write a / story / code a / function', () {
        expect(
          WebSearchTrigger.needsWebSearch('write a story about a dragon'),
          isFalse,
        );
        expect(
          WebSearchTrigger.needsWebSearch('code a function to sort a list'),
          isFalse,
        );
      });

      test('ES : escribe / poema', () {
        expect(
          WebSearchTrigger.needsWebSearch('escribe un poema sobre el mar'),
          isFalse,
        );
      });

      test('DE : schreibe / gedicht', () {
        expect(
          WebSearchTrigger.needsWebSearch('schreibe ein gedicht'),
          isFalse,
        );
      });

      test('exclusion prioritaire sur déclencheur', () {
        // « écris un poème sur la météo » contient à la fois un déclencheur
        // (météo) et un exclusif (écris/poème) → l'exclusif gagne → false.
        expect(
          WebSearchTrigger.needsWebSearch('écris un poème sur la météo'),
          isFalse,
        );
      });
    });

    group('heuristique « ? »', () {
      test('question courte sans mot-clé → true', () {
        expect(WebSearchTrigger.needsWebSearch('tu viens ce soir ?'), isTrue);
      });

      test('question longue (> 100 chars) sans mot-clé → false', () {
        // 129 chars, aucun déclencheur ni exclusif, terminé par « ? ».
        const long = 'as tu bien dormi cette nuit et te sens tu vraiment prêt '
            'et reposé pour la très longue journée de travail qui t attende '
            'au bureau ?';
        expect(long.length, greaterThan(100));
        expect(WebSearchTrigger.needsWebSearch(long), isFalse);
      });
    });

    group('défaut → false (conversation normale)', () {
      test('affirmation simple', () {
        expect(WebSearchTrigger.needsWebSearch('je vais bien merci'), isFalse);
      });

      test('salutation sans question', () {
        expect(
          WebSearchTrigger.needsWebSearch('bonjour comment ça va'),
          isFalse,
        );
      });

      test('chaîne vide', () {
        expect(WebSearchTrigger.needsWebSearch(''), isFalse);
      });
    });
  });

  group('WebSearchTrigger.extractSearchQuery', () {
    test('supprime les salutations courantes (FR)', () {
      expect(
        WebSearchTrigger.extractSearchQuery('bonjour quelle est la météo'),
        equals('quelle est la météo'),
      );
      expect(
        WebSearchTrigger.extractSearchQuery('salut ça va aujourd\'hui'),
        equals('ça va aujourd\'hui'),
      );
      expect(
        WebSearchTrigger.extractSearchQuery('coucou dis moi une blague'),
        equals('dis moi une blague'),
      );
    });

    test('supprime les salutations courantes (EN)', () {
      expect(
        WebSearchTrigger.extractSearchQuery('hello what is the weather'),
        equals('what is the weather'),
      );
      expect(
        WebSearchTrigger.extractSearchQuery('hi there how are you'),
        equals('there how are you'),
      );
    });

    test('sans salutation → requête inchangée', () {
      expect(
        WebSearchTrigger.extractSearchQuery('quelle est la météo'),
        equals('quelle est la météo'),
      );
    });

    test('salutation suivie d\'une virgule (la virgule est conservée)', () {
      // La salutation seule est retirée ; la ponctuation qui suit n'est pas
      // nettoyée (comportement documenté — un futur nettoyage de ponctuation
      // devra mettre à jour ce test).
      expect(
        WebSearchTrigger.extractSearchQuery('bonjour, quelle est la météo'),
        equals(', quelle est la météo'),
      );
    });

    test('tronque à 200 caractères + « ... »', () {
      final long = 'a' * 220;
      final result = WebSearchTrigger.extractSearchQuery(long);
      expect(result.length, equals(203));
      expect(result, equals('a' * 200 + '...'));
    });

    test('préserve les messages ≤ 200 caractères', () {
      const msg = 'quelle est la météo à Paris aujourd\'hui';
      expect(WebSearchTrigger.extractSearchQuery(msg), equals(msg));
    });
  });
}