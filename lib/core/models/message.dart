import 'package:cloud_firestore/cloud_firestore.dart';

import 'attachment.dart';

export 'attachment.dart';

/// Rôle d'un message dans la conversation.
enum Role { user, assistant, system }

/// Message d'une conversation, avec pièces jointes optionnelles.
class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.model,
    this.isStreaming = false,
    this.attachments = const [],
    this.fileContext,
    this.searchSources,
  });

  final String id;
  final String conversationId;
  final Role role;
  final String content;
  final DateTime createdAt;
  final String? model;
  final bool isStreaming;

  /// Pièces jointes (images + documents dont le texte a été extrait).
  final List<Attachment> attachments;

  /// Contexte documentaire injecté dans le prompt (texte concaténé).
  final String? fileContext;

  /// Sources web citées, au format `titre|url`.
  final List<String>? searchSources;

  bool get isUser => role == Role.user;
  bool get isAssistant => role == Role.assistant;
  bool get hasImage => attachments.any((a) => a.isImage);
  bool get hasFile => attachments.any((a) => !a.isImage);
  bool get hasSearchSources => searchSources != null && searchSources!.isNotEmpty;
  int get attachmentsTotalSize =>
      attachments.fold(0, (sum, a) => sum + a.sizeBytes);

  /// Convertit le message au format API OpenAI (multimodal si image).
  Map<String, dynamic> toApiMap() {
    final imageParts =
        attachments.map((a) => a.toApiPart()).whereType<Map<String, dynamic>>().toList();

    if (imageParts.isEmpty) {
      return {'role': role.name, 'content': content};
    }

    final text = content.isNotEmpty ? content : 'Décris cette image en détail.';
    return {
      'role': role.name,
      'content': [
        {'type': 'text', 'text': text},
        ...imageParts,
      ],
    };
  }

  /// Construit le contexte documentaire à injecter dans le prompt système.
  String? buildFileContext({required bool isFull}) {
    if (attachments.isEmpty) return null;

    final buffer = StringBuffer();
    for (final att in attachments) {
      final text = att.extractedText;
      if (att.isImage || text == null || text.isEmpty) continue;
      buffer.writeln('Document : ${att.name}');
      buffer.writeln(_truncate(text, isFull: isFull));
      buffer.writeln();
    }
    return buffer.isEmpty ? null : buffer.toString().trim();
  }

  static String _truncate(String text, {required bool isFull}) {
    const freeLimit = 15000;
    const fullLimit = 30000;
    final limit = isFull ? fullLimit : freeLimit;
    if (text.length <= limit) return text;
    return '${text.substring(0, limit)}\n\n[... contenu tronqué]';
  }

  factory Message.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    final attachmentsData = data['attachments'] as List<dynamic>? ?? const [];
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
      attachments: attachmentsData
          .whereType<Map<String, dynamic>>()
          .map(Attachment.fromFirestore)
          .toList(),
      fileContext: data['fileContext'] as String?,
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
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toFirestore()).toList(),
        if (fileContext != null && fileContext!.isNotEmpty)
          'fileContext': fileContext,
        if (searchSources != null && searchSources!.isNotEmpty)
          'searchSources': searchSources,
      };

  Message copyWith({
    String? content,
    bool? isStreaming,
    List<Attachment>? attachments,
    String? fileContext,
    List<String>? searchSources,
  }) =>
      Message(
        id: id,
        conversationId: conversationId,
        role: role,
        content: content ?? this.content,
        createdAt: createdAt,
        model: model,
        isStreaming: isStreaming ?? this.isStreaming,
        attachments: attachments ?? this.attachments,
        fileContext: fileContext ?? this.fileContext,
        searchSources: searchSources ?? this.searchSources,
      );
}
