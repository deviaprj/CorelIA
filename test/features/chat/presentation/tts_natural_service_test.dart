import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/presentation/tts_natural_service.dart';

void main() {
  group('TtsNaturalService', () {
    group('cleanMarkdown', () {
      test('supprime les URLs en gardant le domaine', () {
        final result = TtsNaturalService.cleanMarkdown(
          'Visitez https://www.example.com/page pour plus d\'infos.',
        );
        expect(result, contains('example.com'));
        expect(result, isNot(contains('https://')));
      });

      test('supprime les citations entre crochets', () {
        final result = TtsNaturalService.cleanMarkdown(
          'Voir la documentation [1] pour plus de détails [2].',
        );
        expect(result, isNot(contains('[1]')));
        expect(result, isNot(contains('[2]')));
        expect(result, contains('documentation'));
        expect(result, contains('détails'));
      });

      test('supprime les emojis', () {
        final result = TtsNaturalService.stripEmojis('Hello 🌍 world 🎉');
        // Les emojis sont remplacés par du vide, laissant potentiellement des espaces multiples
        expect(result.contains('🌍'), false);
        expect(result.contains('🎉'), false);
        expect(result.contains('Hello'), true);
        expect(result.contains('world'), true);
      });

      test('supprime le gras et l\'italique', () {
        final result = TtsNaturalService.cleanMarkdown('Ceci est **important** et *italique*.');
        expect(result, 'Ceci est important et italique.');
      });

      test('supprime les titres markdown', () {
        final result = TtsNaturalService.cleanMarkdown('# Titre principal\n## Sous-titre');
        expect(result, contains('Titre principal'));
        expect(result, isNot(contains('#')));
      });

      test('supprime les blocs de code', () {
        final result = TtsNaturalService.cleanMarkdown('Du texte\n```\ncode ici\n```\nSuite');
        expect(result, contains('[bloc de code]'));
        expect(result, isNot(contains('```')));
      });

      test('supprime le code inline', () {
        final result = TtsNaturalService.cleanMarkdown('Utilisez `flutter test` pour tester.');
        expect(result, 'Utilisez flutter test pour tester.');
      });

      test('supprime les liens markdown en gardant le texte', () {
        final result = TtsNaturalService.cleanMarkdown('[Cliquer ici](https://example.com)');
        expect(result, 'Cliquer ici');
        expect(result, isNot(contains('https://')));
      });

      test('supprime les images avec texte alternatif', () {
        final result = TtsNaturalService.cleanMarkdown('![Photo du chat](cat.jpg)');
        expect(result, contains('Photo du chat'));
        expect(result, isNot(contains('cat.jpg')));
      });

      test('nettoie les listes à puces', () {
        final result = TtsNaturalService.cleanMarkdown('- Premier\n- Deuxième\n- Troisième');
        expect(result, isNot(contains('- ')));
        expect(result, contains('Premier'));
      });

      test('supprime la section Sources', () {
        final result = TtsNaturalService.cleanMarkdown(
          'Réponse ici.\n\n---\n**Sources :**\n1. example.com\n2. test.com',
        );
        expect(result, contains('Réponse ici.'));
        expect(result, isNot(contains('Sources')));
        expect(result, isNot(contains('example.com')));
      });

      test('nettoie le HTML basique', () {
        final result = TtsNaturalService.cleanMarkdown('<b>Gras</b> et <i>italique</i>');
        expect(result, isNot(contains('<b>')));
        expect(result, isNot(contains('<i>')));
      });
    });

    group('stripEmojis', () {
      test('supprime les emojis', () {
        expect(TtsNaturalService.stripEmojis('Hello 🌍!'), 'Hello !');
        expect(TtsNaturalService.stripEmojis('🎉🎊Party'), 'Party');
      });

      test('préserve le texte sans emojis', () {
        expect(TtsNaturalService.stripEmojis('Pas d\'emoji ici'), 'Pas d\'emoji ici');
      });
    });

    group('stripUrls', () {
      test('extrait le domaine d\'une URL', () {
        expect(TtsNaturalService.stripUrls('Visit https://www.google.com/search'),
            contains('google.com'));
      });

      test('gère les URLs sans www', () {
        expect(TtsNaturalService.stripUrls('See https://example.com/page'), contains('example.com'));
      });
    });

    group('stripCitations', () {
      test('supprime les citations numériques', () {
        expect(TtsNaturalService.stripCitations('Voir [1] et [25]'), 'Voir  et ');
      });

      test('préserve le texte entre crochets non numérique', () {
        expect(TtsNaturalService.stripCitations('[joyeux] texte'), '[joyeux] texte');
      });
    });
  });
}