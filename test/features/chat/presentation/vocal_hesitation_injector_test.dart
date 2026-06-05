import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/features/chat/presentation/vocal_hesitation_injector.dart';

void main() {
  group('VocalHesitationInjector', () {
    test('texte court (<15 chars) → pas d\'injection', () {
      final text = 'Bonjour.';
      expect(VocalHesitationInjector.inject(text), text);
    });

    test('intensity 0 → pas d\'injection', () {
      final text = 'Ceci est un texte assez long pour être traité normalement.';
      expect(VocalHesitationInjector.inject(text, intensity: 0.0), text);
    });

    test('intensity élevée ne change pas le texte court', () {
      final text = 'Salut.';
      expect(VocalHesitationInjector.inject(text, intensity: 1.0), text);
    });

    test('texte long peut recevoir un prefixe hesitant', () {
      final text = 'Ceci est un texte suffisamment long pour recevoir une hésitation.';
      // Avec intensity=1.0, probabilité prefix = 0.4 (quasi certain après quelques essais)
      var found = false;
      for (var i = 0; i < 50; i++) {
        final result = VocalHesitationInjector.inject(text, intensity: 1.0);
        if (result != text) {
          found = true;
          break;
        }
      }
      expect(found, true, reason: 'Should inject prefix with intensity=1.0');
    });

    test('texte long peut recevoir une hésitation après virgule', () {
      final text = 'Bonjour, comment vas-tu, j\'espère que tout va bien.';
      var found = false;
      for (var i = 0; i < 50; i++) {
        final result = VocalHesitationInjector.inject(text, intensity: 1.0);
        if (result != text && result.contains('euh')) {
          found = true;
          break;
        }
      }
      expect(found, true, reason: 'Should inject mid-hesitation with intensity=1.0');
    });

    test('texte long peut recevoir une pause "..."', () {
      final text =
          'Ceci est un texte vraiment très long qui devrait recevoir une pause au milieu de la phrase.';
      var found = false;
      for (var i = 0; i < 50; i++) {
        final result = VocalHesitationInjector.inject(text, intensity: 1.0);
        if (result.contains('...')) {
          found = true;
          break;
        }
      }
      expect(found, true, reason: 'Should inject pause with intensity=1.0');
    });

    test('ne pas injecter de prefix si déjà hesitant', () {
      final text = 'Euh ceci est un texte suffisamment long pour tester.';
      final result = VocalHesitationInjector.inject(text, intensity: 1.0);
      // Should not add a second prefix; verify no double-prefix
      expect(result.startsWith('euh, euh'), false);
      expect(result.startsWith('euh, hmm'), false);
      expect(result.startsWith('euh, ben'), false);
      expect(result.startsWith('euh, alors'), false);
    });

    test('ne pas injecter de pause dans une URL', () {
      final text =
          'Visite https://example.com pour plus d\'informations sur ce sujet important.';
      final result = VocalHesitationInjector.inject(text, intensity: 1.0);
      expect(result.contains('https://...'), false);
    });

    test('ne pas injecter de pause dans du markdown', () {
      final text =
          'Voici du **texte en gras** et du code inline `print("hello")` pour tester.';
      final result = VocalHesitationInjector.inject(text, intensity: 1.0);
      // Should not break markdown with ... inside backticks or bold
      expect(result.contains('`...'), false);
      expect(result.contains('**...'), false);
    });

    test('injection aléatoire produit des résultats variés', () {
      final text = 'Ceci est un exemple de texte que nous allons utiliser pour tester l\'injection.';
      final results = <String>{};
      for (var i = 0; i < 20; i++) {
        results.add(VocalHesitationInjector.inject(text, intensity: 0.5));
      }
      // With 20 runs and intensity 0.5, we expect at least some variation
      expect(results.length > 1, true, reason: 'Should produce varied results');
    });
  });
}
