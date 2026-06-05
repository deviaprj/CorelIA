import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import '../domain/attachment.dart';

/// Exception specifique au service d'upload de fichiers.
class FileUploadException implements Exception {
  final String message;
  const FileUploadException(this.message);
  @override
  String toString() => 'FileUploadException: \$message';
}

/// Service d'upload et extraction de texte depuis fichiers — 100% autonome.
///
/// Supporte la selection multiple avec limite agrégée de 5MB.
/// Formats : PDF, DOCX, XLSX, PPTX, TXT, CSV, MD
class FileUploadService {
  static const int maxTotalBytes = 5 * 1024 * 1024; // 5 MB total
  static const int maxSingleBytes = 5 * 1024 * 1024; // 5 MB par fichier

  /// Ouvre le picker et extrait le texte des fichiers selectionnes.
  Future<List<Attachment>> pickAndExtract({bool allowMultiple = true}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'xlsx', 'pptx', 'txt', 'csv', 'md'],
      withData: true,
      allowMultiple: allowMultiple,
    );

    if (result == null || result.files.isEmpty) return [];

    final attachments = <Attachment>[];
    var totalSize = 0;

    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;

      if (bytes.length > maxSingleBytes) {
        debugPrint('[FileUploadService] \${file.name} ignoree (\${bytes.length ~/ 1024}KB > \${maxSingleBytes ~/ 1024}KB)');
        continue;
      }

      if (totalSize + bytes.length > maxTotalBytes) {
        debugPrint('[FileUploadService] Limite 5MB atteinte, \${result.files.length - attachments.length} fichier(s) ignore(s)');
        break;
      }

      final ext = _getExtension(file.name);
      final mime = _detectMimeType(file.name);
      final text = await _extractText(bytes, ext, file.name);

      attachments.add(Attachment(
        type: Attachment.detectType(file.name),
        name: file.name,
        mimeType: mime,
        sizeBytes: bytes.length,
        extractedText: text,
        rawBytes: bytes,
      ));
      totalSize += bytes.length;
    }

    return attachments;
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
          throw FileUploadException('Format non supporte: .\$ext');
      }
    } catch (e) {
      if (e is FileUploadException) rethrow;
      debugPrint('[FileUploadService] Extraction error: \$e');
      throw FileUploadException('Erreur extraction \$name: \$e');
    }
  }

  String _decodeTextFile(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _extractPdf(Uint8List bytes) {
    final direct = _extractStringsFromRawPdf(bytes);
    if (direct.length > 80 && !direct.startsWith('[')) return direct;
    try {
      final fromStreams = _extractFromPdfStreams(bytes);
      if (fromStreams.length > 80) return fromStreams;
    } catch (e, st) {
      debugPrint('[FileUploadService] PDF stream extraction error: \$e');
      debugPrint(st.toString());
    }
    return '[Extraction PDF incomplete — fichier probablement scanne, protege ou vectoriel]';
  }

  String _extractStringsFromRawPdf(Uint8List bytes) {
    final raw = utf8.decode(bytes, allowMalformed: true);
    final results = <String>[];
    final parenRegex = RegExp(r"\(([^\\()]*(?:\\.[^\\()]*)*)\)\s*(?:Tj|T')");
    for (final m in parenRegex.allMatches(raw)) {
      final t = m.group(1);
      if (t != null && t.length > 1) results.add(_unescapePdfString(t));
    }
    if (results.isEmpty) {
      final fallbackRegex = RegExp(r'\(([^\\()]{3,}(?:\\.[^\\()]*)*)\)');
      for (final m in fallbackRegex.allMatches(raw)) {
        final t = m.group(1);
        if (t != null) results.add(_unescapePdfString(t));
      }
    }
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
    final seen = <String>{};
    final unique = <String>[];
    for (final t in results) {
      final clean = t.trim();
      if (clean.isEmpty || seen.contains(clean)) continue;
      seen.add(clean);
      unique.add(clean);
    }
    return unique.isNotEmpty
        ? _groupIntoParagraphs(unique)
        : '[Extraction PDF brute incomplete — fichier complexe]';
  }

  String _extractFromPdfStreams(Uint8List bytes) {
    final allTexts = <String>[];
    for (final stream in _findPdfStreams(bytes)) {
      if (stream.data.isEmpty) continue;
      Uint8List data = stream.data;
      if (stream.dictionary.contains('/FlateDecode')) {
        try {
          final decompressed = inflateBuffer(data.toList());
          if (decompressed != null && decompressed.isNotEmpty) {
            data = Uint8List.fromList(decompressed);
          } else continue;
        } catch (_) { continue; }
      }
      final decodedPreview = utf8.decode(data, allowMalformed: true);
      if (decodedPreview.contains('/Type /XRef') ||
          decodedPreview.contains('/Type /ObjStm') ||
          decodedPreview.contains('/Type /Catalog')) continue;
      final texts = _extractPdfStringsFromDecoded(data);
      if (texts.isNotEmpty) allTexts.addAll(texts);
    }
    if (allTexts.isEmpty) return '';
    return _groupIntoParagraphs(_deduplicateStrings(allTexts));
  }

  List<_PdfStream> _findPdfStreams(Uint8List bytes) {
    final streams = <_PdfStream>[];
    final marker = utf8.encode('stream');
    final endMarker = utf8.encode('endstream');
    var searchStart = 0;
    while (searchStart < bytes.length) {
      final idx = _indexOfBytes(bytes, marker, searchStart);
      if (idx == -1) break;
      var dataStart = idx + marker.length;
      while (dataStart < bytes.length && _isPdfWhitespace(bytes[dataStart])) dataStart++;
      final endIdx = _indexOfBytes(bytes, endMarker, dataStart);
      if (endIdx == -1) break;
      var dataEnd = endIdx;
      while (dataEnd > dataStart && _isPdfWhitespace(bytes[dataEnd - 1])) dataEnd--;
      if (dataEnd <= dataStart) { searchStart = idx + marker.length; continue; }
      final streamData = bytes.sublist(dataStart, dataEnd);
      var dictStart = idx - 1;
      var dictFound = false;
      while (dictStart >= 0 && idx - dictStart < 600) {
        if (bytes[dictStart] == 0x3C && dictStart + 1 < bytes.length && bytes[dictStart + 1] == 0x3C) {
          dictFound = true; break;
        }
        dictStart--;
      }
      if (!dictFound) { searchStart = idx + marker.length; continue; }
      final dictBytes = bytes.sublist(dictStart, idx);
      final dict = utf8.decode(dictBytes, allowMalformed: true);
      streams.add(_PdfStream(data: streamData, dictionary: dict));
      searchStart = endIdx + endMarker.length;
    }
    return streams;
  }

  List<String> _extractPdfStringsFromDecoded(Uint8List bytes) {
    final results = <String>[];
    final raw = utf8.decode(bytes, allowMalformed: true);
    final parenRegex = RegExp(r"\(([^\\()]*(?:\\.[^\\()]*)*)\)\s*(?:Tj|T')");
    for (final m in parenRegex.allMatches(raw)) {
      final t = m.group(1);
      if (t != null && t.length > 1) results.add(_unescapePdfString(t));
    }
    if (results.isEmpty) {
      final fallbackRegex = RegExp(r'\(([^\\()]{3,}(?:\\.[^\\()]*)*)\)');
      for (final m in fallbackRegex.allMatches(raw)) {
        final t = m.group(1);
        if (t != null) results.add(_unescapePdfString(t));
      }
    }
    final hexRegex = RegExp(r'<([0-9A-Fa-f\s]{4,})>');
    for (final m in hexRegex.allMatches(raw)) {
      final hex = m.group(1)?.replaceAll(RegExp(r'\s+'), '');
      if (hex != null && hex.length % 2 == 0) {
        try {
          final hexBytes = <int>[];
          for (var i = 0; i < hex.length; i += 2) hexBytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
          final decoded = utf8.decode(hexBytes, allowMalformed: true).trim();
          if (decoded.length > 2) results.add(decoded);
        } catch (_) {}
      }
    }
    return results;
  }

  static List<String> _deduplicateStrings(List<String> items) {
    final seen = <String>{};
    final out = <String>[];
    for (final t in items) {
      final clean = t.trim();
      if (clean.isEmpty || seen.contains(clean)) continue;
      seen.add(clean); out.add(clean);
    }
    return out;
  }

  static bool _isPdfWhitespace(int b) {
    return b == 0x00 || b == 0x09 || b == 0x0A || b == 0x0C || b == 0x0D || b == 0x20;
  }

  static int _indexOfBytes(Uint8List data, List<int> pattern, int start) {
    if (pattern.isEmpty) return start;
    outer: for (var i = start; i <= data.length - pattern.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  static String _groupIntoParagraphs(List<String> fragments) {
    final buffer = StringBuffer();
    var currentLine = StringBuffer();
    for (final fragment in fragments) {
      if (fragment.endsWith('.') || fragment.endsWith('!') || fragment.endsWith('?') || fragment.endsWith(':')) {
        currentLine.write(fragment);
        buffer.writeln(currentLine.toString().trim());
        buffer.writeln();
        currentLine.clear();
      } else {
        currentLine.write('\$fragment ');
      }
    }
    if (currentLine.isNotEmpty) buffer.writeln(currentLine.toString().trim());
    return buffer.toString().trim();
  }

  String _extractDocx(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final documentXml = archive.firstWhere(
        (f) => f.name == 'word/document.xml',
        orElse: () => throw const FileUploadException('Structure DOCX invalide'),
      );
      final content = utf8.decode(documentXml.content as List<int>);
      final document = XmlDocument.parse(content);

      // Namespace-agnostic extraction : cherche les paragraphes par localName 'p'
      // dans le namespace wordprocessingml (pas de dépendance au préfixe 'w:')
      final paragraphs = <String>[];
      for (final node in document.descendants) {
        if (node is! XmlElement) continue;
        final name = node.name;
        if (name.local == 'p' &&
            (name.namespaceUri?.contains('wordprocessingml') ?? false)) {
          final pTexts = <String>[];
          for (final child in node.descendants) {
            if (child is XmlElement &&
                child.name.local == 't' &&
                (child.name.namespaceUri?.contains('wordprocessingml') ?? false)) {
              pTexts.add(child.innerText);
            }
          }
          final joined = pTexts.join();
          if (joined.trim().isNotEmpty) paragraphs.add(joined);
        }
      }

      if (paragraphs.isNotEmpty) return paragraphs.join('\n\n');

      // Fallback : tous les nœuds 't' sans restriction de namespace
      final allTexts = document.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 't')
          .map((n) => n.innerText)
          .toList();
      return allTexts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    } on XmlException catch (e) {
      debugPrint('[FileUploadService] DOCX XML parse error: $e');
      return '[Erreur parsing DOCX — fichier probablement corrompu]';
    } on ArchiveException catch (e) {
      debugPrint('[FileUploadService] DOCX ZIP error: $e');
      return '[Erreur archive DOCX — fichier ZIP invalide]';
    }
  }

  String _extractXlsx(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final buffer = StringBuffer();
    for (final table in excel.tables.keys) {
      final sheet = excel.tables[table]!;
      buffer.writeln('--- \$table ---');
      for (final row in sheet.rows) {
        final cells = row.map((cell) => cell?.value?.toString() ?? '').join('\t');
        if (cells.trim().isNotEmpty) buffer.writeln(cells);
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  String _extractPptx(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final slideFiles = archive
          .where((f) => f.name.startsWith('ppt/slides/slide') && f.name.endsWith('.xml'))
          .toList()
        ..sort((a, b) {
          final numA = int.tryParse(a.name.replaceAll(RegExp(r'[^\d]'), '') ?? '0') ?? 0;
          final numB = int.tryParse(b.name.replaceAll(RegExp(r'[^\d]'), '') ?? '0') ?? 0;
          return numA.compareTo(numB);
        });
      if (slideFiles.isEmpty) return '[Aucune diapositive trouvee]';
      final slides = <String>[];
      for (final slideFile in slideFiles) {
        final content = utf8.decode(slideFile.content as List<int>, allowMalformed: true);
        final document = XmlDocument.parse(content);
        final slideTexts = <String>[];

        // Namespace-agnostic : cherche tous les éléments 't' (text) dans le document
        // sans dépendre du préfixe 'a:' ou 'p:'
        final allTextElements = document.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 't')
            .toList();

        // Regrouper par élément shape/sp parent pour préserver la structure
        final shapeTexts = <String>[];
        for (final node in document.descendants) {
          if (node is! XmlElement) continue;
          if (node.name.local == 'sp') {
            final shapeTextNodes = node.descendants
                .whereType<XmlElement>()
                .where((e) => e.name.local == 't')
                .map((e) => e.innerText)
                .toList();
            if (shapeTextNodes.isNotEmpty) {
              shapeTexts.add(shapeTextNodes.join(' ').trim());
            }
          }
        }

        if (shapeTexts.isNotEmpty) {
          slideTexts.addAll(shapeTexts);
        } else if (allTextElements.isNotEmpty) {
          // Fallback : tous les textes plats
          slideTexts.add(allTextElements.map((e) => e.innerText).join(' '));
        }

        if (slideTexts.isNotEmpty) {
          final slideNum = slideFiles.indexOf(slideFile) + 1;
          slides.add("--- Diapositive $slideNum ---\n${slideTexts.join('\n')}");
        }
      }
      return slides.join('\n\n');
    } on XmlException catch (e) {
      debugPrint('[FileUploadService] PPTX XML parse error: $e');
      return '[Erreur parsing PPTX — fichier probablement corrompu]';
    } on ArchiveException catch (e) {
      debugPrint('[FileUploadService] PPTX ZIP error: $e');
      return '[Erreur archive PPTX — fichier ZIP invalide]';
    }
  }

  static const int maxContextCharsFree = 15000;
  static const int maxContextCharsPro = 30000;

  /// Tronque intelligemment un texte a la limite de contexte.
  /// Respecte les limites de paragraphes et phrases.
  static String truncateForContext(String text, {required bool isPro}) {
    final maxChars = isPro ? maxContextCharsPro : maxContextCharsFree;

    if (text.length <= maxChars) return text;

    // 1. Essayer de couper au dernier paragraphe complet avant la limite
    final paragraphBreak = text.lastIndexOf('\n\n', maxChars);
    if (paragraphBreak > maxChars * 0.5) {
      return '${text.substring(0, paragraphBreak)}\n\n[... contenu tronque — ${text.length - paragraphBreak} caracteres restants]';
    }

    // 2. Essayer de couper a la derniere phrase complete
    final sentenceEnd = lastSentenceEnd(text, maxChars);
    if (sentenceEnd > maxChars * 0.5) {
      return '${text.substring(0, sentenceEnd)}\n\n[... contenu tronque — ${text.length - sentenceEnd} caracteres restants]';
    }

    // 3. Dernier recours : coupe dure
    return '${text.substring(0, maxChars)}... [tronque]';
  }

  /// Trouve la position de la fin de la derniere phrase complete avant [limit].
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
    if (lower.endsWith('.pptx')) return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.md')) return 'text/markdown';
    return 'text/plain';
  }

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

class _PdfStream {
  final Uint8List data;
  final String dictionary;
  const _PdfStream({required this.data, required this.dictionary});
}
