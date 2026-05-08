import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Exception specifique au service d'upload d'images.
class ImageUploadException implements Exception {
  final String message;
  const ImageUploadException(this.message);
  @override
  String toString() => 'ImageUploadException: $message';
}

/// Resultat d'un upload d'image.
class ImageUploadResult {
  final String base64;
  final String mimeType;
  final String? localPath;
  final int width;
  final int height;
  final int sizeBytes;

  const ImageUploadResult({
    required this.base64,
    required this.mimeType,
    this.localPath,
    required this.width,
    required this.height,
    required this.sizeBytes,
  });
}

/// Service d'upload d'images — implementation web via FilePicker.
/// Sur web/extension, pas de camera, mais la galerie/fichier fonctionne.
class ImageUploadService {
  /// Ouvre le selecteur de fichiers pour choisir une image (web).
  Future<ImageUploadResult?> pickFromGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return null;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const ImageUploadException('Impossible de lire l\'image');
      }

      // Limite 1MB pour DeepSeek
      if (bytes.length > 1 * 1024 * 1024) {
        throw const ImageUploadException('Image trop volumineuse (max 1MB)');
      }

      final base64 = base64Encode(bytes);
      final mimeType = _detectMimeType(file.name);

      return ImageUploadResult(
        base64: base64,
        mimeType: mimeType,
        width: 0,
        height: 0,
        sizeBytes: bytes.length,
      );
    } catch (e) {
      if (e is ImageUploadException) rethrow;
      debugPrint('[ImageUploadService] Web error: $e');
      return null;
    }
  }

  /// Camera non disponible sur web.
  Future<ImageUploadResult?> pickFromCamera() async {
    debugPrint('[ImageUploadService] Camera non disponible sur web');
    return null;
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