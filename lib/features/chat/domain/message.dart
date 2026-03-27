import 'package:cloud_firestore/cloud_firestore.dart';

enum Role { user, assistant, system }

class Message {
  final String id;
  final String conversationId;
  final Role role;
  final String content;
  final String? model;
  final bool isStreaming;
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.model,
    this.isStreaming = false,
    required this.createdAt,
  });

  Map<String, dynamic> toApiMap() => {
        'role': role.name,
        'content': content,
      };

  factory Message.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return Message(
      id: doc.id,
      conversationId: data['conversationId'] as String? ?? '',
      role: Role.values.firstWhere(
        (r) => r.name == data['role'],
        orElse: () => Role.user,
      ),
      content: data['content'] as String? ?? '',
      model: data['model'] as String?,
      isStreaming: data['isStreaming'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'conversationId': conversationId,
        'role': role.name,
        'content': content,
        'model': model,
        'isStreaming': isStreaming,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  Message copyWith({String? content, bool? isStreaming}) => Message(
        id: id,
        conversationId: conversationId,
        role: role,
        content: content ?? this.content,
        model: model,
        isStreaming: isStreaming ?? this.isStreaming,
        createdAt: createdAt,
      );

  /// Returns true if this message is from a user
  bool get isUser => role == Role.user;

  /// Returns true if this message is from the assistant
  bool get isAssistant => role == Role.assistant;
}
