import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/message.dart';
import '../../../core/providers/firebase_providers.dart';
import 'mock_chat_repository.dart';

/// Persistance des conversations et messages.
///
/// Utilise Firestore en production et le repository mémoire en mode démo
/// (ou lorsque Firestore est indisponible).
class ChatRepository {
  const ChatRepository(this._db);

  /// `null` en mode démo : toutes les opérations déléguent au mock.
  final FirebaseFirestore? _db;

  // ── Conversations ──────────────────────────────────────────────────────────
  Stream<List<Conversation>> watchConversations(String userId) {
    final db = _db;
    if (db == null) return mockChatRepository.watchConversations(userId);
    return db
        .collection(AppConfig.colConversations)
        .where('userId', isEqualTo: userId)
        .orderBy('updatedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map(Conversation.fromFirestore).toList());
  }

  Future<Conversation> createConversation({
    required String userId,
    String title = 'Nouvelle conversation',
  }) async {
    final db = _db;
    if (db == null) {
      return mockChatRepository.createConversation(userId: userId, title: title);
    }
    final now = DateTime.now();
    final conv = Conversation(
      id: const Uuid().v4(),
      userId: userId,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    await db
        .collection(AppConfig.colConversations)
        .doc(conv.id)
        .set(conv.toFirestore());
    return conv;
  }

  Future<void> updateConversation(String convId, Map<String, dynamic> data) {
    final db = _db;
    if (db == null) return mockChatRepository.updateConversation(convId, data);
    return db.collection(AppConfig.colConversations).doc(convId).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteConversation(String convId) async {
    final db = _db;
    if (db == null) return mockChatRepository.deleteConversation(convId);
    final messages = await db
        .collection(AppConfig.colConversations)
        .doc(convId)
        .collection(AppConfig.colMessages)
        .get();
    final batch = db.batch();
    for (final doc in messages.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(db.collection(AppConfig.colConversations).doc(convId));
    await batch.commit();
  }

  // ── Messages ───────────────────────────────────────────────────────────────
  Stream<List<Message>> watchMessages(String convId) {
    final db = _db;
    if (db == null) return mockChatRepository.watchMessages(convId);
    return db
        .collection(AppConfig.colConversations)
        .doc(convId)
        .collection(AppConfig.colMessages)
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map(Message.fromFirestore).toList());
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
    final db = _db;
    final resolvedAttachments = attachments ?? const <Attachment>[];
    if (db == null) {
      return mockChatRepository.addMessage(
        conversationId: conversationId,
        role: role,
        content: content,
        model: model,
        attachments: resolvedAttachments,
        fileContext: fileContext,
        searchSources: searchSources,
      );
    }

    final msg = Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      role: role,
      content: content,
      model: model,
      createdAt: DateTime.now(),
      attachments: resolvedAttachments,
      fileContext: fileContext,
      searchSources: searchSources,
    );
    await db
        .collection(AppConfig.colConversations)
        .doc(conversationId)
        .collection(AppConfig.colMessages)
        .doc(msg.id)
        .set(msg.toFirestore());

    await updateConversation(conversationId, {
      'messageCount': FieldValue.increment(1),
      if (role == Role.user && content.length > 3) 'title': _extractTitle(content),
    });

    return msg;
  }

  Future<void> updateMessageContent(String convId, String msgId, String content) {
    final db = _db;
    if (db == null) {
      return mockChatRepository.updateMessageContent(convId, msgId, content);
    }
    return db
        .collection(AppConfig.colConversations)
        .doc(convId)
        .collection(AppConfig.colMessages)
        .doc(msgId)
        .update({'content': content, 'isStreaming': false});
  }

  static String _extractTitle(String text) {
    final t = text.replaceAll('\n', ' ').trim();
    return t.length > 60 ? '${t.substring(0, 57)}...' : t;
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  if (isDemoMode) return const ChatRepository(null);
  return ChatRepository(ref.watch(firestoreProvider));
});
