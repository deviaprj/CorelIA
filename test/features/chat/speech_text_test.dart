import 'dart:ui';

import 'package:corel_ia/features/chat/data/speech_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stripMarkdownForSpeech', () {
    test('retire gras, italique et titres', () {
      expect(stripMarkdownForSpeech('# Titre\n**gras** et *italique*'),
          'Titre\ngras et italique');
    });

    test('retire le code mais garde le texte des liens', () {
      const markdown = 'Voir [la doc](https://example.com) et `le code`.';
      expect(stripMarkdownForSpeech(markdown), 'Voir la doc et le code.');
    });

    test('supprime les blocs de code', () {
      const markdown = 'Avant\n```dart\nvoid main() {}\n```\nAprès';
      final spoken = stripMarkdownForSpeech(markdown);
      expect(spoken, contains('Avant'));
      expect(spoken, contains('Après'));
      expect(spoken, isNot(contains('void main')));
    });

    test('retire les puces et les citations', () {
      const markdown = '- premier\n- deuxième\n> citation';
      expect(stripMarkdownForSpeech(markdown), 'premier\ndeuxième\ncitation');
    });

    test('compacte les espaces superflus', () {
      expect(stripMarkdownForSpeech('Bonjour    le\n\n\nmonde'),
          'Bonjour le\nmonde');
    });

    test('ne renvoie rien pour un contenu vide ou du code seul', () {
      expect(stripMarkdownForSpeech('```\ncode\n```').trim(), isEmpty);
    });
  });

  group('resolveSpeechLanguage', () {
    test('détecte le français', () {
      expect(
        resolveSpeechLanguage('La capitale du Canada est Ottawa.',
            deviceLocale: const Locale('en', 'US')),
        'fr-FR',
      );
      expect(
        resolveSpeechLanguage('Voici la réponse à votre question.',
            deviceLocale: const Locale('en', 'US')),
        'fr-FR',
      );
    });

    test('détecte l\'anglais', () {
      expect(
        resolveSpeechLanguage('The capital of Canada is Ottawa, and you can visit it.',
            deviceLocale: const Locale('fr', 'FR')),
        'en-US',
      );
    });

    test('retombe sur la langue de l\'appareil si indéterminé', () {
      expect(
        resolveSpeechLanguage('42', deviceLocale: const Locale('fr', 'FR')),
        'fr-FR',
      );
      expect(
        resolveSpeechLanguage('42', deviceLocale: const Locale('es', 'ES')),
        'es-ES',
      );
    });

    test('languageTag construit une balise BCP-47', () {
      expect(languageTag(const Locale('fr', 'FR')), 'fr-FR');
      expect(languageTag(const Locale('en')), 'en');
    });
  });
}
