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

      final image = parts.last as Map<String, dynamic>;
      final imageUrl = image['image_url'] as Map<String, dynamic>;
      expect(
        imageUrl['url'],
        'data:image/jpeg;base64,AAAA',
        reason: 'le Worker transmet cette URL telle quelle au modèle vision',
      );
    });

    test('toApiMap décrit l\'image si l\'utilisateur n\'a rien écrit', () {
      final map = buildMessage(
        content: '',
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

      final parts = map['content'] as List<dynamic>;
      final text = parts.first as Map<String, dynamic>;
      expect(text['text'], isNotEmpty);
    });

    test('toFirestore conserve le texte extrait et le contexte documentaire', () {
      final message = Message(
        id: 'm3',
        conversationId: 'c1',
        role: Role.user,
        content: 'Résume ce document',
        createdAt: DateTime(2026, 9, 20),
        fileContext: 'Document : rapport.pdf\nZORGLUB-42',
        attachments: const [
          Attachment(
            type: AttachmentType.document,
            name: 'rapport.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 20,
            extractedText: 'ZORGLUB-42',
          ),
        ],
      );

      final data = message.toFirestore();
      expect(
        data['fileContext'],
        contains('ZORGLUB-42'),
        reason: 'sans cela, une question de suivi perdrait le document',
      );
      final attachments = data['attachments'] as List<dynamic>;
      final first = attachments.single as Map<String, dynamic>;
      expect(first['extractedText'], 'ZORGLUB-42');
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

    test('buildFileContext ne présente pas un échec comme du contenu', () {
      final message = buildMessage(
        attachments: const [
          Attachment(
            type: AttachmentType.pdf,
            name: 'scan.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 20,
            extractedText:
                '[Document illisible] PDF sans couche texte exploitable.',
          ),
        ],
      );

      final context = message.buildFileContext(isFull: false);
      expect(context, contains('scan.pdf'));
      expect(context, contains('Lecture automatique impossible'));
      expect(
        context,
        isNot(contains('Document illisible')),
        reason: 'le marqueur ne doit jamais passer pour du contenu',
      );
    });

    test('isUnreadableText distingue un marqueur d\'un vrai contenu', () {
      expect(Attachment.isUnreadableText('[Document illisible] PDF…'), isTrue);
      expect(Attachment.isUnreadableText('  [Document illisible] PDF'), isTrue);
      expect(Attachment.isUnreadableText('Le vrai contenu'), isFalse);
      expect(Attachment.isUnreadableText(null), isFalse);
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
