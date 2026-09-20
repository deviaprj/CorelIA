import 'package:corel_ia/core/models/message.dart';
import 'package:corel_ia/features/chat/data/mock_chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MockChatRepository repository;

  setUp(() => repository = MockChatRepository());
  tearDown(() => repository.dispose());

  test('createConversation rattache la conversation à l\'utilisateur', () async {
    final conversation =
        await repository.createConversation(userId: 'u1', title: 'Test');
    expect(conversation.userId, 'u1');

    final conversations = await repository.watchConversations('u1').first;
    expect(conversations, hasLength(1));
    expect(conversations.first.id, conversation.id);
  });

  test('addMessage persiste et expose le message', () async {
    final conversation = await repository.createConversation(userId: 'u1');
    final message = await repository.addMessage(
      conversationId: conversation.id,
      role: Role.user,
      content: 'Bonjour le monde',
    );
    expect(message.role, Role.user);

    final messages = await repository.watchMessages(conversation.id).first;
    expect(messages, hasLength(1));
    expect(messages.first.content, 'Bonjour le monde');
  });

  test('le premier message définit le titre de la conversation', () async {
    final conversation = await repository.createConversation(userId: 'u1');
    await repository.addMessage(
      conversationId: conversation.id,
      role: Role.user,
      content: 'Quelle est la capitale de la France ?',
    );
    final conversations = await repository.watchConversations('u1').first;
    expect(conversations.first.title, startsWith('Quelle est la capitale'));
  });

  test('updateMessageContent met à jour le contenu', () async {
    final conversation = await repository.createConversation(userId: 'u1');
    final message = await repository.addMessage(
      conversationId: conversation.id,
      role: Role.assistant,
      content: 'Brouillon',
    );
    await repository.updateMessageContent(
      conversation.id,
      message.id,
      'Réponse finale',
    );
    final messages = await repository.watchMessages(conversation.id).first;
    expect(messages.first.content, 'Réponse finale');
    expect(messages.first.isStreaming, isFalse);
  });

  test('deleteConversation retire la conversation et ses messages', () async {
    final conversation = await repository.createConversation(userId: 'u1');
    await repository.addMessage(
      conversationId: conversation.id,
      role: Role.user,
      content: 'Bonjour',
    );
    await repository.deleteConversation(conversation.id);

    expect(await repository.watchConversations('u1').first, isEmpty);
    expect(await repository.watchMessages(conversation.id).first, isEmpty);
  });
}
