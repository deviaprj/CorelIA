import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../domain/conversation.dart';
import '../domain/message.dart';

/// Mock repository pour le chat - mode DEMO sans Firebase
/// Stocke les données en mémoire locale
class MockChatRepository {
  final _uuid = const Uuid();

  // Stockage en mémoire
  final Map<String, Conversation> _conversations = {};
  final Map<String, List<Message>> _messages = {};

  // Streams pour la réactivité
  final _conversationsController = StreamController<List<Conversation>>.broadcast();
  final _messagesController = StreamController<Map<String, List<Message>>>.broadcast();

  // ── Conversations ──────────────────────────────────────────────────────────
  Stream<List<Conversation>> watchConversations(String userId) async* {
    yield List.unmodifiable(getConversations(userId));
    yield* _conversationsController.stream
        .map((_) => List.unmodifiable(getConversations(userId)));
  }

  List<Conversation> getConversations(String userId) {
    return _conversations.values
        .where((c) => c.userId == userId)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<Conversation> createConversation({
    required String userId,
    String title = 'Nouvelle conversation',
    String? projectId,
  }) async {
    final now = DateTime.now();
    final conv = Conversation(
      id: _uuid.v4(),
      userId: userId,
      title: title,
      projectId: projectId,
      createdAt: now,
      updatedAt: now,
    );
    _conversations[conv.id] = conv;
    _messages[conv.id] = [];
    _conversationsController.add(_conversations.values.toList());
    debugPrint('[MockChat] Conversation créée: ${conv.id}');
    return conv;
  }

  Future<void> updateConversation(String convId, Map<String, dynamic> data) async {
    if (_conversations.containsKey(convId)) {
      final conv = _conversations[convId]!;
      final updated = conv.copyWith(
        title: data['title'] as String? ?? conv.title,
        projectId: data['projectId'] as String? ?? conv.projectId,
        updatedAt: DateTime.now(),
      );
      _conversations[convId] = updated;
      _conversationsController.add(_conversations.values.toList());
      debugPrint('[MockChat] Conversation mise à jour: $convId');
    }
  }

  Future<void> deleteConversation(String convId) async {
    _conversations.remove(convId);
    _messages.remove(convId);
    _conversationsController.add(_conversations.values.toList());
    debugPrint('[MockChat] Conversation supprimée: $convId');
  }

  // ── Messages ───────────────────────────────────────────────────────────────
  Stream<List<Message>> watchMessages(String convId) async* {
    yield List.unmodifiable(_messages[convId] ?? []);
    yield* _messagesController.stream
        .where((_) => _messages.containsKey(convId))
        .map((_) => List.unmodifiable(_messages[convId] ?? []));
  }

  /// Charge les messages plus anciens que [before] (mock = tous les messages).
  Future<List<Message>> loadOlderMessages(
    String convId,
    DateTime before, {
    int limit = 20,
  }) async {
    final all = _messages[convId] ?? [];
    final older = all
        .where((m) => m.createdAt.isBefore(before))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (older.length > limit) {
      return older.sublist(older.length - limit);
    }
    return older;
  }

  Future<Message> addMessage({
    required String conversationId,
    required Role role,
    required String content,
    String? model,
    String? imageBase64,
    String? imageMimeType,
    String? fileName,
    List<String>? searchSources,
  }) async {
    final msg = Message(
      id: _uuid.v4(),
      conversationId: conversationId,
      role: role,
      content: content,
      model: model,
      createdAt: DateTime.now(),
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      fileName: fileName,
      searchSources: searchSources,
    );

    if (!_messages.containsKey(conversationId)) {
      _messages[conversationId] = [];
    }
    _messages[conversationId]!.add(msg);
    _messagesController.add(_messages);

    // Mettre à jour le compteur + titre
    await updateConversation(conversationId, {
      'messageCount': (_messages[conversationId]!.length),
      if (role == Role.user && content.length > 3)
        'title': _extractTitle(content),
    });

    debugPrint('[MockChat] Message ajouté: ${msg.id}');
    return msg;
  }

  Future<void> updateMessageContent(
      String convId, String msgId, String content) async {
    if (_messages.containsKey(convId)) {
      final msgs = _messages[convId]!;
      final idx = msgs.indexWhere((m) => m.id == msgId);
      if (idx != -1) {
        msgs[idx] = msgs[idx].copyWith(content: content, isStreaming: false);
        _messagesController.add(_messages);
        debugPrint('[MockChat] Message mis à jour: $msgId');
      }
    }
  }

  // Créer un message placeholder pour le streaming
  Future<String> createStreamingMessage(String conversationId) async {
    final msgId = _uuid.v4();
    final msg = Message(
      id: msgId,
      conversationId: conversationId,
      role: Role.assistant,
      content: '',
      isStreaming: true,
      createdAt: DateTime.now(),
    );

    if (!_messages.containsKey(conversationId)) {
      _messages[conversationId] = [];
    }
    _messages[conversationId]!.add(msg);
    _messagesController.add(_messages);
    return msgId;
  }

  String _extractTitle(String text) {
    final t = text.replaceAll('\n', ' ').trim();
    return t.length > 60 ? '${t.substring(0, 57)}...' : t;
  }

  void dispose() {
    _conversationsController.close();
    _messagesController.close();
  }
}

// Instance globale pour le mode DEMO
final mockChatRepository = MockChatRepository();
