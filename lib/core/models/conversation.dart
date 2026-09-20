import 'package:cloud_firestore/cloud_firestore.dart';

/// Conversation de chat (un fil de messages).
class Conversation {
  const Conversation({
    required this.id,
    required this.userId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.modelUsed,
    this.messageCount = 0,
  });

  final String id;
  final String userId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? modelUsed;
  final int messageCount;

  factory Conversation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return Conversation(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      title: data['title'] as String? ?? 'Nouvelle conversation',
      modelUsed: data['modelUsed'] as String?,
      messageCount: data['messageCount'] as int? ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'title': title,
        'modelUsed': modelUsed,
        'messageCount': messageCount,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  Conversation copyWith({
    String? title,
    String? modelUsed,
    int? messageCount,
    DateTime? updatedAt,
  }) =>
      Conversation(
        id: id,
        userId: userId,
        title: title ?? this.title,
        modelUsed: modelUsed ?? this.modelUsed,
        messageCount: messageCount ?? this.messageCount,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
