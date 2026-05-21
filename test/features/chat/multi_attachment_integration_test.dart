import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/domain/attachment.dart';
import 'package:airon_bot/features/chat/domain/message.dart';
import 'package:airon_bot/features/chat/data/model_router.dart';

void main() {
  group('Multi-Attachment Integration', () {
    group('5MB aggregate limit', () {
      test('10 images of 500KB each = exactly 5MB, accepted', () {
        final attachments = List.generate(
          10,
          (i) => Attachment(
            type: AttachmentType.image,
            name: 'img_$i.jpg',
            mimeType: 'image/jpeg',
            sizeBytes: 500 * 1024,
            imageBase64: 'a' * (500 * 1024), // approx 500KB string
          ),
        );
        final msg = Message(
          id: 'msg',
          conversationId: 'conv',
          role: Role.user,
          content: 'test',
          createdAt: DateTime.now(),
          attachments: attachments,
        );
        expect(msg.attachmentsTotalSize, 10 * 500 * 1024);
        expect(msg.exceedsAttachmentLimit, isFalse);
      });

      test('3 PDFs of 2MB each = 6MB, exceeds limit', () {
        final attachments = List.generate(
          3,
          (i) => Attachment(
            type: AttachmentType.pdf,
            name: 'doc_$i.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 2 * 1024 * 1024,
            extractedText: 'PDF content',
          ),
        );
        final msg = Message(
          id: 'msg',
          conversationId: 'conv',
          role: Role.user,
          content: 'test',
          createdAt: DateTime.now(),
          attachments: attachments,
        );
        expect(msg.attachmentsTotalSize, 3 * 2 * 1024 * 1024);
        expect(msg.exceedsAttachmentLimit, isTrue);
      });

      test('1 image + 1 PDF of 2MB + 1 TXT = OK if total <= 5MB', () {
        final attachments = [
          const Attachment(
            type: AttachmentType.image,
            name: 'photo.png',
            mimeType: 'image/png',
            sizeBytes: 500 * 1024,
            imageBase64: 'abc',
          ),
          const Attachment(
            type: AttachmentType.pdf,
            name: 'doc.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 2 * 1024 * 1024,
            extractedText: 'PDF',
          ),
          const Attachment(
            type: AttachmentType.text,
            name: 'notes.txt',
            mimeType: 'text/plain',
            sizeBytes: 100,
            extractedText: 'Notes',
          ),
        ];
        final msg = Message(
          id: 'msg',
          conversationId: 'conv',
          role: Role.user,
          content: 'test',
          createdAt: DateTime.now(),
          attachments: attachments,
        );
        expect(msg.exceedsAttachmentLimit, isFalse);
        expect(msg.hasImage, isTrue);
        expect(msg.hasFile, isTrue);
      });
    });

    group('Model routing by attachment type', () {
      test('images trigger vision model', () {
        final task = ModelRouter.classifyTask(
          'analyse',
          attachmentTypes: ['image'],
        );
        expect(task, TaskType.vision);
      });

      test('PDFs trigger document model', () {
        final task = ModelRouter.classifyTask(
          'analyse',
          attachmentTypes: ['pdf'],
        );
        expect(task, TaskType.document);
      });

      test('mixed types prioritize vision', () {
        final task = ModelRouter.classifyTask(
          'analyse',
          attachmentTypes: ['pdf', 'text', 'image'],
        );
        expect(task, TaskType.vision);
      });
    });

    group('Message API map with multiple images', () {
      test('toApiMap includes all images as parts', () {
        final msg = Message(
          id: 'msg',
          conversationId: 'conv',
          role: Role.user,
          content: 'Compare',
          createdAt: DateTime.now(),
          attachments: const [
            Attachment(
              type: AttachmentType.image,
              name: 'a.png',
              mimeType: 'image/png',
              sizeBytes: 1,
              imageBase64: 'base64a',
            ),
            Attachment(
              type: AttachmentType.image,
              name: 'b.png',
              mimeType: 'image/png',
              sizeBytes: 1,
              imageBase64: 'base64b',
            ),
          ],
        );
        final apiMap = msg.toApiMap();
        expect(apiMap['content'], isA<List>());
        final parts = apiMap['content'] as List;
        expect(parts.length, 3); // text + 2 images
        expect(parts[0]['type'], 'text');
        expect(parts[1]['type'], 'image_url');
        expect(parts[2]['type'], 'image_url');
        expect(parts[1]['image_url']['url'], 'data:image/png;base64,base64a');
        expect(parts[2]['image_url']['url'], 'data:image/png;base64,base64b');
      });

      test('toApiMap text-only when no images', () {
        final msg = Message(
          id: 'msg',
          conversationId: 'conv',
          role: Role.user,
          content: 'Hello',
          createdAt: DateTime.now(),
          attachments: const [
            Attachment(
              type: AttachmentType.pdf,
              name: 'doc.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 1,
              extractedText: 'PDF content',
            ),
          ],
        );
        final apiMap = msg.toApiMap();
        expect(apiMap['content'], 'Hello');
        expect(apiMap['content'], isNot(isA<List>()));
      });
    });

    group('File context building', () {
      test('buildFileContext concatenates multiple documents', () {
        final msg = Message(
          id: 'msg',
          conversationId: 'conv',
          role: Role.user,
          content: 'test',
          createdAt: DateTime.now(),
          attachments: const [
            Attachment(
              type: AttachmentType.pdf,
              name: 'doc1.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 1,
              extractedText: 'Content of PDF 1',
            ),
            Attachment(
              type: AttachmentType.text,
              name: 'notes.txt',
              mimeType: 'text/plain',
              sizeBytes: 1,
              extractedText: 'Text notes',
            ),
          ],
        );
        final ctx = msg.buildFileContext(isPro: false);
        expect(ctx, isNotNull);
        expect(ctx!, contains('Content of PDF 1'));
        expect(ctx, contains('Text notes'));
      });
    });
  });
}
