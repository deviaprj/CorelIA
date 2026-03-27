import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/domain/message.dart';

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

    test('should convert to API map', () {
      final apiMap = testMessage.toApiMap();

      expect(apiMap['role'], equals('user'));
      expect(apiMap['content'], equals('Hello, this is a test message'));
      expect(apiMap.containsKey('id'), isFalse);
      expect(apiMap.containsKey('createdAt'), isFalse);
    });

    test('should convert to Firestore map', () {
      final firestoreMap = testMessage.toFirestore();

      expect(firestoreMap['conversationId'], equals('conv_456'));
      expect(firestoreMap['role'], equals('user'));
      expect(firestoreMap['content'], equals('Hello, this is a test message'));
      expect(firestoreMap['isStreaming'], isFalse);
      expect(firestoreMap.containsKey('createdAt'), isTrue);
    });

    test('should create from Firestore document', () {
      final mockData = {
        'conversationId': 'conv_789',
        'role': 'assistant',
        'content': 'Test response',
        'model': 'deepseek-chat',
        'isStreaming': false,
        'createdAt': DateTime(2024, 1, 15, 10, 35),
      };

      final message = Message(
        id: 'doc_123',
        conversationId: mockData['conversationId'] as String,
        role: Role.values.firstWhere(
          (r) => r.name == mockData['role'],
          orElse: () => Role.user,
        ),
        content: mockData['content'] as String,
        model: mockData['model'] as String?,
        isStreaming: mockData['isStreaming'] as bool,
        createdAt: mockData['createdAt'] as DateTime,
      );

      expect(message.id, equals('doc_123'));
      expect(message.role, equals(Role.assistant));
      expect(message.model, equals('deepseek-chat'));
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

    test('should handle system messages', () {
      final systemMsg = Message(
        id: 'msg_126',
        conversationId: 'conv_456',
        role: Role.system,
        content: 'System instruction',
        createdAt: DateTime.now(),
      );

      expect(systemMsg.isUser, isFalse);
      expect(systemMsg.isAssistant, isFalse);
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
  });
}
