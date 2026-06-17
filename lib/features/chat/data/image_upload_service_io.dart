import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import '../domain/attachment.dart';

/// Exception specifique au service d'upload d'images.
class ImageUploadException implements Exception {
  final String message;
  const ImageUploadException(this.message);
  @override
  String toString() => 'ImageUploadException: $message';
}

/// Service d'upload et compression d'images — 100% autonome cote client.
///
/// Supporte la selection multiple avec limite agrégée de 5MB.
class ImageUploadService {
  static const int maxTotalBytes = 5 * 1024 * 1024; // 5 MB total
  static const int maxSingleBytes = 2 * 1024 * 1024; // 2 MB par image (apres compression)
  final ImagePicker _picker = ImagePicker();

  /// Ouvre la galerie pour selectionner plusieurs images.
  Future<List<Attachment>> pickFromGallery({bool allowMultiple = true}) async {
    final picked = await _picker.pickMultiImage(
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked.isEmpty) return [];
    return _processImages(picked.map((x) => File(x.path)).toList());
  }

  /// Ouvre la camera pour prendre une photo (unique).
  Future<List<Attachment>> pickFromCamera() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null) return [];
    return _processImages([File(picked.path)]);
  }

  Future<List<Attachment>> _processImages(List<File> files) async {
    final results = <Attachment>[];
    var totalSize = 0;

    for (final file in files) {
      try {
        final att = await _processSingleImage(file);
        if (att == null) continue;

        // Verification limite agrégée
        if (totalSize + att.sizeBytes > maxTotalBytes) {
          debugPrint('[ImageUploadService] Limite 5MB atteinte, ${files.length - results.length} image(s) ignorée(s)');
          break;
        }

        results.add(att);
        totalSize += att.sizeBytes;
      } catch (e) {
        debugPrint('[ImageUploadService] Erreur traitement image : $e');
      }
    }

    if (results.isEmpty && files.isNotEmpty) {
      throw const ImageUploadException(
        'Aucune image valide. Limite totale : 5MB.',
      );
    }

    return results;
  }

  Future<Attachment?> _processSingleImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final originalSize = bytes.length;
      debugPrint('[ImageUploadService] Original size: ${(originalSize / 1024).toStringAsFixed(1)}KB');

      var compressedBytes = bytes;
      if (originalSize > 5 * 1024 * 1024) {
        final result = await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          minWidth: 1024,
          minHeight: 1024,
          quality: 50,
          format: CompressFormat.jpeg,
        );
        if (result != null) compressedBytes = result;
      } else if (originalSize > 2 * 1024 * 1024) {
        final result = await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          minWidth: 1280,
          minHeight: 1280,
          quality: 60,
          format: CompressFormat.jpeg,
        );
        if (result != null) compressedBytes = result;
      } else if (originalSize > 700 * 1024) {
        final result = await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          minWidth: 1600,
          minHeight: 1600,
          quality: 75,
          format: CompressFormat.jpeg,
        );
        if (result != null) compressedBytes = result;
      }

      // Limite stricte par image : 2MB
      if (compressedBytes.length > maxSingleBytes) {
        final lastTry = await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          minWidth: 1024,
          minHeight: 1024,
          quality: 45,
          format: CompressFormat.jpeg,
        );
        if (lastTry != null && lastTry.length <= maxSingleBytes) {
          compressedBytes = lastTry;
        } else {
          throw ImageUploadException(
            'Image trop volumineuse après compression (max ${maxSingleBytes ~/ 1024}KB)',
          );
        }
      }

      final base64 = base64Encode(compressedBytes);
      if (base64.length > 2.5 * 1024 * 1024) {
        throw const ImageUploadException('Image encodee trop volumineuse');
      }

      final mimeType = _detectMimeType(file.path);
      debugPrint('[ImageUploadService] Final size: ${(compressedBytes.length / 1024).toStringAsFixed(1)}KB');

      return Attachment(
        type: AttachmentType.image,
        name: file.path.split('/').last,
        mimeType: mimeType,
        sizeBytes: compressedBytes.length,
        imageBase64: base64,
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