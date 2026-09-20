import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/attachment.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/message.dart';

/// Repository de chat en mémoire — mode démo sans Firebase et tests.
class MockChatRepository {
  final _uuid = const Uuid();

  final Map<String, Conversation> _conversations = {};
  final Map<String, List<Message>> _messages = {};

  final _conversationsController =
      StreamController<List<Conversation>>.broadcast();
  final _messagesController =
      StreamController<Map<String, List<Message>>>.broadcast();

  // ── Conversations ──────────────────────────────────────────────────────────
  Stream<List<Conversation>> watchConversations(String userId) async* {
    yield List.unmodifiable(getConversations(userId));
    yield* _conversationsController.stream
        .map((_) => List.unmodifiable(getConversations(userId)));
  }

  List<Conversation> getConversations(String userId) =>
      _conversations.values.where((c) => c.userId == userId).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<Conversation> createConversation({
    required String userId,
    String title = 'Nouvelle conversation',
  }) async {
    final now = DateTime.now();
    final conv = Conversation(
      id: _uuid.v4(),
      userId: userId,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    _conversations[conv.id] = conv;
    _messages[conv.id] = [];
    _conversationsController.add(_conversations.values.toList());
    return conv;
  }

  Future<void> updateConversation(String convId, Map<String, dynamic> data) async {
    final conv = _conversations[convId];
    if (conv == null) return;
    _conversations[convId] = conv.copyWith(
      title: data['title'] as String? ?? conv.title,
      updatedAt: DateTime.now(),
    );
    _conversationsController.add(_conversations.values.toList());
  }

  Future<void> deleteConversation(String convId) async {
    _conversations.remove(convId);
    _messages.remove(convId);
    _conversationsController.add(_conversations.values.toList());
  }

  // ── Messages ───────────────────────────────────────────────────────────────
  Stream<List<Message>> watchMessages(String convId) async* {
    yield List.unmodifiable(_messages[convId] ?? const <Message>[]);
    yield* _messagesController.stream
        .where((_) => _messages.containsKey(convId))
        .map((_) => List.unmodifiable(_messages[convId] ?? const <Message>[]));
  }

  Future<Message> addMessage({
    required String conversationId,
    required Role role,
    required String content,
    String? model,
    List<Attachment>? attachments,
    String? fileContext,
    List<String>? searchSources,
  }) async {
    final msg = Message(
      id: _uuid.v4(),
      conversationId: conversationId,
      role: role,
      content: content,
      model: model,
      createdAt: DateTime.now(),
      attachments: attachments ?? const [],
      fileContext: fileContext,
      searchSources: searchSources,
    );

    final messages = _messages.putIfAbsent(conversationId, () => []);
    messages.add(msg);
    _messagesController.add(_messages);

    await updateConversation(conversationId, {
      'messageCount': messages.length,
      if (role == Role.user && content.length > 3) 'title': _extractTitle(content),
    });

    debugPrint('[MockChat] Message ajouté: ${msg.id}');
    return msg;
  }

  Future<void> updateMessageContent(
    String convId,
    String msgId,
    String content,
  ) async {
    final messages = _messages[convId];
    if (messages == null) return;
    final idx = messages.indexWhere((m) => m.id == msgId);
    if (idx == -1) return;
    messages[idx] = messages[idx].copyWith(content: content, isStreaming: false);
    _messagesController.add(_messages);
  }

  static String _extractTitle(String text) {
    final t = text.replaceAll('\n', ' ').trim();
    return t.length > 60 ? '${t.substring(0, 57)}...' : t;
  }

  void dispose() {
    _conversationsController.close();
    _messagesController.close();
  }
}

final mockChatRepository = MockChatRepository();
