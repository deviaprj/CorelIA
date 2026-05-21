import 'dart:typed_data';

/// Types d'attachment supportes.
enum AttachmentType {
  image,
  pdf,
  document,
  spreadsheet,
  presentation,
  text,
}

/// Piece jointe dans un message de conversation.
class Attachment {
  final AttachmentType type;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final String? imageBase64;
  final String? extractedText;
  final Uint8List? rawBytes;

  const Attachment({
    required this.type,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    this.imageBase64,
    this.extractedText,
    this.rawBytes,
  });

  bool get isImage => type == AttachmentType.image;
  bool get isDocument => type == AttachmentType.document;
  bool get isSpreadsheet => type == AttachmentType.spreadsheet;
  bool get isPresentation => type == AttachmentType.presentation;
  bool get isPdf => type == AttachmentType.pdf;
  bool get isText => type == AttachmentType.text;

  static AttachmentType detectType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp')) {
      return AttachmentType.image;
    }
    if (lower.endsWith('.pdf')) return AttachmentType.pdf;
    if (lower.endsWith('.docx')) return AttachmentType.document;
    if (lower.endsWith('.xlsx')) return AttachmentType.spreadsheet;
    if (lower.endsWith('.pptx')) return AttachmentType.presentation;
    if (lower.endsWith('.txt') ||
        lower.endsWith('.csv') ||
        lower.endsWith('.md')) {
      return AttachmentType.text;
    }
    return AttachmentType.text;
  }

  Map<String, dynamic> toFirestore() => {
    'type': type.name,
    'name': name,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    if (imageBase64 != null && imageBase64!.length < 900000)
      'imageBase64': imageBase64,
    if (extractedText != null) 'extractedText': extractedText,
  };

  factory Attachment.fromFirestore(Map<String, dynamic> data) {
    return Attachment(
      type: AttachmentType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => AttachmentType.text,
      ),
      name: data['name'] as String? ?? 'fichier',
      mimeType: data['mimeType'] as String? ?? 'application/octet-stream',
      sizeBytes: data['sizeBytes'] as int? ?? 0,
      imageBase64: data['imageBase64'] as String?,
      extractedText: data['extractedText'] as String?,
    );
  }

  Map<String, dynamic>? toApiPart() {
    if (isImage && imageBase64 != null && imageBase64!.isNotEmpty) {
      return {
        'type': 'image_url',
        'image_url': {
          'url': 'data:\$mimeType;base64,\$imageBase64',
        },
      };
    }
    return null;
  }

  Attachment copyWith({
    AttachmentType? type,
    String? name,
    String? mimeType,
    int? sizeBytes,
    String? imageBase64,
    String? extractedText,
    Uint8List? rawBytes,
  }) =>
      Attachment(
        type: type ?? this.type,
        name: name ?? this.name,
        mimeType: mimeType ?? this.mimeType,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        imageBase64: imageBase64 ?? this.imageBase64,
        extractedText: extractedText ?? this.extractedText,
        rawBytes: rawBytes ?? this.rawBytes,
      );
}
