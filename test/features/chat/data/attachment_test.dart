import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/features/chat/domain/attachment.dart';

void main() {
  group('Attachment', () {
    test('detectType image', () {
      expect(Attachment.detectType('photo.png'), AttachmentType.image);
      expect(Attachment.detectType('photo.jpg'), AttachmentType.image);
      expect(Attachment.detectType('photo.jpeg'), AttachmentType.image);
      expect(Attachment.detectType('photo.webp'), AttachmentType.image);
      expect(Attachment.detectType('photo.gif'), AttachmentType.image);
      expect(Attachment.detectType('photo.bmp'), AttachmentType.image);
    });

    test('detectType pdf', () {
      expect(Attachment.detectType('doc.pdf'), AttachmentType.pdf);
    });

    test('detectType document', () {
      expect(Attachment.detectType('doc.docx'), AttachmentType.document);
    });

    test('detectType spreadsheet', () {
      expect(Attachment.detectType('data.xlsx'), AttachmentType.spreadsheet);
    });

    test('detectType presentation', () {
      expect(Attachment.detectType('slides.pptx'), AttachmentType.presentation);
    });

    test('detectType text', () {
      expect(Attachment.detectType('notes.txt'), AttachmentType.text);
      expect(Attachment.detectType('data.csv'), AttachmentType.text);
      expect(Attachment.detectType('readme.md'), AttachmentType.text);
    });

    test('detectType fallback text', () {
      expect(Attachment.detectType('unknown.xyz'), AttachmentType.text);
    });

    test('toFirestore roundtrip', () {
      const att = Attachment(
        type: AttachmentType.image,
        name: 'photo.png',
        mimeType: 'image/png',
        sizeBytes: 1234,
        imageBase64: 'abc123',
        extractedText: null,
      );
      final map = att.toFirestore();
      expect(map['type'], 'image');
      expect(map['name'], 'photo.png');
      expect(map['mimeType'], 'image/png');
      expect(map['sizeBytes'], 1234);
      expect(map['imageBase64'], 'abc123');

      final restored = Attachment.fromFirestore(map);
      expect(restored.type, AttachmentType.image);
      expect(restored.name, 'photo.png');
      expect(restored.sizeBytes, 1234);
    });

    test('toApiPart for image', () {
      const att = Attachment(
        type: AttachmentType.image,
        name: 'photo.png',
        mimeType: 'image/png',
        sizeBytes: 1234,
        imageBase64: 'abc123',
      );
      final part = att.toApiPart();
      expect(part, isNotNull);
      expect(part!['type'], 'image_url');
      expect(part['image_url']['url'], 'data:image/png;base64,abc123');
    });

    test('toApiPart for non-image returns null', () {
      const att = Attachment(
        type: AttachmentType.pdf,
        name: 'doc.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 5000,
        extractedText: 'Contenu PDF',
      );
      expect(att.toApiPart(), isNull);
    });

    test('isImage / isDocument / isPdf / isText', () {
      const img = Attachment(type: AttachmentType.image, name: 'a.png', mimeType: 'image/png', sizeBytes: 1);
      const pdf = Attachment(type: AttachmentType.pdf, name: 'a.pdf', mimeType: 'application/pdf', sizeBytes: 1);
      const txt = Attachment(type: AttachmentType.text, name: 'a.txt', mimeType: 'text/plain', sizeBytes: 1);
      const doc = Attachment(type: AttachmentType.document, name: 'a.docx', mimeType: 'application/vnd...', sizeBytes: 1);
      const xls = Attachment(type: AttachmentType.spreadsheet, name: 'a.xlsx', mimeType: 'application/vnd...', sizeBytes: 1);
      const ppt = Attachment(type: AttachmentType.presentation, name: 'a.pptx', mimeType: 'application/vnd...', sizeBytes: 1);

      expect(img.isImage, isTrue);
      expect(img.isDocument, isFalse);
      expect(pdf.isPdf, isTrue);
      expect(txt.isText, isTrue);
      expect(doc.isDocument, isTrue);
      expect(xls.isSpreadsheet, isTrue);
      expect(ppt.isPresentation, isTrue);
    });

    test('copyWith', () {
      const att = Attachment(
        type: AttachmentType.image,
        name: 'photo.png',
        mimeType: 'image/png',
        sizeBytes: 1234,
      );
      final copied = att.copyWith(name: 'new.png', sizeBytes: 5678);
      expect(copied.type, AttachmentType.image);
      expect(copied.name, 'new.png');
      expect(copied.sizeBytes, 5678);
      expect(copied.mimeType, 'image/png');
    });
  });
}
