import 'dart:convert';
import 'dart:typed_data';

import 'package:corel_ia/features/chat/data/file_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = FileUploadService();

  Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

  group('extractText — fichiers texte', () {
    test('lit un .txt', () async {
      expect(
        await service.extractText(bytesOf('Bonjour le monde'), 'txt', 'a.txt'),
        'Bonjour le monde',
      );
    });

    test('lit un .csv et un .md', () async {
      expect(
        await service.extractText(bytesOf('nom,ville\nJean,Lyon'), 'csv', 'a.csv'),
        contains('Jean,Lyon'),
      );
      expect(
        await service.extractText(bytesOf('# Titre\ncorps'), 'md', 'a.md'),
        contains('# Titre'),
      );
    });

    test('ignore le BOM UTF-8', () async {
      final withBom = Uint8List.fromList([
        0xEF, 0xBB, 0xBF,
        ...utf8.encode('Bonjour'),
      ]);
      expect(await service.extractText(withBom, 'txt', 'a.txt'), 'Bonjour');
    });

    test('tolère l\'encodage imparfait', () async {
      final broken = Uint8List.fromList([0x41, 0xFF, 0x42]);
      expect(await service.extractText(broken, 'txt', 'a.txt'), isNotEmpty);
    });
  });

  group('extractText — PDF', () {
    /// PDF minimal contenant un flux texte non compressé.
    Uint8List pdfWith(String text) => bytesOf(
          '%PDF-1.4\n'
          '1 0 obj << /Length 60 >>\n'
          'stream\n'
          'BT /F1 12 Tf 72 720 Td ($text) Tj ET\n'
          'endstream\n'
          'endobj\n'
          'trailer << /Root 1 0 R >>\n'
          '%%EOF\n',
        );

    test('extrait le texte d\'un PDF non compressé', () async {
      final extracted =
          await service.extractText(pdfWith('Bonjour le monde'), 'pdf', 'a.pdf');

      expect(
        extracted,
        contains('Bonjour le monde'),
        reason: 'le texte doit être lu, pas remplacé par un gabarit',
      );
      // Une interpolation cassée produirait ceci à la place du texte :
      expect(extracted, isNot(contains(r'$fragment')));
    });

    test('signale un PDF sans texte exploitable', () async {
      final scanned = bytesOf('%PDF-1.4\n1 0 obj << >>\nendobj\n%%EOF\n');
      final extracted = await service.extractText(scanned, 'pdf', 'scan.pdf');

      expect(extracted, contains('PDF'));
      expect(extracted, isNotEmpty);
    });
  });

  group('extractText — erreurs', () {
    test('rejette un format non supporté', () async {
      await expectLater(
        service.extractText(bytesOf('x'), 'zip', 'a.zip'),
        throwsA(isA<FileUploadException>()),
      );
    });

    test('le message d\'erreur est interpolé', () async {
      try {
        await service.extractText(bytesOf('x'), 'zip', 'archive.zip');
        fail('une exception était attendue');
      } on FileUploadException catch (e) {
        expect(e.message, contains('.zip'));
        expect(e.message, isNot(contains(r'$ext')));
      }
    });

    test('signale un DOCX invalide sans lever', () async {
      final broken = bytesOf('ceci n\'est pas un zip');
      final extracted =
          await service.extractText(broken, 'docx', 'a.docx');

      // Soit un message explicatif, soit une exception contrôlée : jamais un
      // plantage silencieux.
      expect(extracted, isA<String>());
    });
  });

  group('truncateForContext', () {
    test('conserve un texte court', () {
      expect(
        FileUploadService.truncateForContext('court', isPro: false),
        'court',
      );
    });

    test('tronque un texte long en le signalant', () {
      final long = 'Phrase. ' * 5000;
      final truncated =
          FileUploadService.truncateForContext(long, isPro: false);

      expect(truncated.length, lessThan(long.length));
      expect(truncated, contains('tronque'));
    });

    test('le palier Full autorise plus de contexte', () {
      final long = 'Phrase. ' * 5000;
      final free = FileUploadService.truncateForContext(long, isPro: false);
      final pro = FileUploadService.truncateForContext(long, isPro: true);

      expect(pro.length, greaterThan(free.length));
    });
  });
}
