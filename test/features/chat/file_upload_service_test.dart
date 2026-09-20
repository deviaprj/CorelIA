import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:corel_ia/core/models/attachment.dart';
import 'package:corel_ia/features/chat/data/file_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = FileUploadService();

  Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

  /// Encode en UTF-16 (avec BOM), comme le Bloc-notes Windows « Unicode ».
  Uint8List utf16WithBom(String text, {required bool bigEndian}) {
    final out = <int>[
      if (bigEndian) ...[0xFE, 0xFF] else ...[0xFF, 0xFE],
    ];
    for (final unit in text.codeUnits) {
      if (bigEndian) {
        out..add((unit >> 8) & 0xFF)..add(unit & 0xFF);
      } else {
        out..add(unit & 0xFF)..add((unit >> 8) & 0xFF);
      }
    }
    return Uint8List.fromList(out);
  }

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

    test('lit un .txt UTF-16 (Bloc-notes « Unicode »)', () async {
      const french = 'Résumé du café à Lyon';
      expect(
        await service.extractText(
          utf16WithBom(french, bigEndian: false),
          'txt',
          'a.txt',
        ),
        french,
      );
      expect(
        await service.extractText(
          utf16WithBom(french, bigEndian: true),
          'txt',
          'a.txt',
        ),
        french,
      );
    });

    test('lit un .txt « ANSI » (Latin-1) sans perdre les accents', () async {
      const french = 'Résumé du café à Lyon, déjà vu';
      final extracted = await service.extractText(
        Uint8List.fromList(latin1.encode(french)),
        'txt',
        'a.txt',
      );

      expect(extracted, french);
      expect(
        extracted,
        isNot(contains('\uFFFD')),
        reason: 'les accents perdus faisaient passer le texte pour du binaire',
      );
    });

    test('décode un .txt CP1252 (€, apostrophe courbe)', () async {
      // « R’sultat : 10 € » en CP1252 : 0x92 = ’, 0x80 = €.
      final bytes = Uint8List.fromList([
        0x52, 0x92, 0x73, 0x75, 0x6C, 0x74, 0x61, 0x74, 0x20, 0x3A,
        0x20, 0x31, 0x30, 0x20, 0x80,
      ]);
      expect(
        await service.extractText(bytes, 'txt', 'a.txt'),
        'R’sultat : 10 €',
      );
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

    /// Même PDF, mais avec l'opérateur de tableau `TJ` (forme la plus répandue).
    Uint8List pdfWithTjArray(String text) => bytesOf(
          '%PDF-1.4\n'
          '1 0 obj << /Length 60 >>\n'
          'stream\n'
          'BT /F1 12 Tf 72 720 Td [($text)] TJ ET\n'
          'endstream\n'
          'endobj\n'
          '%%EOF\n',
        );

    /// PDF dont le flux de contenu est réellement compressé (zlib/FlateDecode).
    Uint8List pdfWithFlateStream(String text) {
      final content = 'BT /F1 12 Tf 72 720 Td [($text)] TJ ET';
      final compressed =
          Uint8List.fromList(const ZLibEncoder().encode(utf8.encode(content)));
      return Uint8List.fromList([
        ...bytesOf(
          '%PDF-1.4\n'
          '1 0 obj << /Filter /FlateDecode /Length ${compressed.length} >>\n'
          'stream\n',
        ),
        ...compressed,
        ...bytesOf('\nendstream\nendobj\n%%EOF\n'),
      ]);
    }

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

    test('extrait le texte d\'un opérateur TJ (tableau)', () async {
      final extracted = await service.extractText(
        pdfWithTjArray('Bonjour le monde'),
        'pdf',
        'tj.pdf',
      );

      expect(extracted, contains('Bonjour'));
      expect(extracted, contains('monde'));
    });

    test('décompresse un flux FlateDecode (zlib)', () async {
      final extracted = await service.extractText(
        pdfWithFlateStream('Bonjour le monde'),
        'pdf',
        'flate.pdf',
      );

      expect(
        extracted,
        contains('Bonjour'),
        reason: 'un flux zlib doit être décompressé, pas ignoré',
      );
      expect(extracted, contains('monde'));
    });

    test('ne lit que le flux /Contents, pas les flux de police', () async {
      // Le vrai texte est dans l'objet référencé par /Contents ; un autre flux
      // contient du bruit qui ressemble à du texte (cas des polices/CMap).
      final structured = bytesOf(
        '%PDF-1.4\n'
        '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'
        '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'
        '3 0 obj << /Type /Page /Parent 2 0 R /Contents 4 0 R >> endobj\n'
        '4 0 obj\n'
        'stream\n'
        'BT /F1 12 Tf 72 720 Td (Bonjour le monde) Tj ET\n'
        'endstream\n'
        'endobj\n'
        '5 0 obj\n'
        'stream\n'
        'BT /F9 1 Tf (ZZZBRUITPOLICE) Tj ET\n'
        'endstream\n'
        'endobj\n'
        '%%EOF\n',
      );

      final extracted =
          await service.extractText(structured, 'pdf', 'page.pdf');

      expect(extracted, contains('Bonjour'));
      expect(
        extracted,
        isNot(contains('ZZZBRUITPOLICE')),
        reason: 'balayer tous les flux ramassait les polices et les CMap',
      );
    });

    test('signale un flux de contenu illisible au lieu de le restituer', () async {
      // Polices CID sans ToUnicode : les opérandes sont des indices de glyphes,
      // imprimables mais sans mots. Mieux vaut un échec explicite que du charabia.
      final cidLike = bytesOf(
        '%PDF-1.4\n'
        '3 0 obj << /Type /Page /Contents 4 0 R >> endobj\n'
        '4 0 obj\n'
        'stream\n'
        'BT /F1 1 Tf (a b c d e f g h i j k) Tj ET\n'
        'endstream\n'
        'endobj\n'
        '%%EOF\n',
      );

      final extracted = await service.extractText(cidLike, 'pdf', 'cid.pdf');

      expect(
        Attachment.isUnreadableText(extracted),
        isTrue,
        reason: 'un amas de caractères isolés n\'est pas du texte lisible',
      );
      expect(extracted, isNot(contains('a b c d e')));
    });

    test('ne restitue jamais du bruit binaire comme du texte', () async {
      // Flux binaire qui, décodé en force, produirait du charabia : mieux vaut
      // un échec explicite qu'un contexte IA pollué par des octets de police.
      final noise = bytesOf(
        '%PDF-1.4\n'
        '1 0 obj << /Length 40 >>\n'
        'stream\n'
        '<000102030405060708090A0B0C0D0E0F>\n'
        'endstream\n'
        'endobj\n'
        '%%EOF\n',
      );

      final extracted = await service.extractText(noise, 'pdf', 'noise.pdf');

      expect(extracted, startsWith('['));
      expect(extracted, contains('PDF'));
      expect(extracted, isNot(contains('\uFFFD')));
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
