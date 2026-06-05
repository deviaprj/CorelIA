/// Modèle de requête chat envoyé au backend.
class ChatRequest {
  final String conversationId;
  final List<ChatMessage> messages;
  final String? systemPrompt;
  final String? model;
  final bool useSearch;
  final int maxTokens;

  const ChatRequest({
    required this.conversationId,
    required this.messages,
    this.systemPrompt,
    this.model,
    this.useSearch = false,
    this.maxTokens = 4096,
  });

  Map<String, dynamic> toJson() => {
    'conversationId': conversationId,
    'messages': messages.map((m) => m.toJson()).toList(),
    if (systemPrompt != null) 'systemPrompt': systemPrompt,
    if (model != null) 'model': model,
    'useSearch': useSearch,
    'maxTokens': maxTokens,
  };
}

class ChatMessage {
  final String role;
  final String content;
  final String? name;

  const ChatMessage({
    required this.role,
    required this.content,
    this.name,
  });

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    if (name != null) 'name': name,
  };

  static ChatMessage fromDomain(dynamic m) => ChatMessage(
        role: m.role == 'user' ? 'user' : 'assistant',
        content: m.content as String,
      );
}
