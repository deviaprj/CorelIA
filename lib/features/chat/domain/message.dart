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
  // Support images
  final String? imageUrl;
  final String? imageMimeType;
  final String? imageBase64;
  // Support fichiers
  final String? fileName;
  final List<String>? searchSources;

  const Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.model,
    this.isStreaming = false,
    required this.createdAt,
    this.imageUrl,
    this.imageMimeType,
    this.imageBase64,
    this.fileName,
    this.searchSources,
  });

  /// Convertit en format API compatible DeepSeek.
  ///
  /// DeepSeek-V3 accepte le format texte simple ou le format multimodal avec images en base64.
  /// Format supporté : {"role": "user", "content": [{"type": "image_url", "image_url": {"url": "..."}}]}
  Map<String, dynamic> toApiMap() {
    if (imageBase64 != null && imageBase64!.isNotEmpty) {
      final mime = imageMimeType ?? 'image/jpeg';
      final parts = <Map<String, dynamic>>[];

      // Texte d'abord (meilleure compatibilite avec les API vision)
      if (content.isNotEmpty && content.length < 500) {
        parts.add({'type': 'text', 'text': content});
      } else if (content.isNotEmpty) {
        parts.add({'type': 'text', 'text': 'Image jointe. $content'});
      }

      parts.add({
        'type': 'image_url',
        'image_url': {
          'url': 'data:$mime;base64,$imageBase64',
        },
      });

      return {
        'role': role.name,
        'content': parts,
      };
    }
    // Format texte simple
    return {
      'role': role.name,
      'content': content,
    };
  }

  /// Convertit en format texte seul (pour DeepSeek sans support d'images).
  /// Utile si l'API refuse le format multimodal.
  Map<String, dynamic> toApiMapTextOnly() {
    return {
      'role': role.name,
      'content': content,
    };
  }

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
      imageUrl: data['imageUrl'] as String?,
      imageMimeType: data['imageMimeType'] as String?,
      imageBase64: data['imageBase64'] as String?,
      fileName: data['fileName'] as String?,
      searchSources: (data['searchSources'] as List<dynamic>?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'conversationId': conversationId,
    'role': role.name,
    'content': content,
    'model': model,
    'isStreaming': isStreaming,
    'createdAt': Timestamp.fromDate(createdAt),
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (imageMimeType != null) 'imageMimeType': imageMimeType,
    if (fileName != null) 'fileName': fileName,
    if (searchSources != null && searchSources!.isNotEmpty)
      'searchSources': searchSources,
    // Ne pas stocker imageBase64 dans Firestore (trop gros)
    // L'image doit etre uploadee vers Firebase Storage et stockee via imageUrl
  };

  Message copyWith({
    String? content,
    bool? isStreaming,
    List<String>? searchSources,
  }) =>
      Message(
        id: id,
        conversationId: conversationId,
        role: role,
        content: content ?? this.content,
        model: model,
        isStreaming: isStreaming ?? this.isStreaming,
        createdAt: createdAt,
        imageUrl: imageUrl,
        imageMimeType: imageMimeType,
        imageBase64: imageBase64,
        fileName: fileName,
        searchSources: searchSources ?? this.searchSources,
      );

  /// Returns true if this message is from a user
  bool get isUser => role == Role.user;

  /// Returns true if this message is from the assistant
  bool get isAssistant => role == Role.assistant;

  /// Returns true if this message contains an image
  bool get hasImage => imageUrl != null || imageBase64 != null;

  /// Returns true if this message contains a file
  bool get hasFile => fileName != null && fileName!.isNotEmpty;

  /// Returns true if this message has search sources attached
  bool get hasSearchSources => searchSources != null && searchSources!.isNotEmpty;
}
