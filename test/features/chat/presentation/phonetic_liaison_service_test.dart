import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/features/chat/presentation/phonetic_liaison_service.dart';

void main() {
  group('PhoneticLiaisonService', () {
    group('French — no standalone liaison letters', () {
      test('les + vowel → z becomes onset of next word', () {
        final result = PhoneticLiaisonService.apply(
          'les étoiles brillent',
          'fr-FR',
        );
        expect(result, contains('les zétoiles'));
        expect(result, isNot(contains('les-z-')));
        expect(result, isNot(contains('les z-')));
      });

      test('un + vowel → n becomes onset of next word', () {
        final result = PhoneticLiaisonService.apply(
          'un ami vient',
          'fr-FR',
        );
        expect(result, contains('un nami'));
        expect(result, isNot(contains('un-n-')));
      });

      test('mon + vowel → n onset', () {
        final result = PhoneticLiaisonService.apply(
          'mon oncle',
          'fr-FR',
        );
        expect(result, contains('mon noncle'));
      });

      test('petit + vowel → t onset', () {
        final result = PhoneticLiaisonService.apply(
          'petit enfant',
          'fr-FR',
        );
        expect(result, contains('petit tenfant'));
        expect(result, isNot(contains('petit-t-')));
      });

      test('sont + vowel → t onset', () {
        final result = PhoneticLiaisonService.apply(
          'sont allés',
          'fr-FR',
        );
        expect(result, contains('sont tallés'));
      });

      test('deux + vowel → z onset', () {
        final result = PhoneticLiaisonService.apply(
          'deux hommes',
          'fr-FR',
        );
        expect(result, contains('deux zhommes'));
      });

      test('dans + vowel → z onset', () {
        final result = PhoneticLiaisonService.apply(
          'dans un instant',
          'fr-FR',
        );
        expect(result, contains('dans zun'));
      });

      test('bien + vowel → n onset (preserves bien spelling)', () {
        final result = PhoneticLiaisonService.apply(
          'bien aimé',
          'fr-FR',
        );
        expect(result, contains('bien naim'));
        expect(result, isNot(contains('ben n')));
      });

      test('rien + vowel → n onset', () {
        final result = PhoneticLiaisonService.apply(
          'rien à faire',
          'fr-FR',
        );
        expect(result, contains('rien nà'));
      });

      test('multiple liaisons in one sentence', () {
        final result = PhoneticLiaisonService.apply(
          'les amis sont allés dans un petit hôtel',
          'fr-FR',
        );
        expect(result, contains('les zamis'));
        expect(result, contains('sont tallés'));
        expect(result, contains('dans zun'));
        expect(result, contains('petit thôtel'));
      });

      test('preserves case of vowel', () {
        final result = PhoneticLiaisonService.apply(
          'les Étoiles',
          'fr-FR',
        );
        expect(result, contains('les zÉtoiles'));
      });

      test('no liaison when next word starts with consonant', () {
        final result = PhoneticLiaisonService.apply(
          'les chats',
          'fr-FR',
        );
        expect(result, 'les chats');
      });
    });

    group('French — removed problematic [ʁ] liaisons', () {
      test('sur + vowel is NOT rewritten (avoids doubled r)', () {
        final result = PhoneticLiaisonService.apply(
          'sur une île',
          'fr-FR',
        );
        expect(result, 'sur une île');
      });

      test('pour + vowel is NOT rewritten', () {
        final result = PhoneticLiaisonService.apply(
          'pour aller',
          'fr-FR',
        );
        expect(result, 'pour aller');
      });

      test('par + vowel is NOT rewritten', () {
        final result = PhoneticLiaisonService.apply(
          'par ici',
          'fr-FR',
        );
        expect(result, 'par ici');
      });
    });

    group('English — linking R as onset', () {
      test('more + vowel → r onset', () {
        final result = PhoneticLiaisonService.apply(
          'more apples',
          'en-US',
        );
        expect(result, contains('more rapples'));
        expect(result, isNot(contains('more-r-')));
      });
    });

    group('Spanish — sinalefa preserved, z onset', () {
      test('los + vowel → z onset', () {
        final result = PhoneticLiaisonService.apply(
          'los amigos',
          'es-ES',
        );
        expect(result, contains('los zamigos'));
        expect(result, isNot(contains('los-z-')));
      });
    });

    group('German — s/n onset', () {
      test('das + vowel → s onset', () {
        final result = PhoneticLiaisonService.apply(
          'das ist',
          'de-DE',
        );
        expect(result, contains('das sist'));
        expect(result, isNot(contains('das-s-')));
      });

      test('ein + vowel → n onset', () {
        final result = PhoneticLiaisonService.apply(
          'ein Apfel',
          'de-DE',
        );
        expect(result, contains('ein nApfel'));
      });
    });

    group('Portuguese — z/m onset', () {
      test('os + vowel → z onset', () {
        final result = PhoneticLiaisonService.apply(
          'os amigos',
          'pt-PT',
        );
        expect(result, contains('os zamigos'));
      });

      test('um + vowel → m onset', () {
        final result = PhoneticLiaisonService.apply(
          'um amigo',
          'pt-PT',
        );
        expect(result, contains('um mamigo'));
      });
    });

    group('Unknown language — passthrough', () {
      test('returns text unchanged for unsupported language', () {
        final text = 'les étoiles';
        final result = PhoneticLiaisonService.apply(text, 'jp-JP');
        expect(result, text);
      });
    });
  });
}
