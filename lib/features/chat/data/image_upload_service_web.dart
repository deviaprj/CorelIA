import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../domain/attachment.dart';

/// Exception specifique au service d'upload d'images.
class ImageUploadException implements Exception {
  final String message;
  const ImageUploadException(this.message);
  @override
  String toString() => 'ImageUploadException: $message';
}

/// Service d'upload d'images — implementation web via FilePicker.
/// Supporte la selection multiple avec limite agrégée de 5MB.
class ImageUploadService {
  static const int maxTotalBytes = 5 * 1024 * 1024; // 5 MB total
  static const int maxSingleBytes = 2 * 1024 * 1024; // 2 MB par image

  /// Ouvre le selecteur de fichiers pour choisir des images (web).
  Future<List<Attachment>> pickFromGallery({bool allowMultiple = true}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: allowMultiple,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return [];
      return _processFiles(result.files);
    } catch (e) {
      debugPrint('[ImageUploadService] Web error: $e');
      return [];
    }
  }

  /// Camera non disponible sur web.
  Future<List<Attachment>> pickFromCamera() async {
    debugPrint('[ImageUploadService] Camera non disponible sur web');
    return [];
  }

  Future<List<Attachment>> _processFiles(List<PlatformFile> files) async {
    final results = <Attachment>[];
    var totalSize = 0;

    for (final file in files) {
      final bytes = file.bytes;
      if (bytes == null) continue;

      if (bytes.length > maxSingleBytes) {
        debugPrint('[ImageUploadService] Image ${file.name} ignorée (${bytes.length > maxSingleBytes ? ">" : "<"} ${maxSingleBytes ~/ 1024}KB)');
        continue;
      }

      if (totalSize + bytes.length > maxTotalBytes) {
        debugPrint('[ImageUploadService] Limite 5MB atteinte');
        break;
      }

      final base64 = base64Encode(bytes);
      final mimeType = _detectMimeType(file.name);

      results.add(Attachment(
        type: AttachmentType.image,
        name: file.name,
        mimeType: mimeType,
        sizeBytes: bytes.length,
        imageBase64: base64,
      ));
      totalSize += bytes.length;
    }

    return results;
  }

  String _detectMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'image/jpeg';
  }
}