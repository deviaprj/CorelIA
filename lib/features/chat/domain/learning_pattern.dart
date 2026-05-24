/// Pattern d'apprentissage pour ameliorer les reponses futures.
class LearningPattern {
  final String id;
  final String type; // 'slash_success', 'search_success', 'doc_analysis', 'tts_prosody'
  final String? intent; // ex: 'flights', 'hotels', 'summarize'
  final String? query;
  final String? response;
  final double? successScore; // 0.0-1.0
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const LearningPattern({
    required this.id,
    required this.type,
    this.intent,
    this.query,
    this.response,
    this.successScore,
    this.metadata,
    required this.createdAt,
  });

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'type': type,
    if (intent != null) 'intent': intent,
    if (query != null) 'query': query,
    if (response != null) 'response': response,
    if (successScore != null) 'successScore': successScore,
    if (metadata != null) 'metadata': metadata,
    'createdAt': createdAt.toIso8601String(),
  };

  factory LearningPattern.fromFirestore(Map<String, dynamic> data) => LearningPattern(
    id: data['id'] as String,
    type: data['type'] as String,
    intent: data['intent'] as String?,
    query: data['query'] as String?,
    response: data['response'] as String?,
    successScore: (data['successScore'] as num?)?.toDouble(),
    metadata: data['metadata'] as Map<String, dynamic>?,
    createdAt: DateTime.parse(data['createdAt'] as String),
  );
}
