import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/features/chat/domain/message.dart';
import 'package:corel_ia/features/chat/domain/attachment.dart';

void main() {
  group('Message Model', () {
    final testMessage = Message(
      id: 'msg_123',
      conversationId: 'conv_456',
      role: Role.user,
      content: 'Hello, this is a test message',
      model: null,
      isStreaming: false,
      createdAt: DateTime(2024, 1, 15, 10, 30),
    );

    test('should create message with correct values', () {
      expect(testMessage.id, equals('msg_123'));
      expect(testMessage.conversationId, equals('conv_456'));
      expect(testMessage.role, equals(Role.user));
      expect(testMessage.content, equals('Hello, this is a test message'));
      expect(testMessage.model, isNull);
      expect(testMessage.isStreaming, isFalse);
      expect(testMessage.createdAt, equals(DateTime(2024, 1, 15, 10, 30)));
    });

    test('should identify user messages', () {
      expect(testMessage.isUser, isTrue);
      expect(testMessage.isAssistant, isFalse);
    });

    test('should identify assistant messages', () {
      final assistantMessage = Message(
        id: 'msg_124',
        conversationId: 'conv_456',
        role: Role.assistant,
        content: 'Hello! How can I help you?',
        createdAt: DateTime(2024, 1, 15, 10, 31),
      );
      expect(assistantMessage.isAssistant, isTrue);
      expect(assistantMessage.isUser, isFalse);
    });

    test('should copy with new values', () {
      final updated = testMessage.copyWith(
        content: 'Updated content',
        isStreaming: true,
      );
      expect(updated.content, equals('Updated content'));
      expect(updated.isStreaming, isTrue);
      expect(updated.id, equals(testMessage.id));
      expect(updated.role, equals(testMessage.role));
    });

    test('should convert to API map (text only)', () {
      final apiMap = testMessage.toApiMap();
      expect(apiMap['role'], equals('user'));
      expect(apiMap['content'], equals('Hello, this is a test message'));
    });

    test('should convert to API map with image attachments', () {
      final msg = Message(
        id: 'msg_img',
        conversationId: 'conv_1',
        role: Role.user,
        content: 'Analyse cette image',
        createdAt: DateTime.now(),
        attachments: const [
          Attachment(
            type: AttachmentType.image,
            name: 'photo.png',
            mimeType: 'image/png',
            sizeBytes: 1234,
            imageBase64: 'abc123',
          ),
        ],
      );
      final apiMap = msg.toApiMap();
      expect(apiMap['role'], equals('user'));
      expect(apiMap['content'], isA<List>());
      final parts = apiMap['content'] as List;
      expect(parts.length, 2);
      expect(parts[0]['type'], 'text');
      expect(parts[1]['type'], 'image_url');
    });

    test('should convert to Firestore map', () {
      final firestoreMap = testMessage.toFirestore();
      expect(firestoreMap['conversationId'], equals('conv_456'));
      expect(firestoreMap['role'], equals('user'));
      expect(firestoreMap['content'], equals('Hello, this is a test message'));
      expect(firestoreMap['isStreaming'], isFalse);
      expect(firestoreMap.containsKey('createdAt'), isTrue);
    });

    test('should handle streaming messages', () {
      final streamingMsg = Message(
        id: 'msg_125',
        conversationId: 'conv_456',
        role: Role.assistant,
        content: 'Typing...',
        isStreaming: true,
        createdAt: DateTime.now(),
      );
      expect(streamingMsg.isStreaming, isTrue);
    });

    test('should preserve model information', () {
      final msgWithModel = Message(
        id: 'msg_127',
        conversationId: 'conv_456',
        role: Role.assistant,
        content: 'Response',
        model: 'deepseek-chat',
        createdAt: DateTime.now(),
      );
      expect(msgWithModel.model, equals('deepseek-chat'));
    });

    test('hasImage detects image attachments', () {
      final msg = Message(
        id: 'msg',
        conversationId: 'conv',
        role: Role.user,
        content: 'test',
        createdAt: DateTime.now(),
        attachments: const [
          Attachment(type: AttachmentType.image, name: 'a.png', mimeType: 'image/png', sizeBytes: 1),
        ],
      );
      expect(msg.hasImage, isTrue);
      expect(msg.hasFile, isFalse);
    });

    test('hasFile detects document attachments', () {
      final msg = Message(
        id: 'msg',
        conversationId: 'conv',
        role: Role.user,
        content: 'test',
        createdAt: DateTime.now(),
        attachments: const [
          Attachment(type: AttachmentType.pdf, name: 'a.pdf', mimeType: 'application/pdf', sizeBytes: 1),
        ],
      );
      expect(msg.hasFile, isTrue);
      expect(msg.hasImage, isFalse);
    });

    test('attachmentsTotalSize sums all attachments', () {
      final msg = Message(
        id: 'msg',
        conversationId: 'conv',
        role: Role.user,
        content: 'test',
        createdAt: DateTime.now(),
        attachments: const [
          Attachment(type: AttachmentType.image, name: 'a.png', mimeType: 'image/png', sizeBytes: 1000),
          Attachment(type: AttachmentType.pdf, name: 'b.pdf', mimeType: 'application/pdf', sizeBytes: 2000),
        ],
      );
      expect(msg.attachmentsTotalSize, 3000);
    });

    test('exceedsAttachmentLimit at 5MB', () {
      final msg = Message(
        id: 'msg',
        conversationId: 'conv',
        role: Role.user,
        content: 'test',
        createdAt: DateTime.now(),
        attachments: const [
          Attachment(type: AttachmentType.image, name: 'a.png', mimeType: 'image/png', sizeBytes: maxAttachmentsTotalBytes + 1),
        ],
      );
      expect(msg.exceedsAttachmentLimit, isTrue);
    });

    test('buildFileContext truncates documents', () {
      final msg = Message(
        id: 'msg',
        conversationId: 'conv',
        role: Role.user,
        content: 'test',
        createdAt: DateTime.now(),
        attachments: const [
          Attachment(
            type: AttachmentType.pdf,
            name: 'doc.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 100,
            extractedText: 'Contenu du PDF',
          ),
        ],
      );
      final ctx = msg.buildFileContext(isPro: false);
      expect(ctx, isNotNull);
      expect(ctx!, contains('Contenu du PDF'));
    });
  });
}
