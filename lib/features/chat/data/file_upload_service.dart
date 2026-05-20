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
///
/// Supporte : PDF, DOCX, XLSX, PPTX, TXT, CSV, MD
/// Extraction pure Dart, sans dépendance native.
class FileUploadService {
  static const int maxSizeFreeBytes = 5 * 1024 * 1024; // 5 MB
  static const int maxSizeProBytes = 50 * 1024 * 1024; // 50 MB

  /// Limites de contexte fichier (en caractères).
  static const int maxContextCharsFree = 15000;
  static const int maxContextCharsPro = 30000;

  /// Ouvre le picker et extrait le texte du fichier selectionne.
  Future<FileUploadResult?> pickAndExtract({required bool isPro}) async {
    final maxSize = isPro ? maxSizeProBytes : maxSizeFreeBytes;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'xlsx', 'pptx', 'txt', 'csv', 'md'],
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

  /// Tronque intelligemment un texte à la limite de contexte.
  /// Respecte les limites de paragraphes et phrases.
  static String truncateForContext(String text, {required bool isPro}) {
    final maxChars = isPro ? maxContextCharsPro : maxContextCharsFree;

    if (text.length <= maxChars) return text;

    // 1. Essayer de couper au dernier paragraphe complet avant la limite
    final paragraphBreak = text.lastIndexOf('\n\n', maxChars);
    if (paragraphBreak > maxChars * 0.5) {
      return '${text.substring(0, paragraphBreak)}\n\n[... contenu tronque — ${text.length - paragraphBreak} caracteres restants]';
    }

    // 2. Essayer de couper à la dernière phrase complète
    final sentenceEnd = lastSentenceEnd(text, maxChars);
    if (sentenceEnd > maxChars * 0.5) {
      return '${text.substring(0, sentenceEnd)}\n\n[... contenu tronque — ${text.length - sentenceEnd} caracteres restants]';
    }

    // 3. Dernier recours : coupe dure
    return '${text.substring(0, maxChars)}... [tronque]';
  }

  /// Trouve la position de la fin de la dernière phrase complète avant [limit].
  static int lastSentenceEnd(String text, int limit) {
    const sentenceEnders = ['. ', '.\n', '! ', '? ', '!\n', '?\n'];
    final searchEnd = limit < text.length ? limit : text.length - 1;
    if (searchEnd < 0) return 0;
    var lastPos = 0;
    for (final ender in sentenceEnders) {
      final pos = text.lastIndexOf(ender, searchEnd);
      if (pos > lastPos) lastPos = pos + ender.length;
    }
    return lastPos;
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
        case 'pptx':
          return _extractPptx(bytes);
        case 'txt':
        case 'csv':
        case 'md':
          return _decodeTextFile(bytes);
        default:
          throw FileUploadException('Format non supporte: .$ext');
      }
    } catch (e) {
      if (e is FileUploadException) rethrow;
      debugPrint('[FileUploadService] Extraction error: $e');
      throw FileUploadException('Erreur extraction $name: $e');
    }
  }

  /// Decode un fichier texte en gerant le BOM UTF-8/UTF-16.
  String _decodeTextFile(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return utf8.decode(bytes.sublist(2), allowMalformed: true);
      }
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return utf8.decode(bytes.sublist(2), allowMalformed: true);
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
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
          final hexBytes = <int>[];
          for (var i = 0; i < hex.length; i += 2) {
            hexBytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
          }
          final decoded = utf8.decode(hexBytes, allowMalformed: true).trim();
          if (decoded.length > 2) results.add(decoded);
        } catch (_) {}
      }
    }

    // 4. Nettoyer les duplicats et assembler avec des retours à la ligne
    final seen = <String>{};
    final unique = <String>[];
    for (final t in results) {
      final clean = t.trim();
      if (clean.isEmpty) continue;
      if (seen.contains(clean)) continue;
      seen.add(clean);
      unique.add(clean);
    }

    // Assembler en paragraphes (retour à la ligne entre les blocs de texte)
    return unique.isNotEmpty
        ? _groupIntoParagraphs(unique)
        : '[Extraction PDF brute incomplete — fichier complexe]';
  }

  /// Regroupe les fragments de texte en paragraphes cohérents.
  static String _groupIntoParagraphs(List<String> fragments) {
    final buffer = StringBuffer();
    var currentLine = StringBuffer();

    for (final fragment in fragments) {
      // Si le fragment se termine par une ponctuation de fin, c'est probablement
      // la fin d'un paragraphe
      if (fragment.endsWith('.') ||
          fragment.endsWith('!') ||
          fragment.endsWith('?') ||
          fragment.endsWith(':')) {
        currentLine.write(fragment);
        buffer.writeln(currentLine.toString().trim());
        buffer.writeln();
        currentLine.clear();
      } else {
        currentLine.write('$fragment ');
      }
    }

    // Ne pas oublier le dernier fragment
    if (currentLine.isNotEmpty) {
      buffer.writeln(currentLine.toString().trim());
    }

    return buffer.toString().trim();
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

    // Regrouper par paragraphes (w:p)
    final paragraphs = <String>[];
    final pElements = document.findAllElements('w:p');
    for (final p in pElements) {
      final pTexts = p.findAllElements('w:t').map((t) => t.innerText).join('');
      if (pTexts.trim().isNotEmpty) {
        paragraphs.add(pTexts);
      }
    }

    if (paragraphs.isNotEmpty) {
      return paragraphs.join('\n\n');
    }

    // Fallback : texte brut sans structure de paragraphe
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
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  /// Extraction PPTX — un PPTX est un ZIP contenant des XML par slide.
  String _extractPptx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // Trouver toutes les slides (ppt/slide/slide1.xml, slide2.xml, etc.)
    final slideFiles = archive
        .where((f) => f.name.startsWith('ppt/slide/slide') && f.name.endsWith('.xml'))
        .toList()
      ..sort((a, b) {
        final numA = int.tryParse(a.name.replaceAll(RegExp(r'[^\d]'), '') ?? '0') ?? 0;
        final numB = int.tryParse(b.name.replaceAll(RegExp(r'[^\d]'), '') ?? '0') ?? 0;
        return numA.compareTo(numB);
      });

    if (slideFiles.isEmpty) {
      return '[Aucune diapositive trouvée dans le fichier PPTX]';
    }

    final slides = <String>[];

    for (final slideFile in slideFiles) {
      final content = utf8.decode(slideFile.content as List<int>, allowMalformed: true);
      final document = XmlDocument.parse(content);

      // Extraire les textes des éléments <a:t> (texte dans les shapes)
      final texts = document.findAllElements('a:t').map((t) => t.innerText).toList();

      // Regrouper par shape (<p:sp> ou <p:cxSp>) pour structurer
      final slideTexts = <String>[];
      final shapes = document.findAllElements('p:sp');
      for (final shape in shapes) {
        final shapeText = shape.findAllElements('a:t').map((t) => t.innerText).join(' ');
        if (shapeText.trim().isNotEmpty) {
          slideTexts.add(shapeText.trim());
        }
      }

      // Fallback si pas de shapes structurés
      if (slideTexts.isEmpty && texts.isNotEmpty) {
        slideTexts.add(texts.join(' '));
      }

      if (slideTexts.isNotEmpty) {
        final slideNum = slideFiles.indexOf(slideFile) + 1;
        slides.add('--- Diapositive $slideNum ---\n${slideTexts.join('\n')}');
      }
    }

    return slides.join('\n\n');
  }

  String _getExtension(String path) {
    final idx = path.lastIndexOf('.');
    if (idx == -1 || idx == path.length - 1) return '';
    return path.substring(idx + 1).toLowerCase();
  }

  String _detectMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.md')) return 'text/markdown';
    return 'text/plain';
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
}