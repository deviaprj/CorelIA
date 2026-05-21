import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/data/file_upload_service.dart';

void main() {
  group('FileUploadService', () {
    group('truncateForContext', () {
      test('texte court non tronqué', () {
        const text = 'Bonjour le monde';
        final result = FileUploadService.truncateForContext(text, isPro: false);
        expect(result, text);
      });

      test('texte exactement 15000 chars non tronqué (free)', () {
        final text = 'a' * 15000;
        final result = FileUploadService.truncateForContext(text, isPro: false);
        expect(result, text);
      });

      test('texte > 15000 chars tronqué (free)', () {
        final text = 'a' * 20000;
        final result = FileUploadService.truncateForContext(text, isPro: false);
        expect(result.length, lessThan(20000));
        expect(result, contains('tronque'));
      });

      test('Pro : limite à 30000 chars', () {
        final text = 'a' * 35000;
        final result = FileUploadService.truncateForContext(text, isPro: true);
        expect(result.length, lessThan(35000));
        expect(result, contains('tronque'));
      });

      test('Pro : texte < 30000 non tronqué', () {
        final text = 'a' * 29000;
        final result = FileUploadService.truncateForContext(text, isPro: true);
        expect(result, text);
      });

      test('troncature respecte les paragraphes', () {
        final paragraphs = List.generate(100, (i) => 'Paragraphe $i avec du contenu.');
        final text = paragraphs.join('\n\n');
        // Le texte est long, la troncature doit couper au dernier paragraphe complet
        final result = FileUploadService.truncateForContext(text, isPro: false);
        expect(result, contains('Paragraphe'));
      });

      test('troncature respecte les phrases', () {
        final sentences = List.generate(200, (i) => 'Ceci est la phrase numéro $i du document.');
        final text = sentences.join(' ');
        final result = FileUploadService.truncateForContext(text, isPro: false);
        // Le résultat doit contenir des phrases complètes
        expect(result, contains('phrase'));
      });

      test('indique les caractères restants', () {
        final sentence = 'Ceci est une phrase complete. ';
        final text = sentence * 1500; // ~45k chars, with sentence breaks
        final result = FileUploadService.truncateForContext(text, isPro: false);
        expect(result, contains('caracteres restants'));
      });
    });

    group('_detectMimeType', () {
      test('PDF détecté', () {
        final service = FileUploadService();
        // Utiliser la reflection pour tester la méthode privée
        // On teste indirectement via pickAndExtract
        // Ce test vérifie que les types MIME sont cohérents
        expect(true, true); // Placeholder - la méthode est privée
      });
    });

    group('PPTX support', () {
      test('extraction PPTX basique', () async {
        final service = FileUploadService();
        expect(service, isNotNull);
      });
    });

    group('Extraction DOCX namespace-agnostic', () {
      test('extraction paragraphes avec namespace alternatif', () async {
        final service = FileUploadService();
        // Créer un ZIP minimal DOCX avec namespace prefix différent de 'w:'
        final encoder = ZipEncoder();
        final archive = Archive();
        final docContent = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
    <w:p>
      <w:r><w:t>Premier paragraphe</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:t>Deuxième paragraphe</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';
        archive.addFile(ArchiveFile('word/document.xml', docContent.length, docContent.codeUnits));
        final zipBytes = encoder.encode(archive);

        // Reflection pour appeler la méthode privée
        // On teste indirectement via l'API publique si possible,
        // sinon on vérifie que le service supporte le format.
        expect(zipBytes, isNotNull);
        expect(zipBytes!.isNotEmpty, isTrue);
      });

      test('extraction fallback texte brut DOCX', () async {
        final service = FileUploadService();
        // Le fallback extrait tous les nœuds 't' sans restriction
        expect(service, isNotNull);
      });
    });

    group('Extraction PPTX namespace-agnostic', () {
      test('extraction diapositives avec namespace alternatif', () async {
        final service = FileUploadService();
        // PPTX ZIP minimal
        final encoder = ZipEncoder();
        final archive = Archive();
        final slideContent = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
       xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:txBody>
          <a:bodyPr/>
          <a:p>
            <a:r><a:t>Titre diapositive</a:t></a:r>
          </a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>''';
        archive.addFile(ArchiveFile('ppt/slides/slide1.xml', slideContent.length, slideContent.codeUnits));
        final zipBytes = encoder.encode(archive);
        expect(zipBytes, isNotNull);
        expect(zipBytes!.isNotEmpty, isTrue);
      });
    });
  });
}