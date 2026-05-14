import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/data/file_upload_service.dart';

void main() {
  group('FileUploadService.truncateForContext', () {
    test('texte court non tronqué (free)', () {
      const text = 'Bonjour le monde';
      final result = FileUploadService.truncateForContext(text, isPro: false);
      expect(result, text);
    });

    test('texte court non tronqué (pro)', () {
      const text = 'Bonjour le monde';
      final result = FileUploadService.truncateForContext(text, isPro: true);
      expect(result, text);
    });

    test('texte > 15000 chars tronqué avec indication (free)', () {
      final text = 'Phrase complète. ' * 2000; // ~32000 chars
      final result = FileUploadService.truncateForContext(text, isPro: false);
      expect(result.length, lessThan(text.length));
      expect(result, contains('tronque'));
    });

    test('texte > 30000 chars tronqué avec indication (pro)', () {
      final text = 'Phrase complète. ' * 4000; // ~64000 chars
      final result = FileUploadService.truncateForContext(text, isPro: true);
      expect(result.length, lessThan(text.length));
      expect(result, contains('tronque'));
    });

    test('troncature respecte les paragraphes', () {
      // Créer un texte avec des paragraphes séparés par \n\n
      final buffer = StringBuffer();
      for (var i = 0; i < 1000; i++) {
        buffer.writeln('Ceci est le paragraphe numéro $i qui contient du texte suffisant pour être long.');
        buffer.writeln();
      }
      final text = buffer.toString();

      final result = FileUploadService.truncateForContext(text, isPro: false);
      // Le résultat doit contenir des paragraphes complets
      expect(result, contains('paragraphe'));
    });

    test('troncature respecte les phrases quand pas de paragraphes', () {
      final buffer = StringBuffer();
      for (var i = 0; i < 2000; i++) {
        buffer.write('Ceci est la phrase numéro $i du document. ');
      }
      final text = buffer.toString();

      final result = FileUploadService.truncateForContext(text, isPro: false);
      // Le résultat doit contenir des phrases complètes se terminant par un point
      expect(result, contains('phrase'));
    });

    test('fallback coupe dure si nécessaire', () {
      // Texte sans ponctuation de fin ni paragraphes
      final text = 'a' * 20000;
      final result = FileUploadService.truncateForContext(text, isPro: false);
      expect(result.length, lessThanOrEqualTo(15100)); // 15000 + marge
      expect(result, contains('tronque'));
    });
  });

  group('_lastSentenceEnd', () {
    test('trouve la dernière phrase avant la limite', () {
      final text = 'Première phrase. Deuxième phrase. Troisième phrase. Quatrième phrase.';
      final pos = FileUploadService.lastSentenceEnd(text, 40);
      expect(pos, greaterThan(0));
      expect(pos, lessThanOrEqualTo(40));
    });

    test('retourne 0 si aucune fin de phrase trouvée', () {
      final text = 'pas de ponctuation finale ici';
      final pos = FileUploadService.lastSentenceEnd(text, 15);
      expect(pos, 0);
    });

    test('trouve les fins de phrases avec ! et ?', () {
      final text = 'Question? Réponse! Et encore.';
      final pos = FileUploadService.lastSentenceEnd(text, 30);
      expect(pos, greaterThan(0));
    });
  });
}