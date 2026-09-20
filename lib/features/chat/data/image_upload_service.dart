import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/attachment.dart';

/// Exception spécifique au service d'upload d'images.
class ImageUploadException implements Exception {
  const ImageUploadException(this.message);

  final String message;

  @override
  String toString() => 'ImageUploadException: $message';
}

/// Sélection, compression et encodage des images (100 % côté client).
class ImageUploadService {
  static const int maxTotalBytes = 5 * 1024 * 1024;
  static const int maxSingleBytes = 2 * 1024 * 1024;

  final ImagePicker _picker = ImagePicker();

  Future<List<Attachment>> pickFromGallery({bool allowMultiple = true}) async {
    final picked = await _picker.pickMultiImage(
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked.isEmpty) return const [];
    return _process(picked.map((x) => File(x.path)).toList());
  }

  Future<List<Attachment>> pickFromCamera() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null) return const [];
    return _process([File(picked.path)]);
  }

  Future<List<Attachment>> _process(List<File> files) async {
    final results = <Attachment>[];
    var totalSize = 0;

    for (final file in files) {
      final att = await _processSingle(file);
      if (att == null) continue;
      if (totalSize + att.sizeBytes > maxTotalBytes) break;
      results.add(att);
      totalSize += att.sizeBytes;
    }

    if (results.isEmpty && files.isNotEmpty) {
      throw const ImageUploadException('Aucune image valide (max 5 Mo au total).');
    }
    return results;
  }

  Future<Attachment?> _processSingle(File file) async {
    try {
      final bytes = await file.readAsBytes();
      var compressed = bytes;

      if (bytes.length > 2 * 1024 * 1024) {
        final result = await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          minWidth: 1280,
          minHeight: 1280,
          quality: 60,
          format: CompressFormat.jpeg,
        );
        if (result != null) compressed = result;
      } else if (bytes.length > 700 * 1024) {
        final result = await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          minWidth: 1600,
          minHeight: 1600,
          quality: 75,
          format: CompressFormat.jpeg,
        );
        if (result != null) compressed = result;
      }

      if (compressed.length > maxSingleBytes) {
        final lastTry = await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          minWidth: 1024,
          minHeight: 1024,
          quality: 45,
          format: CompressFormat.jpeg,
        );
        if (lastTry == null || lastTry.length > maxSingleBytes) {
          throw ImageUploadException(
            'Image trop volumineuse après compression '
            '(max ${maxSingleBytes ~/ 1024} Ko)',
          );
        }
        compressed = lastTry;
      }

      return Attachment(
        type: AttachmentType.image,
        name: file.path.split('/').last,
        mimeType: _detectMimeType(file.path),
        sizeBytes: compressed.length,
        imageBase64: base64Encode(compressed),
      );
    } catch (e) {
      debugPrint('[ImageUploadService] Échec du traitement : $e');
      return null;
    }
  }

  static String _detectMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'image/jpeg';
  }
}
