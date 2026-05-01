import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

/// Exception specifique au service d'upload de fichiers.
class FileUploadException implements Exception {
  final String message;
  const FileUploadException(this.message);
  @override
  String toString() => 'FileUploadException: $message';
}

/// Resultat d'une extraction de fichier.
class FileUploadResult {
  final String fileName;
  final String extractedText;
  final String mimeType;
  final int sizeBytes;

  const FileUploadResult({
    required this.fileName,
    required this.extractedText,
    required this.mimeType,
    required this.sizeBytes,
  });
}

/// Service d'upload et extraction de texte depuis fichiers — 100% autonome.
class FileUploadService {
  static const int maxSizeFreeBytes = 5 * 1024 * 1024; // 5 MB
  static const int maxSizeProBytes = 50 * 1024 * 1024; // 50 MB

  /// Ouvre le picker et extrait le texte du fichier selectionne.
  Future<FileUploadResult?> pickAndExtract({required bool isPro}) async {
    final maxSize = isPro ? maxSizeProBytes : maxSizeFreeBytes;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'xlsx', 'txt', 'csv', 'md'],
      withData: true,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final bytes = file.bytes;
    final name = file.name;

    if (bytes == null) {
      throw const FileUploadException('Impossible de lire le fichier');
    }

    if (bytes.length > maxSize) {
      throw FileUploadException(
        'Fichier trop volumineux (max ${isPro ? '50' : '5'}MB)',
      );
    }

    final ext = _getExtension(name);
    final mime = _detectMimeType(name);

    final text = await _extractText(bytes, ext, name);

    return FileUploadResult(
      fileName: name,
      extractedText: text,
      mimeType: mime,
      sizeBytes: bytes.length,
    );
  }

  Future<String> _extractText(Uint8List bytes, String ext, String name) async {
    try {
      switch (ext) {
        case 'pdf':
          return _extractPdf(bytes);
        case 'docx':
          return _extractDocx(bytes);
        case 'xlsx':
          return _extractXlsx(bytes);
        case 'txt':
        case 'csv':
        case 'md':
          return utf8.decode(bytes, allowMalformed: true);
        default:
          throw FileUploadException('Format non supporte: .$ext');
      }
    } catch (e) {
      debugPrint('[FileUploadService] Extraction error: $e');
      throw FileUploadException('Erreur extraction $name: $e');
    }
  }

  String _extractPdf(Uint8List bytes) {
    // Extraction pure Dart sans dependance native.
    // Fonctionne bien sur les PDF textuels (Word -> PDF, LaTeX, etc.).
    // Les PDF scannes ou avec encodages complexes peuvent etre partiels.
    return _extractStringsFromRawPdf(bytes);
  }

  String _extractStringsFromRawPdf(Uint8List bytes) {
    final raw = utf8.decode(bytes, allowMalformed: true);
    final results = <String>[];

    // 1. Extraire les textes entre parentheses (operateurs Tj / ')
    // Format PDF: (texte) Tj  ou  (texte) '
    final parenRegex = RegExp(r"\(([^\\()]*(?:\\.[^\\()]*)*)\)\s*(?:Tj|T')");
    for (final m in parenRegex.allMatches(raw)) {
      final t = m.group(1);
      if (t != null && t.length > 1) {
        results.add(_unescapePdfString(t));
      }
    }

    // 2. Extraire les textes entre parentheses generaux (fallback)
    if (results.isEmpty) {
      final fallbackRegex = RegExp(r'\(([^\\()]{3,}(?:\\.[^\\()]*)*)\)');
      for (final m in fallbackRegex.allMatches(raw)) {
        final t = m.group(1);
        if (t != null) {
          results.add(_unescapePdfString(t));
        }
      }
    }

    // 3. Extraire les chaines hexadecimales <...>
    final hexRegex = RegExp(r'<([0-9A-Fa-f\s]{4,})>');
    for (final m in hexRegex.allMatches(raw)) {
      final hex = m.group(1)?.replaceAll(RegExp(r'\s+'), '');
      if (hex != null && hex.length % 2 == 0) {
        try {
          final bytes = <int>[];
          for (var i = 0; i < hex.length; i += 2) {
            bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
          }
          final decoded = utf8.decode(bytes, allowMalformed: true).trim();
          if (decoded.length > 2) results.add(decoded);
        } catch (_) {}
      }
    }

    // 4. Nettoyer les duplicats et assembler
    final seen = <String>{};
    final unique = <String>[];
    for (final t in results) {
      final clean = t.trim();
      if (clean.isEmpty) continue;
      if (seen.contains(clean)) continue;
      seen.add(clean);
      unique.add(clean);
    }

    return unique.isNotEmpty
        ? unique.join(' ')
        : '[Extraction PDF brute incomplete — fichier complexe]';
  }

  /// Decode les echappements PDF courants.
  String _unescapePdfString(String s) {
    return s
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\b', '\b')
        .replaceAll(r'\f', '\f')
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')')
        .replaceAll(r'\\', '\\')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _extractDocx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final documentXml = archive.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () => throw const FileUploadException('Structure DOCX invalide'),
    );

    final content = utf8.decode(documentXml.content as List<int>);
    final document = XmlDocument.parse(content);

    final texts = document.findAllElements('w:t').map((node) => node.innerText);
    return texts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _extractXlsx(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final buffer = StringBuffer();

    for (final table in excel.tables.keys) {
      final sheet = excel.tables[table]!;
      buffer.writeln('--- $table ---');
      for (final row in sheet.rows) {
        final cells = row.map((cell) {
          if (cell == null) return '';
          return cell.value?.toString() ?? '';
        }).join('\t');
        if (cells.trim().isNotEmpty) {
          buffer.writeln(cells);
        }
      }
    }
    return buffer.toString().trim();
  }

  String _getExtension(String path) {
    final idx = path.lastIndexOf('.');
    if (idx == -1 || idx == path.length - 1) return '';
    return path.substring(idx + 1).toLowerCase();
  }

  String _detectMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.docx')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    if (lower.endsWith('.xlsx')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.md')) return 'text/markdown';
    return 'text/plain';
  }
}
