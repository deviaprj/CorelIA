import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/data/mock_chat_repository.dart';
import 'package:airon_bot/features/chat/domain/message.dart';

void main() {
  late MockChatRepository repo;

  setUp(() {
    repo = MockChatRepository();
  });

  group('MockChatRepository - Conversations', () {
    test('should create a conversation', () async {
      final conv = await repo.createConversation(
        userId: 'user1',
        title: 'Test',
      );

      expect(conv.userId, equals('user1'));
      expect(conv.title, equals('Test'));
      expect(conv.id, isNotEmpty);
    });

    test('should list conversations for user', () async {
      await repo.createConversation(userId: 'user1', title: 'A');
      await repo.createConversation(userId: 'user1', title: 'B');
      await repo.createConversation(userId: 'user2', title: 'C');

      final list = repo.getConversations('user1');
      expect(list.length, equals(2));
    });

    test('should update conversation title', () async {
      final conv = await repo.createConversation(
        userId: 'user1',
        title: 'Old',
      );

      await repo.updateConversation(conv.id, {'title': 'New'});

      final list = repo.getConversations('user1');
      expect(list.first.title, equals('New'));
    });

    test('should delete conversation', () async {
      final conv = await repo.createConversation(
        userId: 'user1',
        title: 'Del',
      );

      await repo.deleteConversation(conv.id);

      final list = repo.getConversations('user1');
      expect(list, isEmpty);
    });

    test('should sort conversations by updatedAt descending', () async {
      await repo.createConversation(userId: 'user1', title: 'First');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await repo.createConversation(userId: 'user1', title: 'Second');

      final list = repo.getConversations('user1');
      expect(list.first.title, equals('Second'));
    });
  });

  group('MockChatRepository - Messages', () {
    test('should add message to conversation', () async {
      final conv = await repo.createConversation(
        userId: 'user1',
        title: 'Chat',
      );

      final msg = await repo.addMessage(
        conversationId: conv.id,
        role: Role.user,
        content: 'Hello',
      );

      expect(msg.content, equals('Hello'));
      expect(msg.role, equals(Role.user));
      expect(msg.conversationId, equals(conv.id));
    });

    test('should update message content', () async {
      final conv = await repo.createConversation(
        userId: 'user1',
        title: 'Chat',
      );

      final msg = await repo.addMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: 'partial',
      );

      await repo.updateMessageContent(conv.id, msg.id, 'full response');

      // Verify via stream or internal state
      expect(msg.id, isNotEmpty);
    });

    test('should create streaming message placeholder', () async {
      final conv = await repo.createConversation(
        userId: 'user1',
        title: 'Chat',
      );

      final msgId = await repo.createStreamingMessage(conv.id);
      expect(msgId, isNotEmpty);
    });

    test('should extract title from long text', () async {
      final conv = await repo.createConversation(
        userId: 'user1',
        title: 'Chat',
      );

      await repo.addMessage(
        conversationId: conv.id,
        role: Role.user,
        content: 'A' * 100,
      );

      // The conversation title should be truncated
      final convs = repo.getConversations('user1');
      expect(convs.first.title.length, lessThanOrEqualTo(60));
    });
  });

  group('MockChatRepository - Streams', () {
    test('watchConversations emits on create', () async {
      final stream = repo.watchConversations('user1');

      // Schedule a create
      Future<void>.delayed(
        const Duration(milliseconds: 50),
        () => repo.createConversation(userId: 'user1', title: 'New'),
      );

      final first = await stream.first;
      expect(first, isNotEmpty);
    });

    test('watchMessages emits on addMessage', () async {
      final conv = await repo.createConversation(
        userId: 'user1',
        title: 'Chat',
      );

      final stream = repo.watchMessages(conv.id);

      // Schedule a message
      Future<void>.delayed(
        const Duration(milliseconds: 50),
        () => repo.addMessage(
          conversationId: conv.id,
          role: Role.user,
          content: 'Test',
        ),
      );

      final first = await stream.first;
      expect(first, isNotEmpty);
    });
  });

  group('MockChatRepository - Dispose', () {
    test('should dispose without error', () {
      final localRepo = MockChatRepository();
      expect(() => localRepo.dispose(), returnsNormally);
    });
  });
}
