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

/// Service d'upload d'images — stub web (pas de File/camera natifs).
/// Sur web, l'upload d'images passe par le HTML file picker directement.
class ImageUploadService {
  Future<ImageUploadResult?> pickFromGallery() async {
    debugPrint('[ImageUploadService] Web stub: pickFromGallery non disponible');
    return null;
  }

  Future<ImageUploadResult?> pickFromCamera() async {
    debugPrint('[ImageUploadService] Web stub: pickFromCamera non disponible');
    return null;
  }
}