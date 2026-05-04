import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

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

/// Service d'upload et compression d'images — 100% autonome cote client.
class ImageUploadService {
  final ImagePicker _picker = ImagePicker();

  /// Ouvre la galerie pour selectionner une image.
  Future<ImageUploadResult?> pickFromGallery() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null) return null;
    return _processImage(File(picked.path));
  }

  /// Ouvre la camera pour prendre une photo.
  Future<ImageUploadResult?> pickFromCamera() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null) return null;
    return _processImage(File(picked.path));
  }

  /// Compresse et convertit une image en base64.
  Future<ImageUploadResult?> _processImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final originalSize = bytes.length;

      // Compression supplementaire si necessaire
      var compressedBytes = bytes;
      if (originalSize > 5 * 1024 * 1024) {
        // > 5MB : compresser davantage pour DeepSeek (limite recommandee)
        final result = await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          minWidth: 1024,
          minHeight: 1024,
          quality: 60,
          format: CompressFormat.jpeg,
        );
        if (result != null) {
          compressedBytes = result;
        }
      } else if (originalSize > 2 * 1024 * 1024) {
        // 2-5MB : compresser modérément
        final result = await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          minWidth: 1280,
          minHeight: 1280,
          quality: 70,
          format: CompressFormat.jpeg,
        );
        if (result != null) {
          compressedBytes = result;
        }
      }

      // Limite : 1MB max pour eviter les payloads API trop volumineux
      if (compressedBytes.length > 1 * 1024 * 1024) {
        throw const ImageUploadException('Image trop volumineuse (max 1MB)');
      }

      final base64 = base64Encode(compressedBytes);
      // Securite supplementaire : verifier la taille du base64
      if (base64.length > 1.5 * 1024 * 1024) {
        throw const ImageUploadException('Image encodee trop volumineuse (max 1MB base64)');
      }
      final mimeType = _detectMimeType(file.path);

      return ImageUploadResult(
        base64: base64,
        mimeType: mimeType,
        localPath: file.path,
        width: 0, // On pourrait utiliser image package pour obtenir les dimensions
        height: 0,
        sizeBytes: compressedBytes.length,
      );
    } catch (e) {
      debugPrint('[ImageUploadService] Erreur traitement image : $e');
      return null;
    }
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
