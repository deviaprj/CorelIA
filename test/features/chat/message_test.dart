import 'package:corel_ia/core/models/attachment.dart';
import 'package:corel_ia/core/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Message buildMessage({
    Role role = Role.user,
    String content = 'Bonjour',
    List<Attachment> attachments = const [],
  }) =>
      Message(
        id: 'm1',
        conversationId: 'c1',
        role: role,
        content: content,
        createdAt: DateTime(2026, 9, 20),
        attachments: attachments,
      );

  group('Message', () {
    test('expose le rôle et la taille des pièces jointes', () {
      final message = buildMessage(
        attachments: const [
          Attachment(
            type: AttachmentType.image,
            name: 'photo.jpg',
            mimeType: 'image/jpeg',
            sizeBytes: 1024,
          ),
        ],
      );
      expect(message.isUser, isTrue);
      expect(message.isAssistant, isFalse);
      expect(message.hasImage, isTrue);
      expect(message.attachmentsTotalSize, 1024);
    });

    test('toApiMap renvoie du texte simple sans image', () {
      final map = buildMessage().toApiMap();
      expect(map['role'], 'user');
      expect(map['content'], 'Bonjour');
    });

    test('toApiMap produit un contenu multimodal avec image', () {
      final map = buildMessage(
        attachments: const [
          Attachment(
            type: AttachmentType.image,
            name: 'photo.jpg',
            mimeType: 'image/jpeg',
            sizeBytes: 10,
            imageBase64: 'AAAA',
          ),
        ],
      ).toApiMap();

      expect(map['content'], isA<List<dynamic>>());
      final parts = map['content'] as List<dynamic>;
      expect(parts.first, containsPair('type', 'text'));
      expect(parts.last, containsPair('type', 'image_url'));
    });

    test('buildFileContext concatène les documents texte', () {
      final message = buildMessage(
        attachments: const [
          Attachment(
            type: AttachmentType.document,
            name: 'rapport.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 20,
            extractedText: 'Contenu du rapport',
          ),
        ],
      );
      final context = message.buildFileContext(isFull: false);
      expect(context, contains('rapport.pdf'));
      expect(context, contains('Contenu du rapport'));
    });

    test('buildFileContext renvoie null sans document', () {
      expect(buildMessage().buildFileContext(isFull: false), isNull);
    });

    test('copyWith met à jour le contenu et l\'état de streaming', () {
      final message = buildMessage(content: 'ancien');
      final updated = message.copyWith(content: 'nouveau', isStreaming: true);
      expect(updated.content, 'nouveau');
      expect(updated.isStreaming, isTrue);
      expect(updated.id, message.id);
    });

    test('searchSources est exposé', () {
      final message = Message(
        id: 'm2',
        conversationId: 'c1',
        role: Role.assistant,
        content: 'réponse',
        createdAt: DateTime(2026, 9, 20),
        searchSources: const ['Titre|https://example.com'],
      );
      expect(message.hasSearchSources, isTrue);
      expect(message.searchSources!.first, contains('example.com'));
    });
  });
}
