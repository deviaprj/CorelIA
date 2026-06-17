import 'package:cloud_firestore/cloud_firestore.dart';
import 'attachment.dart';

export 'attachment.dart';

enum Role { user, assistant, system }

/// Limite totale par message : 5 MB (en octets).
const int maxAttachmentsTotalBytes = 5 * 1024 * 1024;

/// Limite totale par message en tier Pro : 50 MB (en octets).
const int proMaxAttachmentsTotalBytes = 50 * 1024 * 1024;

/// Limite d'upload agrégée selon le tier : 50 MB Pro, 5 MB gratuit.
int attachmentLimitFor({required bool isPro}) =>
    isPro ? proMaxAttachmentsTotalBytes : maxAttachmentsTotalBytes;

class Message {
  final String id;
  final String conversationId;
  final Role role;
  final String content;
  final String? model;
  final bool isStreaming;
  final DateTime createdAt;

  /// Pieces jointes multiples (images + fichiers).
  /// Remplace les anciens champs imageBase64 / fileName / fileContent.
  final List<Attachment> attachments;

  /// Contexte de fichier injecte dans le prompt IA (texte concatene des pieces jointes).
  final String? fileContext;

  final List<String>? searchSources;

  // --- Champs legacy (retrocompatibilite Firestore) ---
  final String? imageUrl;
  final String? imageMimeType;
  final String? imageBase64;
  final String? fileName;
  final String? fileContent;

  const Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.model,
    this.isStreaming = false,
    required this.createdAt,
    this.attachments = const [],
    this.fileContext,
    this.searchSources,
    // Legacy
    this.imageUrl,
    this.imageMimeType,
    this.imageBase64,
    this.fileName,
    this.fileContent,
  });

  /// Taille totale des pieces jointes en octets.
  int get attachmentsTotalSize =>
      attachments.fold(0, (sum, a) => sum + a.sizeBytes);

  /// True si le message contient au moins une image.
  bool get hasImage =>
      attachments.any((a) => a.isImage) ||
      (imageBase64 != null && imageBase64!.isNotEmpty);

  /// True si le message contient au moins un fichier texte/doc.
  bool get hasFile =>
      attachments.any((a) => !a.isImage) ||
      (fileContent != null && fileContent!.isNotEmpty);

  /// True si le message a des sources de recherche.
  bool get hasSearchSources => searchSources != null && searchSources!.isNotEmpty;

  /// True si le message depasse la limite de 5MB.
  bool get exceedsAttachmentLimit => attachmentsTotalSize > maxAttachmentsTotalBytes;

  /// Retourne les images sous forme de liste de parts API.
  List<Map<String, dynamic>> _imageParts() {
    final parts = <Map<String, dynamic>>[];
    for (final att in attachments.where((a) => a.isImage)) {
      if (att.imageBase64 != null && att.imageBase64!.isNotEmpty) {
        parts.add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:${att.mimeType};base64,${att.imageBase64}',
          },
        });
      }
    }
    // Legacy fallback
    if (parts.isEmpty && imageBase64 != null && imageBase64!.isNotEmpty) {
      final mime = imageMimeType ?? 'image/jpeg';
      parts.add({
        'type': 'image_url',
        'image_url': {'url': 'data:$mime;base64,$imageBase64'},
      });
    }
    return parts;
  }

  /// Convertit en format API compatible (OpenAI multimodal).
  Map<String, dynamic> toApiMap() {
    final imageParts = _imageParts();
    final hasImages = imageParts.isNotEmpty;

    if (hasImages) {
      final parts = <Map<String, dynamic>>[];
      // Texte — toujours present, meme minimal, pour eviter les rejets API
      final textToSend = content.isNotEmpty
          ? (content.length < 500 ? content : 'Image jointe. $content')
          : 'Décris cette image en détail.';
      parts.add({'type': 'text', 'text': textToSend});
      // Images
      parts.addAll(imageParts);
      return {'role': role.name, 'content': parts};
    }

    // Format texte simple (fichiers texte sont injectes via fileContext dans l'historique)
    return {'role': role.name, 'content': content};
  }

  /// Format texte seul (fallback si l'API refuse le multimodal).
  Map<String, dynamic> toApiMapTextOnly() {
    return {'role': role.name, 'content': content};
  }

  /// Construit le contexte fichier a injecter dans le prompt systeme.
  String? buildFileContext({required bool isPro}) {
    if (attachments.isEmpty && fileContent == null) return null;

    final buffer = StringBuffer();
    for (final att in attachments.where((a) => !a.isImage && a.extractedText != null)) {
      final label = att.name;
      final truncated = _truncate(att.extractedText!, isPro: isPro);
      buffer.writeln('Document: $label');
      buffer.writeln(truncated);
      buffer.writeln();
    }
    // Legacy
    if (buffer.isEmpty && fileContent != null && fileContent!.isNotEmpty) {
      buffer.writeln(_truncate(fileContent!, isPro: isPro));
    }
    return buffer.isNotEmpty ? buffer.toString().trim() : null;
  }

  static String _truncate(String text, {required bool isPro}) {
    const maxCharsFree = 15000;
    const maxCharsPro = 30000;
    final maxChars = isPro ? maxCharsPro : maxCharsFree;
    if (text.length <= maxChars) return text;
    final paragraphBreak = text.lastIndexOf('\n\n', maxChars);
    if (paragraphBreak > maxChars * 0.5) {
      return '${text.substring(0, paragraphBreak)}\n\n[... contenu tronque]';
    }
    return '${text.substring(0, maxChars)}... [tronque]';
  }

  factory Message.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;

    // Nouveau format : liste d'attachments
    final attachmentsData = data['attachments'] as List<dynamic>?;
    List<Attachment> attachments = [];
    if (attachmentsData != null) {
      attachments = attachmentsData
          .whereType<Map<String, dynamic>>()
          .map(Attachment.fromFirestore)
          .toList();
    }

    // Legacy fallback
    final imageBase64 = data['imageBase64'] as String?;
    final imageMimeType = data['imageMimeType'] as String?;
    final fileName = data['fileName'] as String?;
    final fileContent = data['fileContent'] as String?;

    if (attachments.isEmpty) {
      if (imageBase64 != null && imageBase64.isNotEmpty) {
        attachments.add(Attachment(
          type: AttachmentType.image,
          name: fileName ?? 'image.jpg',
          mimeType: imageMimeType ?? 'image/jpeg',
          sizeBytes: imageBase64.length,
          imageBase64: imageBase64,
        ));
      }
      if (fileContent != null && fileContent.isNotEmpty) {
        attachments.add(Attachment(
          type: Attachment.detectType(fileName ?? 'document.txt'),
          name: fileName ?? 'document.txt',
          mimeType: 'application/octet-stream',
          sizeBytes: fileContent.length,
          extractedText: fileContent,
        ));
      }
    }

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
      attachments: attachments,
      fileContext: data['fileContext'] as String?,
      searchSources: (data['searchSources'] as List<dynamic>?)?.cast<String>(),
      // Legacy
      imageUrl: data['imageUrl'] as String?,
      imageMimeType: imageMimeType,
      imageBase64: imageBase64,
      fileName: fileName,
      fileContent: fileContent,
    );
  }

  Map<String, dynamic> toFirestore() {
    final result = <String, dynamic>{
      'conversationId': conversationId,
      'role': role.name,
      'content': content,
      'model': model,
      'isStreaming': isStreaming,
      'createdAt': Timestamp.fromDate(createdAt),
    };

    // Nouveau format
    if (attachments.isNotEmpty) {
      result['attachments'] = attachments.map((a) => a.toFirestore()).toList();
    }

    if (fileContext != null && fileContext!.isNotEmpty) {
      result['fileContext'] = fileContext;
    }

    if (searchSources != null && searchSources!.isNotEmpty) {
      result['searchSources'] = searchSources;
    }

    // Legacy (pour compatibilite si jamais besoin de downgrade)
    if (imageUrl != null) result['imageUrl'] = imageUrl;
    if (imageMimeType != null) result['imageMimeType'] = imageMimeType;
    if (fileName != null) result['fileName'] = fileName;

    return result;
  }

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
        model: model,
        isStreaming: isStreaming ?? this.isStreaming,
        createdAt: createdAt,
        attachments: attachments ?? this.attachments,
        fileContext: fileContext ?? this.fileContext,
        searchSources: searchSources ?? this.searchSources,
        imageUrl: imageUrl,
        imageMimeType: imageMimeType,
        imageBase64: imageBase64,
        fileName: fileName,
        fileContent: fileContent,
      );

  bool get isUser => role == Role.user;
  bool get isAssistant => role == Role.assistant;
}
