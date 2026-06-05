/// Evenement de feedback utilisateur (explicite ou implicite).
class FeedbackEvent {
  final String id;
  final String type; // 'thumbs_up', 'thumbs_down', 'barge_in', 'correction', 'retry', 'link_opened', 'slash_reused'
  final String? messageId;
  final String? conversationId;
  final String? content;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const FeedbackEvent({
    required this.id,
    required this.type,
    this.messageId,
    this.conversationId,
    this.content,
    this.metadata,
    required this.createdAt,
  });

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'type': type,
    if (messageId != null) 'messageId': messageId,
    if (conversationId != null) 'conversationId': conversationId,
    if (content != null) 'content': content,
    if (metadata != null) 'metadata': metadata,
    'createdAt': createdAt.toIso8601String(),
  };

  factory FeedbackEvent.fromFirestore(Map<String, dynamic> data) => FeedbackEvent(
    id: data['id'] as String,
    type: data['type'] as String,
    messageId: data['messageId'] as String?,
    conversationId: data['conversationId'] as String?,
    content: data['content'] as String?,
    metadata: data['metadata'] as Map<String, dynamic>?,
    createdAt: DateTime.parse(data['createdAt'] as String),
  );
}
