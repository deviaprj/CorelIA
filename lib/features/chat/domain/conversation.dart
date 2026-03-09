import 'package:cloud_firestore/cloud_firestore.dart';

class Conversation {
  final String id;
  final String userId;
  final String title;
  final String? modelUsed;
  final int messageCount;
  final String? projectId;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Conversation({
    required this.id,
    required this.userId,
    required this.title,
    this.modelUsed,
    this.messageCount = 0,
    this.projectId,
    this.isPinned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Conversation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return Conversation(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      title: data['title'] as String? ?? 'Nouvelle conversation',
      modelUsed: data['modelUsed'] as String?,
      messageCount: data['messageCount'] as int? ?? 0,
      projectId: data['projectId'] as String?,
      isPinned: data['isPinned'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'title': title,
        'modelUsed': modelUsed,
        'messageCount': messageCount,
        'projectId': projectId,
        'isPinned': isPinned,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  Conversation copyWith({
    String? title,
    int? messageCount,
    String? modelUsed,
    bool? isPinned,
    DateTime? updatedAt,
  }) =>
      Conversation(
        id: id,
        userId: userId,
        title: title ?? this.title,
        modelUsed: modelUsed ?? this.modelUsed,
        messageCount: messageCount ?? this.messageCount,
        projectId: projectId,
        isPinned: isPinned ?? this.isPinned,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
