import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../domain/conversation.dart';
import '../domain/message.dart';
import '../../../core/constants.dart';
import '../../../core/providers/firebase_providers.dart';

class FirestoreChatRepository {
  final FirebaseFirestore _db;
  const FirestoreChatRepository(this._db);

  // ── Conversations ──────────────────────────────────────────────────────────
  Stream<List<Conversation>> watchConversations(String userId) {
    return _db
        .collection(AppConstants.colConversations)
        .where('userId', isEqualTo: userId)
        .orderBy('updatedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map(Conversation.fromFirestore).toList());
  }

  Future<Conversation> createConversation({
    required String userId,
    String title = 'Nouvelle conversation',
    String? projectId,
  }) async {
    final now = DateTime.now();
    final conv = Conversation(
      id: const Uuid().v4(),
      userId: userId,
      title: title,
      projectId: projectId,
      createdAt: now,
      updatedAt: now,
    );
    await _db
        .collection(AppConstants.colConversations)
        .doc(conv.id)
        .set(conv.toFirestore());
    return conv;
  }

  Future<void> updateConversation(String convId, Map<String, dynamic> data) =>
      _db
          .collection(AppConstants.colConversations)
          .doc(convId)
          .update({...data, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> deleteConversation(String convId) async {
    // Supprimer les messages puis la conversation
    final msgs = await _db
        .collection(AppConstants.colConversations)
        .doc(convId)
        .collection(AppConstants.colMessages)
        .get();

    final batch = _db.batch();
    for (final doc in msgs.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(
      _db.collection(AppConstants.colConversations).doc(convId),
    );
    await batch.commit();
  }

  // ── Messages ───────────────────────────────────────────────────────────────
  Stream<List<Message>> watchMessages(String convId) {
    return _db
        .collection(AppConstants.colConversations)
        .doc(convId)
        .collection(AppConstants.colMessages)
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map(Message.fromFirestore).toList());
  }

  Future<Message> addMessage({
    required String conversationId,
    required Role role,
    required String content,
    String? model,
  }) async {
    final msg = Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      role: role,
      content: content,
      model: model,
      createdAt: DateTime.now(),
    );
    await _db
        .collection(AppConstants.colConversations)
        .doc(conversationId)
        .collection(AppConstants.colMessages)
        .doc(msg.id)
        .set(msg.toFirestore());

    // Mettre à jour le compteur + titre si premier message
    await updateConversation(conversationId, {
      'messageCount': FieldValue.increment(1),
      if (role == Role.user && content.length > 3)
        'title': _extractTitle(content),
    });

    return msg;
  }

  Future<void> updateMessageContent(
      String convId, String msgId, String content) =>
      _db
          .collection(AppConstants.colConversations)
          .doc(convId)
          .collection(AppConstants.colMessages)
          .doc(msgId)
          .update({'content': content, 'isStreaming': false});

  String _extractTitle(String text) {
    final t = text.replaceAll('\n', ' ').trim();
    return t.length > 60 ? '${t.substring(0, 57)}...' : t;
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────
final chatRepositoryProvider = Provider<FirestoreChatRepository>((ref) {
  return FirestoreChatRepository(ref.watch(firestoreProvider));
});
