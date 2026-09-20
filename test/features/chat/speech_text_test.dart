import 'dart:ui';

import 'package:corel_ia/features/chat/data/speech_text.dart';
import 'package:corel_ia/features/chat/data/tts_service.dart';
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

    test('supprime les emojis', () {
      expect(stripMarkdownForSpeech('Bonjour 😀 !'), 'Bonjour !');
      expect(stripMarkdownForSpeech('Bravo 🎉🎊'), 'Bravo');
      expect(stripMarkdownForSpeech('C\'est fait ✅'), 'C\'est fait');
      expect(stripMarkdownForSpeech('Attention ⚠️ au feu'), 'Attention au feu');
    });

    test('supprime les drapeaux et les séquences composées', () {
      expect(stripMarkdownForSpeech('Vive la 🇫🇷 !'), 'Vive la !');
      expect(stripMarkdownForSpeech('Famille 👨‍👩‍👧 ici'), 'Famille ici');
      expect(stripMarkdownForSpeech('touche 1️⃣ active'), 'touche 1 active');
    });

    test('supprime les flèches et puces symboliques', () {
      expect(stripMarkdownForSpeech('→ première étape'), 'première étape');
      expect(stripMarkdownForSpeech('résultat ➜ gagné'), 'résultat gagné');
    });

    test('conserve les accents, la ponctuation et les chiffres', () {
      expect(
        stripMarkdownForSpeech('Où ça ? 12,50 € — bien sûr !'),
        'Où ça ? 12,50 € — bien sûr !',
      );
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

  group('réglages de lecture', () {
    test('le débit est très légèrement au-dessus du débit normal', () {
      // flutter_tts transmet `rate × 2` à Android : 0.5 = débit normal.
      // Un débit franchement supérieur rendrait la lecture désagréable.
      expect(TtsService.speechRate, greaterThan(0.5));
      expect(TtsService.speechRate, lessThan(0.7));
    });
  });
}
