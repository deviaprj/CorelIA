import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class GeneratedDocument {
  final String fileName;
  final String mimeType;
  final String base64Content;
  final int sizeBytes;
  final Uint8List bytes;

  const GeneratedDocument({
    required this.fileName,
    required this.mimeType,
    required this.base64Content,
    required this.sizeBytes,
    required this.bytes,
  });
}

/// Internal section model for PPTX generation.
class _PptxSection {
  final String title;
  final String content;
  final String? imageDescription;

  _PptxSection({required this.title, required this.content, this.imageDescription});
}

/// Internal hyperlink model for PPTX sources slide.
class _SourceLink {
  final String text;
  final String url;

  _SourceLink({required this.text, required this.url});
}

class DocumentGenerationService {
  Future<GeneratedDocument> generate({
    required String format,
    required String title,
    required String body,
    required List<String> sources,
    String? preferredFileName,
  }) async {
    final normalized = _normalizeFormat(format);
    final safeTitle = _safeFileName(preferredFileName?.trim().isNotEmpty == true
        ? preferredFileName!.trim()
        : title);

    final fullText = _composeDocumentText(
      title: title,
      body: body,
      sources: sources,
    );

    late Uint8List fileBytes;
    late String ext;
    late String mimeType;

    switch (normalized) {
      case 'text':
        fileBytes = Uint8List.fromList(utf8.encode(fullText));
        ext = 'txt';
        mimeType = 'text/plain';
        break;
      case 'markdown':
        fileBytes = Uint8List.fromList(utf8.encode(_toMarkdown(title, body, sources)));
        ext = 'md';
        mimeType = 'text/markdown';
        break;
      case 'word':
        fileBytes = await _toDocx(title, body, sources);
        ext = 'docx';
        mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        break;
      case 'powerpoint':
        fileBytes = await _toPptx(title, body, sources);
        ext = 'pptx';
        mimeType = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
        break;
      case 'excel':
        fileBytes = _toExcel(title, body, sources);
        ext = 'xlsx';
        mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        break;
      case 'jpg':
        fileBytes = await _toImage(title, format: 'jpg');
        ext = 'jpg';
        mimeType = 'image/jpeg';
        break;
      case 'png':
        fileBytes = await _toImage(title, format: 'png');
        ext = 'png';
        mimeType = 'image/png';
        break;
      case 'pdf':
      default:
        fileBytes = await _toPdf(title, body, sources);
        ext = 'pdf';
        mimeType = 'application/pdf';
        break;
    }

    return GeneratedDocument(
      fileName: '$safeTitle.$ext',
      mimeType: mimeType,
      base64Content: base64Encode(fileBytes),
      sizeBytes: fileBytes.length,
      bytes: fileBytes,
    );
  }

  String _normalizeFormat(String format) {
    final lower = format.toLowerCase();
    if (lower == 'txt' || lower == 'text') return 'text';
    if (lower == 'md' || lower == 'markdown') return 'markdown';
    if (lower == 'word' || lower == 'doc' || lower == 'docx') return 'word';
    if (lower == 'ppt' || lower == 'pptx' || lower == 'powerpoint') return 'powerpoint';
    if (lower == 'xls' || lower == 'xlsx' || lower == 'excel') return 'excel';
    if (lower == 'jpg' || lower == 'jpeg') return 'jpg';
    if (lower == 'png') return 'png';
    if (lower == 'pdf') return 'pdf';
    return 'pdf';
  }

  String _safeFileName(String input) {
    final sanitized = input
        .replaceAll(RegExp(r'[^a-zA-Z0-9\-_.À-ÿ\s]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    if (sanitized.isEmpty) return 'document_corely';
    return sanitized.length > 80 ? sanitized.substring(0, 80) : sanitized;
  }

  // ── Text & Markdown ────────────────────────────────────────────────────────

  String _composeDocumentText({
    required String title,
    required String body,
    required List<String> sources,
  }) {
    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final cleanBody = _cleanBodyForDocgen(_stripLeadingTitle(body, title));

    final sourceLines = sources.isEmpty
        ? 'Aucune source web explicite.'
        : sources.map((s) {
            final emDashIdx = s.indexOf(' — ');
            final urlPart = emDashIdx != -1 ? s.substring(emDashIdx + 3).trim() : s;
            final decoded = _decodeRedirectUrl(urlPart);
            final domain = _extractDomain(decoded);
            return '- $domain : $decoded';
          }).join('\n');

    return '═══════════════════════════════════════\n'
        '  $title\n'
        '  Généré par Corely — $dateStr\n'
        '═══════════════════════════════════════\n\n'
        '$cleanBody\n\n'
        '───────────────────────────────────────\n'
        'SOURCES\n'
        '───────────────────────────────────────\n'
        '$sourceLines\n';
  }

  String _toMarkdown(String title, String body, List<String> sources) {
    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final cleanBody = _cleanBodyForDocgen(_stripLeadingTitle(body, title));

    final sourceLines = sources.isEmpty
        ? '- Aucune source web explicite.'
        : sources.map((s) {
            final emDashIdx = s.indexOf(' — ');
            final urlPart = emDashIdx != -1 ? s.substring(emDashIdx + 3).trim() : s;
            final decoded = _decodeRedirectUrl(urlPart);
            final domain = _extractDomain(decoded);
            return '- [$domain]($decoded)';
          }).join('\n');

    return '<div align="center">\n\n'
        '# $title\n\n'
        '*Généré par Corely — $dateStr*\n\n'
        '</div>\n\n'
        '---\n\n'
        '$cleanBody\n\n'
        '---\n\n'
        '## Sources\n\n'
        '$sourceLines\n';
  }

  // ── PDF ─────────────────────────────────────────────────────────────────────

  static final _primaryColor = PdfColor.fromHex('#6C63FF');
  static final _lightBgColor = PdfColor.fromHex('#F3F0FF');

  Future<Uint8List> _toPdf(String title, String body, List<String> sources) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    // Remove duplicated title heading and image-suggestion blocks from the body
    final cleanBody = _cleanBodyForDocgen(_stripLeadingTitle(body, title));
    final sections = _splitSections(cleanBody);

    // Fetch illustrations in parallel
    final coverImageFuture = _fetchIllustration(title);
    final sectionImageFutures = sections.keys.map((s) => _fetchIllustration(s)).toList();
    final coverImage = await coverImageFuture;
    final sectionImages = await Future.wait(sectionImageFutures);

    // ── Cover page ───────────────────────────────────────────────────────────
    doc.addPage(
      pw.Page(
        build: (context) => pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (coverImage != null)
                pw.ClipRRect(
                  horizontalRadius: 12,
                  verticalRadius: 12,
                  child: pw.Image(
                    pw.MemoryImage(coverImage),
                    width: 260,
                    height: 180,
                    fit: pw.BoxFit.cover,
                  ),
                ),
              if (coverImage != null) pw.SizedBox(height: 24),
              pw.Container(
                width: 80,
                height: 80,
                decoration: pw.BoxDecoration(
                  color: _primaryColor,
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Center(
                  child: pw.Text(
                    'C',
                    style: pw.TextStyle(
                      fontSize: 48,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(height: 32),
              pw.Text(
                _normalizePdfText(title),
                style: pw.TextStyle(
                  fontSize: 32,
                  fontWeight: pw.FontWeight.bold,
                  color: _primaryColor,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'Généré par Corely',
                style: pw.TextStyle(fontSize: 14, color: PdfColor.fromInt(0xff757575)),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                dateStr,
                style: pw.TextStyle(fontSize: 12, color: PdfColor.fromInt(0xff757575)),
              ),
            ],
          ),
        ),
      ),
    );

    // ── Content pages ──────────────────────────────────────────────────────
    final contentWidgets = <pw.Widget>[];

    var sectionIdx = 0;
    for (final entry in sections.entries) {
      final secImage = sectionImages[sectionIdx];
      if (secImage != null) {
        contentWidgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            alignment: pw.Alignment.center,
            child: pw.ClipRRect(
              horizontalRadius: 8,
              verticalRadius: 8,
              child: pw.Image(
                pw.MemoryImage(secImage),
                width: 400,
                height: 220,
                fit: pw.BoxFit.cover,
              ),
            ),
          ),
        );
      }
      contentWidgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8, bottom: 6),
          child: pw.Text(
            _normalizePdfText(entry.key),
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: _primaryColor,
            ),
          ),
        ),
      );
      final sectionWidgets = _parseMarkdownToPdfWidgets(entry.value);
      contentWidgets.addAll(_insertInlineImage(sectionWidgets, secImage));
      contentWidgets.add(pw.SizedBox(height: 20));
      sectionIdx++;
    }

    contentWidgets.add(pw.SizedBox(height: 30));
    contentWidgets.add(
      pw.Text(
        'Sources',
        style: pw.TextStyle(
          fontSize: 16,
          fontWeight: pw.FontWeight.bold,
          color: _primaryColor,
        ),
      ),
    );
    contentWidgets.add(pw.SizedBox(height: 12));
    contentWidgets.addAll(_buildSourceWidgets(sources));

    doc.addPage(
      pw.MultiPage(
        header: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(
            _normalizePdfText(title),
            style: pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xff757575)),
          ),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Page ${context.pageNumber} / ${context.pagesCount}  |  $dateStr',
            style: pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xff757575)),
          ),
        ),
        build: (context) => contentWidgets,
      ),
    );

    return Uint8List.fromList(await doc.save());
  }

  /// Removes the duplicated title heading that the LLM often injects at the
  /// very beginning of the body (e.g. "Titre: X" or "# X").
  /// Distribute an inline image at multiple points through a list of PDF widgets
  /// so that every page/section gets visual coverage.
  List<pw.Widget> _insertInlineImage(List<pw.Widget> widgets, Uint8List? image) {
    if (image == null || widgets.length < 3) return widgets;
    final result = List<pw.Widget>.from(widgets);

    // Determine insertion points: 1/3 and 2/3 (and middle for very long sections)
    final positions = <int>[
      result.length ~/ 3,
      if (result.length > 6) 2 * result.length ~/ 3,
    ];

    // Sort descending so indices don't shift during insertions
    positions.sort((a, b) => b.compareTo(a));

    for (final idx in positions) {
      result.insert(
        idx.clamp(1, result.length - 1),
        pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 10),
          alignment: pw.Alignment.center,
          child: pw.ClipRRect(
            horizontalRadius: 8,
            verticalRadius: 8,
            child: pw.Image(
              pw.MemoryImage(image),
              width: 300,
              height: 170,
              fit: pw.BoxFit.cover,
            ),
          ),
        ),
      );
    }
    return result;
  }

  String _stripLeadingTitle(String body, String title) {
    var clean = body.trim();

    // "Titre: ... \n" prefix (case insensitive)
    if (RegExp(r'^Titre\s*:', caseSensitive: false).hasMatch(clean)) {
      final nl = clean.indexOf('\n');
      if (nl != -1) clean = clean.substring(nl + 1).trim();
    }

    // Repeated markdown heading at the very top
    final patterns = ['# $title', '## $title', '### $title'];
    for (final p in patterns) {
      if (clean.startsWith(p)) {
        clean = clean.substring(p.length).trim();
        break;
      }
    }

    return clean;
  }

  /// Strips image-suggestion blocks (Description, Utilité, Image suggérée)
  /// from the document body so they don't leak into visible text output.
  String _cleanBodyForDocgen(String body) {
    final lines = body.split('\n');
    final result = <String>[];
    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      final lowered = line.toLowerCase();
      if (lowered.startsWith('image suggérée') ||
          lowered.startsWith('**image suggérée') ||
          lowered.startsWith('image suggeree') ||
          lowered.startsWith('**image suggeree')) {
        continue;
      }
      if (RegExp(r'^Description\s*:', caseSensitive: false).hasMatch(line) ||
          RegExp(r'^Utilit[ée]\s*:', caseSensitive: false).hasMatch(line)) {
        continue;
      }
      result.add(rawLine);
    }
    return result.join('\n');
  }

  /// Converts markdown-like text into richly-styled PDF widgets.
  List<pw.Widget> _parseMarkdownToPdfWidgets(String text) {
    final widgets = <pw.Widget>[];
    final lines = text.split('\n');

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trimRight();
      if (line.isEmpty) {
        widgets.add(pw.SizedBox(height: 6));
        continue;
      }

      line = _normalizePdfText(line);

      // Horizontal rule
      if (line == '---' || line == '***' || line == '___' || line.startsWith('---')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Divider(color: _primaryColor, thickness: 0.5),
        ));
        continue;
      }

      // Strip image-suggestion and metadata lines from visible output
      final lowered = line.toLowerCase();
      if (lowered.startsWith('image suggérée') || lowered.startsWith('**image suggérée')) continue;
      if (RegExp(r'^Description\s*:', caseSensitive: false).hasMatch(line) ||
          RegExp(r'^Utilit[ée]\s*:', caseSensitive: false).hasMatch(line)) {
        continue;
      }

      // Headings
      if (line.startsWith('#### ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
          child: pw.Text(
            _stripMarkdownMarkers(line.substring(5)),
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _primaryColor,
            ),
          ),
        ));
      } else if (line.startsWith('### ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
          child: pw.Text(
            _stripMarkdownMarkers(line.substring(4)),
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              color: _primaryColor,
            ),
          ),
        ));
      } else if (line.startsWith('## ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 16, bottom: 8),
          child: pw.Text(
            _stripMarkdownMarkers(line.substring(3)),
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: _primaryColor,
            ),
          ),
        ));
      } else if (line.startsWith('# ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 16, bottom: 8),
          child: pw.Text(
            _stripMarkdownMarkers(line.substring(2)),
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: _primaryColor,
            ),
          ),
        ));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        // Bullet list
        final content = line.substring(2).trim();
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 16, bottom: 4),
          child: pw.Bullet(
            text: _stripMarkdownMarkers(content),
            style: pw.TextStyle(fontSize: 11),
            bulletSize: 5,
            bulletColor: _primaryColor,
            bulletMargin: const pw.EdgeInsets.only(right: 8),
          ),
        ));
      } else if (RegExp(r'^(\d+[\.\)]\s+)').hasMatch(line)) {
        // Numbered list
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 16, bottom: 4),
          child: _buildRichParagraph(_stripMarkdownMarkers(line)),
        ));
      } else {
        // Normal paragraph with inline styles
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: _buildRichParagraph(line),
        ));
      }
    }

    return widgets;
  }

  /// Renders a paragraph with inline bold, italic and styled URLs.
  pw.Widget _buildRichParagraph(String text) {
    final spans = <pw.TextSpan>[];
    var cursor = 0;

    // Combined pattern: **bold**, *italic*, URLs
    final pattern = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*|https?://[^\s]+|www\.[^\s]+)');

    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(pw.TextSpan(text: text.substring(cursor, match.start)));
      }

      final m = match.group(0)!;
      if (m.startsWith('**') && m.endsWith('**') && m.length > 4) {
        spans.add(pw.TextSpan(
          text: m.substring(2, m.length - 2),
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ));
      } else if (m.startsWith('*') && m.endsWith('*') && m.length > 2) {
        spans.add(pw.TextSpan(
          text: m.substring(1, m.length - 1),
          style: pw.TextStyle(fontStyle: pw.FontStyle.italic),
        ));
      } else if (m.startsWith('http') || m.startsWith('www.')) {
        final url = m.startsWith('www.') ? 'https://$m' : m;
        spans.add(pw.TextSpan(
          text: m,
          style: pw.TextStyle(
            color: _primaryColor,
            decoration: pw.TextDecoration.underline,
          ),
          annotation: pw.AnnotationUrl(url),
        ));
      } else {
        spans.add(pw.TextSpan(text: m));
      }

      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(pw.TextSpan(text: text.substring(cursor)));
    }
    if (spans.isEmpty) {
      spans.add(pw.TextSpan(text: text));
    }

    return pw.RichText(
      text: pw.TextSpan(children: spans),
      textAlign: pw.TextAlign.justify,
    );
  }

  /// Builds clickable source entries with extracted title + URL.
  /// Decodes DuckDuckGo redirect URLs to show the real destination.
  List<pw.Widget> _buildSourceWidgets(List<String> sources) {
    final widgets = <pw.Widget>[];

    for (var i = 0; i < sources.length; i++) {
      final source = sources[i].trim();
      if (source.isEmpty) continue;

      // Try to separate title from URL
      final urlMatch = RegExp(r'(https?://\S+|//\S+)').firstMatch(source);
      final titlePart = urlMatch != null
          ? source.substring(0, urlMatch.start).trim()
          : source;
      final rawUrl = urlMatch?.group(0);

      if (rawUrl != null) {
        final decoded = _decodeRedirectUrl(rawUrl);
        final url = decoded.startsWith('//') ? 'https:$decoded' : decoded;
        final domain = _extractDomain(url);
        final displayTitle = titlePart.isNotEmpty ? titlePart : domain;

        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${i + 1}. ${_stripMarkdownMarkers(displayTitle)}',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.UrlLink(
                destination: url,
                child: pw.Text(
                  domain,
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: _primaryColor,
                    decoration: pw.TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ));
      } else {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(
            '${i + 1}. ${_stripMarkdownMarkers(titlePart)}',
            style: pw.TextStyle(fontSize: 10),
          ),
        ));
      }
    }

    if (widgets.isEmpty) {
      widgets.add(pw.Text(
        'Aucune source web explicite.',
        style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
      ));
    }

    return widgets;
  }

  /// Decodes DuckDuckGo redirect URLs to extract the real destination.
  /// Input: //duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com&amp;rut=...
  /// Output: https://example.com
  static String _decodeRedirectUrl(String raw) {
    if (!raw.contains('duckduckgo.com/l/?uddg=')) return raw;

    try {
      final uri = Uri.parse(raw.startsWith('http') ? raw : 'https:$raw');
      final uddg = uri.queryParameters['uddg'];
      if (uddg != null && uddg.isNotEmpty) {
        return Uri.decodeFull(uddg);
      }
    } catch (_) {
      // Fallback: manual extraction with regex
      final match = RegExp(r'uddg=([^&]+)').firstMatch(raw);
      if (match != null) {
        try {
          return Uri.decodeFull(match.group(1)!);
        } catch (_) {
          return raw;
        }
      }
    }
    return raw;
  }

  /// Extracts a clean domain name from a full URL.
  static String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      var host = uri.host;
      if (host.startsWith('www.')) host = host.substring(4);
      return host;
    } catch (_) {
      return url;
    }
  }

  /// Removes leading markdown markers (#, ##, **, etc.) from a line.
  String _stripMarkdownMarkers(String line) {
    return line
        .replaceAll(RegExp(r'^[\s\-#\*]+'), '')
        .replaceAll(RegExp(r'^\d+[\.\)]\s+'), '')
        .trim();
  }

  /// Normalizes Unicode characters that the default PDF font (Helvetica)
  /// cannot render. Typographic quotes, dashes and zero-width characters
  /// are replaced by safe ASCII equivalents so they don't silently
  /// disappear from the generated document.
  static String _normalizePdfText(String input) {
    return input
        .replaceAll('’', "'") // right single quotation mark → '
        .replaceAll('‘', "'") // left single quotation mark → '
        .replaceAll('“', '"') // left double quotation mark → "
        .replaceAll('”', '"') // right double quotation mark → "
        .replaceAll('–', '-') // en dash → -
        .replaceAll('—', '--') // em dash → --
        .replaceAll('…', '...') // ellipsis → ...
        .replaceAll(' ', ' ') // non-breaking space
        .replaceAll(' ', ' ') // narrow no-break space
        .replaceAll('­', '') // soft hyphen
        .replaceAll('​', '') // zero width space
        .replaceAll('‌', '') // zero width non-joiner
        .replaceAll('‍', ''); // zero width joiner
  }

  // ── DOCX (real OOXML) ──────────────────────────────────────────────────────

  Future<Uint8List> _toDocx(String title, String body, List<String> sources) async {
    final cleanBody = _cleanBodyForDocgen(_stripLeadingTitle(body, title));
    final sections = _splitSections(cleanBody);
    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    // Fetch illustrations in parallel
    final coverImageFuture = _fetchIllustration(title);
    final sectionImageFutures = sections.keys.map((s) => _fetchIllustration(s)).toList();
    final coverImage = await coverImageFuture;
    final sectionImages = await Future.wait(sectionImageFutures);

    final paragraphs = <String>[];
    final imageParts = <String, List<int>>{};
    final imageRels = <String, String>{};
    final hyperlinkRels = <String, String>{};
    var imageNum = 1;
    var relId = 2; // rId1 is reserved for styles
    var hyperlinkRelId = 50; // Start high to avoid collision with image rIds

    String? registerImage(Uint8List? bytes) {
      if (bytes == null) return null;
      final path = 'word/media/image_$imageNum.jpg';
      imageParts[path] = bytes;
      final rId = 'rId$relId';
      imageRels[rId] = 'media/image_$imageNum.jpg';
      imageNum++;
      relId++;
      return rId;
    }

    String getHyperlinkRelId(String url) {
      for (final entry in hyperlinkRels.entries) {
        if (entry.value == url) return entry.key;
      }
      final rId = 'rId$hyperlinkRelId';
      hyperlinkRelId++;
      hyperlinkRels[rId] = url;
      return rId;
    }

    final coverRid = registerImage(coverImage);

    // Cover page title
    if (coverRid != null) {
      paragraphs.add(_docxImageParagraph(coverRid, 4572000, 3429000));
    }
    paragraphs.add(_docxParagraph(title, bold: true, size: 36, color: '6C63FF', align: 'center', spacingAfter: 200));
    paragraphs.add(_docxParagraph('Généré par Corely', bold: false, size: 14, align: 'center', spacingAfter: 100));
    paragraphs.add(_docxParagraph(dateStr, bold: false, size: 12, align: 'center', spacingAfter: 400));
    paragraphs.add(_docxHorizontalRule());

    var sectionIdx = 0;
    for (final entry in sections.entries) {
      final secRid = registerImage(sectionImages[sectionIdx]);
      paragraphs.add(_docxParagraph(entry.key, bold: true, size: 18, color: '6C63FF', spacingBefore: 240, spacingAfter: 120));

      // Build text paragraphs for this section
      final textParagraphs = <String>[];
      final lines = entry.value.split('\n');
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        if (line.startsWith('---') || line.startsWith('***')) {
          textParagraphs.add(_docxHorizontalRule());
          continue;
        }
        if (RegExp(r'^Description\\s*:', caseSensitive: false).hasMatch(line) ||
            RegExp(r'^Utilit[ée]\\s*:', caseSensitive: false).hasMatch(line)) {
          continue;
        }
        if (line.startsWith('- ') || line.startsWith('* ')) {
          textParagraphs.add(_docxBullet(line.substring(2).trim(), level: 0));
          continue;
        }
        if (line.startsWith('## ')) {
          textParagraphs.add(_docxParagraph(line.substring(3).trim(), bold: true, size: 16, color: '6C63FF', spacingBefore: 200, spacingAfter: 80));
          continue;
        }
        if (line.startsWith('### ')) {
          textParagraphs.add(_docxParagraph(line.substring(4).trim(), bold: true, size: 14, color: '6C63FF', spacingBefore: 160, spacingAfter: 60));
          continue;
        }
        textParagraphs.add(_docxRichParagraph(line));
      }

      // Distribute inline images throughout the section (every ~3 paragraphs)
      if (secRid != null && textParagraphs.isNotEmpty) {
        for (var i = 0; i < textParagraphs.length; i++) {
          paragraphs.add(textParagraphs[i]);
          if ((i + 1) % 3 == 0) {
            paragraphs.add(_docxImageParagraph(secRid, 3200000, 1800000));
          }
        }
      } else {
        paragraphs.addAll(textParagraphs);
      }
      sectionIdx++;
    }

    paragraphs.add(_docxParagraph('', bold: false, size: 11, spacingBefore: 400));
    paragraphs.add(_docxHorizontalRule());
    paragraphs.add(_docxParagraph('Sources', bold: true, size: 16, color: '6C63FF', spacingBefore: 200, spacingAfter: 120));

    for (var i = 0; i < sources.length; i++) {
      final source = sources[i].trim();
      if (source.isEmpty) continue;
      final emDashIdx = source.indexOf(' — ');
      final urlPart = emDashIdx != -1 ? source.substring(emDashIdx + 3).trim() : source;
      final decoded = _decodeRedirectUrl(urlPart);
      final domain = _extractDomain(decoded);
      final linkRid = getHyperlinkRelId(decoded);
      paragraphs.add(_docxHyperlinkParagraph('${i + 1}. $domain', linkRid));
    }
    if (sources.isEmpty) {
      paragraphs.add(_docxParagraph('Aucune source web explicite.', bold: false, size: 11, italic: true));
    }

    final bodyXml = paragraphs.join();

    final documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas" '
        'xmlns:mo="http://schemas.microsoft.com/office/mac/office/2008/5/main" '
        'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" '
        'xmlns:mv="urn:schemas-microsoft-com:mac:vml" '
        'xmlns:o="urn:schemas-microsoft-com:office:office" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math" '
        'xmlns:v="urn:schemas-microsoft-com:vml" '
        'xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:w10="urn:schemas-microsoft-com:office:word" '
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" '
        'xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup" '
        'xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk" '
        'xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml" '
        'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>$bodyXml<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>'
        '</w:sectPr></w:body></w:document>';

    final relsXml = _docxDocumentRels(imageRels: imageRels, hyperlinkRels: hyperlinkRels);

    return _createOoxmlZip(
      contentTypes: _docxContentTypes(hasImages: imageParts.isNotEmpty),
      rels: _docxRels(),
      partFiles: {
        'word/document.xml': utf8.encode(documentXml),
        'word/_rels/document.xml.rels': utf8.encode(relsXml),
        'word/styles.xml': utf8.encode(_docxStyles()),
        ...imageParts,
      },
    );
  }

  String _docxParagraph(
    String text, {
    required bool bold,
    required int size,
    String? color,
    String? align,
    int spacingBefore = 0,
    int spacingAfter = 0,
    bool italic = false,
  }) {
    final escaped = _xmlEscape(text);
    final boldAttr = bold ? ' w:b="1"' : '';
    final italicAttr = italic ? ' w:i="1"' : '';
    final colorAttr = color != null ? ' w:color="$color"' : '';
    final alignAttr = align != null ? '<w:jc w:val="$align"/>' : '';
    final spacingAttr = (spacingBefore > 0 || spacingAfter > 0)
        ? '<w:spacing w:before="$spacingBefore" w:after="$spacingAfter"/>'
        : '';
    return '<w:p><w:pPr>$alignAttr$spacingAttr<w:rPr><w:sz w:val="${size * 2}"/>$boldAttr$italicAttr$colorAttr</w:rPr></w:pPr>'
        '<w:r><w:rPr><w:sz w:val="${size * 2}"/>$boldAttr$italicAttr$colorAttr</w:rPr>'
        '<w:t xml:space="preserve">$escaped</w:t></w:r></w:p>';
  }

  String _docxBullet(String text, {required int level}) {
    final escaped = _xmlEscape(text);
    return '<w:p><w:pPr><w:pStyle w:val="ListParagraph"/><w:numPr><w:ilvl w:val="$level"/><w:numId w:val="1"/></w:numPr></w:pPr>'
        '<w:r><w:t xml:space="preserve">$escaped</w:t></w:r></w:p>';
  }

  String _docxHorizontalRule() {
    return '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="6C63FF"/></w:pBdr></w:pPr></w:p>';
  }

  String _docxRichParagraph(String text) {
    final spans = StringBuffer();
    var cursor = 0;
    final pattern = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*)');
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.write('<w:r><w:t xml:space="preserve">${_xmlEscape(text.substring(cursor, match.start))}</w:t></w:r>');
      }
      final m = match.group(0)!;
      if (m.startsWith('**') && m.endsWith('**') && m.length > 4) {
        spans.write('<w:r><w:rPr><w:b/><w:sz w:val="22"/></w:rPr><w:t xml:space="preserve">${_xmlEscape(m.substring(2, m.length - 2))}</w:t></w:r>');
      } else if (m.startsWith('*') && m.endsWith('*') && m.length > 2) {
        spans.write('<w:r><w:rPr><w:i/><w:sz w:val="22"/></w:rPr><w:t xml:space="preserve">${_xmlEscape(m.substring(1, m.length - 1))}</w:t></w:r>');
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.write('<w:r><w:t xml:space="preserve">${_xmlEscape(text.substring(cursor))}</w:t></w:r>');
    }
    if (spans.isEmpty) {
      spans.write('<w:r><w:t xml:space="preserve">${_xmlEscape(text)}</w:t></w:r>');
    }
    return '<w:p><w:pPr><w:rPr><w:sz w:val="22"/></w:rPr></w:pPr>$spans</w:p>';
  }

  String _docxHyperlinkParagraph(String text, String rId) {
    final escaped = _xmlEscape(text);
    return '<w:p><w:hyperlink r:id="$rId"><w:r><w:rPr><w:color w:val="6C63FF"/><w:u w:val="single"/></w:rPr><w:t xml:space="preserve">$escaped</w:t></w:r></w:hyperlink></w:p>';
  }

  String _docxContentTypes({bool hasImages = false}) {
    final imageDefaults = hasImages
        ? '<Default Extension="jpg" ContentType="image/jpeg"/><Default Extension="png" ContentType="image/png"/>'
        : '';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '$imageDefaults'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '</Types>';
  }

  String _docxRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>';
  }

  String _docxDocumentRels({Map<String, String> imageRels = const {}, Map<String, String> hyperlinkRels = const {}}) {
    final imageRelsXml = imageRels.entries.map((e) {
      return '<Relationship Id="${e.key}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="${e.value}"/>';
    }).join();
    final hyperlinkRelsXml = hyperlinkRels.entries.map((e) {
      return '<Relationship Id="${e.key}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="${_xmlEscape(e.value)}" TargetMode="External"/>';
    }).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '$imageRelsXml'
        '$hyperlinkRelsXml</Relationships>';
  }

  String _docxTwoColumnTable(String imageRid, String textXml) {
    // 2-column table: 55% text (left) | 45% image (right)
    return '<w:tbl>'
        '<w:tblPr><w:tblW w:w="5000" w:type="pct"/>'
        '<w:tblBorders><w:top w:val="none"/><w:left w:val="none"/><w:bottom w:val="none"/><w:right w:val="none"/><w:insideH w:val="none"/><w:insideV w:val="none"/></w:tblBorders>'
        '<w:tblCellMar><w:top w:w="72" w:type="dxa"/><w:left w:w="72" w:type="dxa"/><w:bottom w:w="72" w:type="dxa"/><w:right w:w="72" w:type="dxa"/></w:tblCellMar>'
        '</w:tblPr>'
        '<w:tblGrid><w:gridCol w:w="5490"/><w:gridCol w:w="5490"/></w:tblGrid>'
        '<w:tr>'
        '<w:trPr><w:trHeight w:hRule="atLeast" w:val="400"/></w:trPr>'
        // Left cell: text
        '<w:tc><w:tcPr><w:tcW w:w="5490" w:type="dxa"/><w:vAlign w:val="top"/></w:tcPr>'
        '$textXml</w:tc>'
        // Right cell: image
        '<w:tc><w:tcPr><w:tcW w:w="5490" w:type="dxa"/><w:vAlign w:val="top"/></w:tcPr>'
        '<w:p><w:r><w:drawing>'
        '<wp:inline xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="3200000" cy="2400000"/>'
        '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:docPr id="1" name="Illustration"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr>'
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:nvPicPr><pic:cNvPr id="0" name="image.jpg"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$imageRid"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="3200000" cy="2400000"/></a:xfrm><a:prstGeom prst="rect"/></pic:spPr>'
        '</pic:pic>'
        '</a:graphicData>'
        '</a:graphic>'
        '</wp:inline>'
        '</w:drawing></w:r></w:p>'
        '</w:tc>'
        '</w:tr></w:tbl>';
  }

  String _docxImageParagraph(String rId, int widthEmu, int heightEmu) {
    return '<w:p><w:r><w:drawing>'
        '<wp:inline xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$widthEmu" cy="$heightEmu"/>'
        '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:docPr id="1" name="Picture 1"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr>'
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:nvPicPr><pic:cNvPr id="0" name="image.jpg"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$rId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$widthEmu" cy="$heightEmu"/></a:xfrm><a:prstGeom prst="rect"/></pic:spPr>'
        '</pic:pic>'
        '</a:graphicData>'
        '</a:graphic>'
        '</wp:inline>'
        '</w:drawing></w:r></w:p>';
  }

  String _docxStyles() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>'
        '</w:styles>';
  }

  // ── PPTX (real OOXML) ──────────────────────────────────────────────────────

  Future<Uint8List> _toPptx(String title, String body, List<String> sources) async {
    final cleanBody = _stripLeadingTitle(body, title);
    final sections = _splitPptxSections(cleanBody);
    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    // Identify special sections
    _PptxSection? tocSection;
    _PptxSection? introSection;
    _PptxSection? conclusionSection;
    final contentSections = <_PptxSection>[];

    for (final section in sections) {
      final lower = section.title.toLowerCase().trim();
      if (lower == 'titre' || lower.startsWith('titre :')) {
        // Skip LLM-generated duplicate title section — cover already shows the title
        continue;
      } else if (lower.contains('sommaire') || lower.contains('table des matières') || lower.contains('table des matieres')) {
        tocSection = section;
      } else if (lower.contains('introduction')) {
        introSection = section;
      } else if (lower.contains('conclusion') || lower.contains('plan d\'action') || lower.contains('plan dactions')) {
        conclusionSection = section;
      } else if (lower.contains('source') ||
          lower.contains('référence') ||
          lower.contains('reference') ||
          lower.contains('bibliographie')) {
        // Skip LLM-generated sources sections — sources are rendered on a dedicated slide
        continue;
      } else {
        contentSections.add(section);
      }
    }

    // Pre-generate images in parallel
    final coverImageFuture = _fetchIllustration(title);
    final imageFutures = <Future<Uint8List?>>[];
    for (final section in contentSections) {
      final prompt = section.imageDescription?.isNotEmpty == true
          ? section.imageDescription!
          : section.title;
      imageFutures.add(_fetchIllustration(prompt));
    }
    final coverImage = await coverImageFuture;
    final sectionImages = await Future.wait(imageFutures);

    final slideXmls = <String, List<int>>{};
    final slideRelsXmls = <String, List<int>>{};
    final relTargets = <String>[];
    final partFiles = <String, List<int>>{};
    var slideNum = 1;
    var imageNum = 1;
    var nextRelId = 10; // Reserve rId1-9 for standard rels

    // ── Cover slide ─────────────────────────────────────────────────────────────
    final coverFileName = 'ppt/slides/slide$slideNum.xml';
    final coverRelFileName = 'ppt/slides/_rels/slide$slideNum.xml.rels';
    String? coverImagePath;
    if (coverImage != null) {
      coverImagePath = 'ppt/media/image_$imageNum.jpg';
      partFiles[coverImagePath] = coverImage;
      imageNum++;
    }
    slideXmls[coverFileName] = utf8.encode(_pptxCoverSlideXml(
      title,
      dateStr,
      backgroundRid: coverImagePath != null ? 'rId2' : null,
      hasBgRect: coverImagePath != null,
    ));
    slideRelsXmls[coverRelFileName] = utf8.encode(_pptxSlideRelsXml(
      imagePath: coverImagePath != null ? '../media/image_${imageNum - 1}.jpg' : null,
    ));
    relTargets.add('<Relationship Id="rId$slideNum" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$slideNum.xml"/>');
    slideNum++;

    // ── Table of Contents slide ─────────────────────────────────────────────────
    if (tocSection != null || contentSections.isNotEmpty) {
      final tocItems = contentSections.map((s) => s.title).toList();
      if (introSection != null) tocItems.insert(0, introSection.title);
      if (conclusionSection != null) tocItems.add(conclusionSection.title);
      final tocFileName = 'ppt/slides/slide$slideNum.xml';
      final tocRelFileName = 'ppt/slides/_rels/slide$slideNum.xml.rels';
      slideXmls[tocFileName] = utf8.encode(_pptxTocSlideXml('Sommaire', tocItems));
      slideRelsXmls[tocRelFileName] = utf8.encode(_pptxSlideRelsXml());
      relTargets.add('<Relationship Id="rId$slideNum" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$slideNum.xml"/>');
      slideNum++;
    }

    // ── Introduction slide ─────────────────────────────────────────────────────
    if (introSection != null) {
      final introFileName = 'ppt/slides/slide$slideNum.xml';
      final introRelFileName = 'ppt/slides/_rels/slide$slideNum.xml.rels';
      slideXmls[introFileName] = utf8.encode(_pptxContentSlideXml(
        introSection.title,
        introSection.content,
      ));
      slideRelsXmls[introRelFileName] = utf8.encode(_pptxSlideRelsXml());
      relTargets.add('<Relationship Id="rId$slideNum" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$slideNum.xml"/>');
      slideNum++;
    }

    // ── Content slides (two-column: text + image on every slide) ───────────────
    var sectionIdx = 0;
    for (final section in contentSections) {
      final image = sectionImages[sectionIdx];
      String? imagePath;
      if (image != null) {
        imagePath = 'ppt/media/image_$imageNum.jpg';
        partFiles[imagePath] = image;
        imageNum++;
      }
      // Two-column slide: text left + illustration right
      final textFileName = 'ppt/slides/slide$slideNum.xml';
      final textRelFileName = 'ppt/slides/_rels/slide$slideNum.xml.rels';
      slideXmls[textFileName] = utf8.encode(_pptxTwoColumnSlideXml(
        section.title,
        section.content,
        imageRid: imagePath != null ? 'rId2' : null,
        hasImage: imagePath != null,
      ));
      slideRelsXmls[textRelFileName] = utf8.encode(_pptxSlideRelsXml(
        imagePath: imagePath != null ? '../media/image_${imageNum - 1}.jpg' : null,
      ));
      relTargets.add('<Relationship Id="rId$slideNum" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$slideNum.xml"/>');
      slideNum++;

      // Full-page image slide (kept for visual impact)
      if (image != null) {
        final fullImageFileName = 'ppt/slides/slide$slideNum.xml';
        final fullImageRelFileName = 'ppt/slides/_rels/slide$slideNum.xml.rels';
        slideXmls[fullImageFileName] = utf8.encode(_pptxFullImageSlideXml(
          'Illustration : ${section.title}',
          imageRid: 'rId2',
        ));
        slideRelsXmls[fullImageRelFileName] = utf8.encode(_pptxSlideRelsXml(
          imagePath: '../media/image_${imageNum - 1}.jpg',
        ));
        relTargets.add('<Relationship Id="rId$slideNum" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$slideNum.xml"/>');
        slideNum++;
      }
      sectionIdx++;
    }

    // ── Conclusion slide ────────────────────────────────────────────────────────
    if (conclusionSection != null) {
      final conclusionFileName = 'ppt/slides/slide$slideNum.xml';
      final conclusionRelFileName = 'ppt/slides/_rels/slide$slideNum.xml.rels';
      slideXmls[conclusionFileName] = utf8.encode(_pptxContentSlideXml(
        conclusionSection.title,
        conclusionSection.content,
      ));
      slideRelsXmls[conclusionRelFileName] = utf8.encode(_pptxSlideRelsXml());
      relTargets.add('<Relationship Id="rId$slideNum" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$slideNum.xml"/>');
      slideNum++;
    }

    // ── Sources slide with hyperlinks ───────────────────────────────────────────
    final sourcesFileName = 'ppt/slides/slide$slideNum.xml';
    final sourcesRelFileName = 'ppt/slides/_rels/slide$slideNum.xml.rels';
    final sourceLinks = <_SourceLink>[];
    for (final s in sources) {
      // Extract URL part from "Title — URL" format before decoding
      final emDashIdx = s.indexOf(' — ');
      final urlPart = emDashIdx != -1 ? s.substring(emDashIdx + 3).trim() : s;
      final decoded = _decodeRedirectUrl(urlPart);
      final titlePart = emDashIdx != -1 ? s.substring(0, emDashIdx).trim() : '';
      final domain = _extractDomain(decoded);
      final displayText = titlePart.isNotEmpty ? titlePart : domain;
      sourceLinks.add(_SourceLink(text: displayText, url: decoded));
    }
    final sourceHyperlinkRels = <String, String>{};
    for (var i = 0; i < sourceLinks.length; i++) {
      sourceHyperlinkRels['rId${nextRelId + i}'] = sourceLinks[i].url;
    }
    slideXmls[sourcesFileName] = utf8.encode(_pptxSourcesSlideXmlWithLinks(sourceLinks, nextRelId));
    slideRelsXmls[sourcesRelFileName] = utf8.encode(_pptxSlideRelsXmlWithHyperlinks(sourceHyperlinkRels));
    relTargets.add('<Relationship Id="rId$slideNum" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$slideNum.xml"/>');
    slideNum++;

    final totalSlides = slideNum - 1;
    partFiles['ppt/presentation.xml'] = utf8.encode(_pptxPresentationXml(totalSlides));
    partFiles['ppt/_rels/presentation.xml.rels'] = utf8.encode(_pptxPresentationRelsXml(totalSlides));
    for (final entry in slideXmls.entries) {
      partFiles[entry.key] = entry.value;
    }
    for (final entry in slideRelsXmls.entries) {
      partFiles[entry.key] = entry.value;
    }

    return _createOoxmlZip(
      contentTypes: _pptxContentTypes(totalSlides, hasImages: imageNum > 1),
      rels: _pptxRels(),
      partFiles: partFiles,
    );
  }

  String _pptxCoverSlideXml(
    String title,
    String date, {
    String? backgroundRid,
    bool hasBgRect = false,
  }) {
    final escapedTitle = _xmlEscape(title);
    final bgXml = backgroundRid != null
        ? '<p:bg><p:bgPr><a:blipFill rotWithShape="1"><a:blip r:embed="$backgroundRid"/><a:stretch><a:fillRect/></a:stretch></a:blipFill><a:effectLst/></p:bgPr></p:bg>'
        : '';
    final bgRectXml = hasBgRect
        ? '<p:sp><p:nvSpPr><p:cNvPr id="5" name="BgRect"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="9144000" cy="6858000"/></a:xfrm><a:prstGeom prst="rect"/><a:solidFill><a:srgbClr val="FFFFFF"><a:alpha val="50000"/></a:srgbClr></a:solidFill></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/></p:txBody></p:sp>'
        : '';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld>$bgXml<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/>'
        '<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '$bgRectXml'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="1600200"/>'
        '<a:ext cx="8229600" cy="1143000"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:pPr><a:fontAlgn b="1"/></a:pPr>'
        '<a:r><a:rPr lang="fr-FR" sz="3600" b="1">'
        '<a:solidFill><a:srgbClr val="6C63FF"/></a:solidFill>'
        '</a:rPr><a:t>$escapedTitle</a:t></a:r></a:p></p:txBody></p:sp>'
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Subtitle"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="3000000"/>'
        '<a:ext cx="8229600" cy="457200"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:pPr><a:fontAlgn b="1"/></a:pPr>'
        '<a:r><a:rPr lang="fr-FR" sz="1800">'
        '<a:solidFill><a:srgbClr val="757575"/></a:solidFill>'
        '</a:rPr><a:t>Généré par Corely</a:t></a:r></a:p></p:txBody></p:sp>'
        '<p:sp><p:nvSpPr><p:cNvPr id="4" name="Date"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="3500000"/>'
        '<a:ext cx="8229600" cy="457200"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:pPr><a:fontAlgn b="1"/></a:pPr>'
        '<a:r><a:rPr lang="fr-FR" sz="1400">'
        '<a:solidFill><a:srgbClr val="999999"/></a:solidFill>'
        '</a:rPr><a:t>$date</a:t></a:r></a:p></p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
        '<p:transition spd="slow" advClick="1" advTm="5000"><p:fade/></p:transition>'
        '<p:timing><p:tnLst><p:par><p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot"/><p:childTnLst><p:seq concurrent="1" nextAc="seek"><p:cTn id="2" dur="indefinite" nodeType="mainSeq"/><p:childTnLst><p:par><p:cTn id="3" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst></p:cTn><p:childTnLst><p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="4" dur="1000" fill="hold"/><p:tgtEl><p:spTgt spid="2"/></p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:par><p:par><p:cTn id="5" fill="hold"><p:stCondLst><p:cond delay="400"/></p:stCondLst></p:cTn><p:childTnLst><p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="6" dur="1000" fill="hold"/><p:tgtEl><p:spTgt spid="3"/></p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:par><p:par><p:cTn id="7" fill="hold"><p:stCondLst><p:cond delay="800"/></p:stCondLst></p:cTn><p:childTnLst><p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="8" dur="1000" fill="hold"/><p:tgtEl><p:spTgt spid="4"/></p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:par></p:childTnLst></p:seq></p:childTnLst></p:par></p:tnLst></p:timing></p:sld>';
  }

  String _pptxContentSlideXml(
    String title,
    String content, {
    String? backgroundRid,
    bool hasBgRect = false,
  }) {
    // Strip "DIAPOSITIVE X –" prefix if present
    var cleanTitle = title;
    cleanTitle = cleanTitle.replaceFirst(
      RegExp(r'^DIAPOSITIVE\s+\d+\s*[-–—]\s*', caseSensitive: false),
      '',
    );
    final escapedTitle = _xmlEscape(cleanTitle);
    final paragraphsXml = _pptxContentParagraphs(content);
    final bgXml = backgroundRid != null
        ? '<p:bg><p:bgPr><a:blipFill rotWithShape="1"><a:blip r:embed="$backgroundRid"/><a:stretch><a:fillRect/></a:stretch></a:blipFill><a:effectLst/></p:bgPr></p:bg>'
        : '';
    final bgRectXml = hasBgRect
        ? '<p:sp><p:nvSpPr><p:cNvPr id="5" name="BgRect"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="9144000" cy="6858000"/></a:xfrm><a:prstGeom prst="rect"/><a:solidFill><a:srgbClr val="FFFFFF"><a:alpha val="55000"/></a:srgbClr></a:solidFill></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/></p:txBody></p:sp>'
        : '';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld>$bgXml<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/>'
        '<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '$bgRectXml'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="274630"/>'
        '<a:ext cx="8229600" cy="800000"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:r><a:rPr lang="fr-FR" sz="2400" b="1">'
        '<a:solidFill><a:srgbClr val="6C63FF"/></a:solidFill>'
        '</a:rPr><a:t>$escapedTitle</a:t></a:r></a:p></p:txBody></p:sp>'
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Content"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="1200000"/>'
        '<a:ext cx="8229600" cy="5000000"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '$paragraphsXml</p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
        '<p:transition spd="slow" advClick="1" advTm="5000"><p:fade/></p:transition>'
        '<p:timing><p:tnLst><p:par><p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot"/><p:childTnLst><p:seq concurrent="1" nextAc="seek"><p:cTn id="2" dur="indefinite" nodeType="mainSeq"/><p:childTnLst><p:par><p:cTn id="3" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst></p:cTn><p:childTnLst><p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="4" dur="1000" fill="hold"/><p:tgtEl><p:spTgt spid="2"/></p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:par><p:par><p:cTn id="5" fill="hold"><p:stCondLst><p:cond delay="300"/></p:stCondLst></p:cTn><p:childTnLst><p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="6" dur="1000" fill="hold"/><p:tgtEl><p:spTgt spid="3"/></p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:par></p:childTnLst></p:seq></p:childTnLst></p:par></p:tnLst></p:timing></p:sld>';
  }

  String _pptxTwoColumnSlideXml(
    String title,
    String content, {
    String? imageRid,
    bool hasImage = false,
  }) {
    // Strip "DIAPOSITIVE X –" prefix if present
    var cleanTitle = title;
    cleanTitle = cleanTitle.replaceFirst(
      RegExp(r'^DIAPOSITIVE\s+\d+\s*[-–—]\s*', caseSensitive: false),
      '',
    );
    final escapedTitle = _xmlEscape(cleanTitle);
    final paragraphsXml = _pptxContentParagraphs(content);
    final leftColWidth = hasImage ? 4572000 : 8229600;
    final rightColX = hasImage ? 5029200 : 0;
    final rightColWidth = hasImage ? 3657600 : 0;

    // Image shape on the right
    final imageShapeXml = hasImage
        ? '<p:sp><p:nvSpPr><p:cNvPr id="5" name="ImageShape"/><p:cNvSpPr><a:spLocks noGrp="1" noSelect="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="$rightColX" y="1200000"/><a:ext cx="$rightColWidth" cy="5000000"/></a:xfrm><a:prstGeom prst="rect"/></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/></p:txBody></p:sp><p:pic><p:nvPicPr><p:cNvPr id="6" name="Illustration"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr></p:nvPicPr><p:blipFill><a:blip r:embed="$imageRid"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x="$rightColX" y="1200000"/><a:ext cx="$rightColWidth" cy="3429000"/></a:xfrm><a:prstGeom prst="rect"/></p:spPr></p:pic>'
        : '';

    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/>'
        '<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="274630"/>'
        '<a:ext cx="8229600" cy="800000"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:r><a:rPr lang="fr-FR" sz="2400" b="1">'
        '<a:solidFill><a:srgbClr val="6C63FF"/></a:solidFill>'
        '</a:rPr><a:t>$escapedTitle</a:t></a:r></a:p></p:txBody></p:sp>'
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Content"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="1200000"/>'
        '<a:ext cx="$leftColWidth" cy="5000000"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '$paragraphsXml</p:txBody></p:sp>'
        '$imageShapeXml'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
        '<p:transition spd="slow" advClick="1" advTm="5000"><p:fade/></p:transition>'
        '<p:timing><p:tnLst><p:par><p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot"/><p:childTnLst><p:seq concurrent="1" nextAc="seek"><p:cTn id="2" dur="indefinite" nodeType="mainSeq"/><p:childTnLst><p:par><p:cTn id="3" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst></p:cTn><p:childTnLst><p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="4" dur="1000" fill="hold"/><p:tgtEl><p:spTgt spid="2"/></p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:par><p:par><p:cTn id="5" fill="hold"><p:stCondLst><p:cond delay="300"/></p:stCondLst></p:cTn><p:childTnLst><p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="6" dur="1000" fill="hold"/><p:tgtEl><p:spTgt spid="3"/></p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:par></p:childTnLst></p:seq></p:childTnLst></p:par></p:tnLst></p:timing></p:sld>';
  }

  String _pptxSourcesSlideXml(String sourceText) {
    final paragraphsXml = _pptxContentParagraphs(sourceText);
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/>'
        '<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="274630"/>'
        '<a:ext cx="8229600" cy="800000"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:r><a:rPr lang="fr-FR" sz="2400" b="1">'
        '<a:solidFill><a:srgbClr val="6C63FF"/></a:solidFill>'
        '</a:rPr><a:t>Sources</a:t></a:r></a:p></p:txBody></p:sp>'
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Content"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="1200000"/>'
        '<a:ext cx="8229600" cy="5000000"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '$paragraphsXml</p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
        '<p:transition spd="slow" advClick="1" advTm="5000"><p:fade/></p:transition>'
        '<p:timing><p:tnLst><p:par><p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot"/><p:childTnLst><p:seq concurrent="1" nextAc="seek"><p:cTn id="2" dur="indefinite" nodeType="mainSeq"/><p:childTnLst><p:par><p:cTn id="3" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst></p:cTn><p:childTnLst><p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="4" dur="1000" fill="hold"/><p:tgtEl><p:spTgt spid="2"/></p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:par><p:par><p:cTn id="5" fill="hold"><p:stCondLst><p:cond delay="300"/></p:stCondLst></p:cTn><p:childTnLst><p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="6" dur="1000" fill="hold"/><p:tgtEl><p:spTgt spid="3"/></p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:par></p:childTnLst></p:seq></p:childTnLst></p:par></p:tnLst></p:timing></p:sld>';
  }

  /// Splits PPTX body into ordered sections, extracting image suggestions.
  List<_PptxSection> _splitPptxSections(String body) {
    final sections = <_PptxSection>[];
    final lines = body.split('\n');

    String? currentTitle;
    final currentContent = StringBuffer();
    String? currentImageDesc;

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        if (currentTitle != null) currentContent.writeln();
        continue;
      }

      // Detect heading (#, ##, ###)
      final headingMatch = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(line);
      if (headingMatch != null) {
        // Save previous section
        if (currentTitle != null) {
          sections.add(_PptxSection(
            title: currentTitle,
            content: currentContent.toString().trim(),
            imageDescription: currentImageDesc,
          ));
        }
        currentTitle = headingMatch.group(2)!.trim();
        currentContent.clear();
        currentImageDesc = null;
        continue;
      }

      // Detect image suggestion block (explicit "Image suggérée" marker)
      final lowered = line.toLowerCase();
      if (lowered.startsWith('image suggérée') ||
          lowered.startsWith('**image suggérée') ||
          lowered.startsWith('image suggeree') ||
          lowered.startsWith('**image suggeree')) {
        // Try to parse Description : ... Utilite : ...
        final descMatch = RegExp(
          r'Description\s*:\s*(.+?)(?:\s*Utilit[ée]\s*:\s*(.+))?',
          caseSensitive: false,
        ).firstMatch(line);
        if (descMatch != null) {
          currentImageDesc = descMatch.group(1)!.trim();
          if (descMatch.group(2) != null) {
            currentImageDesc = '$currentImageDesc. ${descMatch.group(2)!.trim()}';
          }
        } else {
          // Fallback: extract everything after the marker
          final markerIdx = lowered.indexOf('image suggérée');
          final fallback = markerIdx != -1
              ? line.substring(markerIdx + 'image suggérée'.length).trim()
              : line;
          currentImageDesc = _stripMarkdownMarkers(fallback);
        }
        continue;
      }

      // Detect standalone Description / Utilité lines (LLM often skips "Image suggérée")
      final descStandalone = RegExp(
        r'^Description\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (descStandalone != null) {
        currentImageDesc = descStandalone.group(1)!.trim();
        continue;
      }

      final utilStandalone = RegExp(
        r'^Utilit[ée]\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (utilStandalone != null) {
        final utilText = utilStandalone.group(1)!.trim();
        currentImageDesc = currentImageDesc != null
            ? '$currentImageDesc. $utilText'
            : utilText;
        continue;
      }

      if (currentTitle != null) {
        currentContent.writeln(line);
      }
    }

    // Save last section
    if (currentTitle != null) {
      sections.add(_PptxSection(
        title: currentTitle,
        content: currentContent.toString().trim(),
        imageDescription: currentImageDesc,
      ));
    }

    return sections;
  }

  // ── PPTX slide XML helpers ──────────────────────────────────────────────────

  String _pptxTocSlideXml(String title, List<String> items) {
    final escapedTitle = _xmlEscape(title);
    final itemsXml = items.asMap().entries.map((e) {
      final text = _xmlEscape('${e.key + 1}. ${e.value}');
      return '<a:p><a:pPr><a:buChar char="•"/></a:pPr><a:r><a:rPr lang="fr-FR" sz="1600"/><a:t>$text</a:t></a:r></a:p>';
    }).join();

    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/>'
        '<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="274630"/>'
        '<a:ext cx="8229600" cy="800000"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:r><a:rPr lang="fr-FR" sz="2400" b="1">'
        '<a:solidFill><a:srgbClr val="6C63FF"/></a:solidFill>'
        '</a:rPr><a:t>$escapedTitle</a:t></a:r></a:p></p:txBody></p:sp>'
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Content"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="1200000"/>'
        '<a:ext cx="8229600" cy="5000000"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '$itemsXml</p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
        '<p:transition spd="slow" advClick="1" advTm="5000"><p:fade/></p:transition>'
        '<p:timing><p:tnLst><p:par><p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot"/><p:childTnLst><p:seq concurrent="1" nextAc="seek"><p:cTn id="2" dur="indefinite" nodeType="mainSeq"/><p:childTnLst><p:par><p:cTn id="3" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst></p:cTn><p:childTnLst><p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="4" dur="1000" fill="hold"/><p:tgtEl><p:spTgt spid="2"/></p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:par><p:par><p:cTn id="5" fill="hold"><p:stCondLst><p:cond delay="300"/></p:stCondLst></p:cTn><p:childTnLst><p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="6" dur="1000" fill="hold"/><p:tgtEl><p:spTgt spid="3"/></p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:par></p:childTnLst></p:seq></p:childTnLst></p:par></p:tnLst></p:timing></p:sld>';
  }

  String _pptxFullImageSlideXml(String caption, {required String imageRid}) {
    final escapedCaption = _xmlEscape(caption);
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:bg><p:bgPr><a:blipFill rotWithShape="1"><a:blip r:embed="$imageRid"/><a:stretch><a:fillRect/></a:stretch></a:blipFill><a:effectLst/></p:bgPr></p:bg>'
        '<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/>'
        '<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Caption"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="6000000"/>'
        '<a:ext cx="8229600" cy="600000"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:pPr><a:fontAlgn b="1"/></a:pPr>'
        '<a:r><a:rPr lang="fr-FR" sz="1200" i="1">'
        '<a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill>'
        '</a:rPr><a:t>$escapedCaption</a:t></a:r></a:p></p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
        '<p:transition spd="slow" advClick="1" advTm="5000"><p:fade/></p:transition></p:sld>';
  }

  String _pptxSourcesSlideXmlWithLinks(List<_SourceLink> links, int baseRelId) {
    final paragraphs = <String>[];
    for (var i = 0; i < links.length; i++) {
      final text = _xmlEscape(links[i].text);
      final relId = 'rId${baseRelId + i}';
      paragraphs.add(
        '<a:p><a:r><a:rPr lang="fr-FR" sz="1400">'
        '<a:solidFill><a:srgbClr val="6C63FF"/></a:solidFill>'
        '<a:hlink r:id="$relId"/>'
        '</a:rPr><a:t>$text</a:t></a:r></a:p>',
      );
    }
    if (paragraphs.isEmpty) {
      paragraphs.add('<a:p><a:r><a:rPr lang="fr-FR" sz="1400"/><a:t>Aucune source web explicite.</a:t></a:r></a:p>');
    }

    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/>'
        '<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="274630"/>'
        '<a:ext cx="8229600" cy="800000"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:r><a:rPr lang="fr-FR" sz="2400" b="1">'
        '<a:solidFill><a:srgbClr val="6C63FF"/></a:solidFill>'
        '</a:rPr><a:t>Sources</a:t></a:r></a:p></p:txBody></p:sp>'
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Content"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="1200000"/>'
        '<a:ext cx="8229600" cy="5000000"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '${paragraphs.join()}</p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
        '<p:transition spd="slow" advClick="1" advTm="5000"><p:fade/></p:transition>'
        '<p:timing><p:tnLst><p:par><p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot"/><p:childTnLst><p:seq concurrent="1" nextAc="seek"><p:cTn id="2" dur="indefinite" nodeType="mainSeq"/><p:childTnLst><p:par><p:cTn id="3" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst></p:cTn><p:childTnLst><p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="4" dur="1000" fill="hold"/><p:tgtEl><p:spTgt spid="2"/></p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:par><p:par><p:cTn id="5" fill="hold"><p:stCondLst><p:cond delay="300"/></p:stCondLst></p:cTn><p:childTnLst><p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="6" dur="1000" fill="hold"/><p:tgtEl><p:spTgt spid="3"/></p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:par></p:childTnLst></p:seq></p:childTnLst></p:par></p:tnLst></p:timing></p:sld>';
  }

  String _pptxSlideRelsXmlWithHyperlinks(Map<String, String> hyperlinkRels) {
    final hyperlinksXml = hyperlinkRels.entries.map((e) {
      return '<Relationship Id="${e.key}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="${_xmlEscape(e.value)}" TargetMode="External"/>';
    }).join();

    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
        '$hyperlinksXml</Relationships>';
  }

  String _pptxContentParagraphs(String content) {
    final lines = content.split('\n');
    final paragraphs = <String>[];

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;
      if (line.startsWith('---') || line.startsWith('***')) continue;

      // Strip image suggestion blocks from visible content
      final lowered = line.toLowerCase();
      if (lowered.startsWith('image suggérée') ||
          lowered.startsWith('**image suggérée') ||
          lowered.startsWith('image suggeree') ||
          lowered.startsWith('**image suggeree')) {
        continue;
      }

      // Strip standalone Description / Utilité lines
      if (RegExp(r'^Description\s*:\s*', caseSensitive: false).hasMatch(line) ||
          RegExp(r'^Utilit[ée]\s*:\s*', caseSensitive: false).hasMatch(line)) {
        continue;
      }

      // Paragraph spacing for readability
      const spacingXml = '<a:spcBef><a:spcPts val="120"/></a:spcBef>';

      if (line.startsWith('- ') || line.startsWith('* ')) {
        final text = _xmlEscape(line.substring(2).trim());
        paragraphs.add(
          '<a:p><a:pPr><a:buChar char="•"/>$spacingXml</a:pPr>'
          '<a:r><a:rPr lang="fr-FR" sz="1400"/><a:t>$text</a:t></a:r></a:p>',
        );
      } else if (line.startsWith('### ')) {
        final text = _xmlEscape(_stripMarkdownMarkers(line));
        paragraphs.add(
          '<a:p><a:pPr><a:buChar char="▸"/>$spacingXml</a:pPr>'
          '<a:r><a:rPr lang="fr-FR" sz="1600" b="1">'
          '<a:solidFill><a:srgbClr val="6C63FF"/></a:solidFill>'
          '</a:rPr><a:t>$text</a:t></a:r></a:p>',
        );
      } else {
        final richText = _pptxRichTextRuns(line);
        paragraphs.add('<a:p><a:pPr>$spacingXml</a:pPr>$richText</a:p>');
      }
    }

    if (paragraphs.isEmpty) {
      paragraphs.add('<a:p><a:r><a:rPr lang="fr-FR" sz="1400"/><a:t></a:t></a:r></a:p>');
    }

    return paragraphs.join();
  }

  String _pptxRichTextRuns(String text) {
    final runs = <String>[];
    var cursor = 0;
    final pattern = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*)');

    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        final plain = _xmlEscape(text.substring(cursor, match.start));
        runs.add('<a:r><a:rPr lang="fr-FR" sz="1400"/><a:t>$plain</a:t></a:r>');
      }

      final m = match.group(0)!;
      if (m.startsWith('**') && m.endsWith('**') && m.length > 4) {
        final inner = _xmlEscape(m.substring(2, m.length - 2));
        runs.add('<a:r><a:rPr lang="fr-FR" sz="1400" b="1">'
            '<a:solidFill><a:srgbClr val="6C63FF"/></a:solidFill>'
            '</a:rPr><a:t>$inner</a:t></a:r>');
      } else if (m.startsWith('*') && m.endsWith('*') && m.length > 2) {
        final inner = _xmlEscape(m.substring(1, m.length - 1));
        runs.add('<a:r><a:rPr lang="fr-FR" sz="1400" i="1"/><a:t>$inner</a:t></a:r>');
      }

      cursor = match.end;
    }

    if (cursor < text.length) {
      final plain = _xmlEscape(text.substring(cursor));
      runs.add('<a:r><a:rPr lang="fr-FR" sz="1400"/><a:t>$plain</a:t></a:r>');
    }
    if (runs.isEmpty) {
      runs.add('<a:r><a:rPr lang="fr-FR" sz="1400"/><a:t>${_xmlEscape(text)}</a:t></a:r>');
    }

    return runs.join();
  }

  String _pptxSlideRelsXml({String? imagePath}) {
    final imageRel = imagePath != null
        ? '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="$imagePath"/>'
        : '';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
        '$imageRel</Relationships>';
  }

  String _pptxPresentationXml(int slideCount) {
    final slideIdList = StringBuffer();
    for (var i = 0; i < slideCount; i++) {
      slideIdList.write('<p:sldId id="${256 + i}" r:id="rId${i + 2}"/>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
        'saveSubsetFonts="1">'
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        '<p:sldIdLst>$slideIdList</p:sldIdLst>'
        '<p:sldSz cx="9144000" cy="6858000" type="screen4x3"/>'
        '<p:notesSz cx="6858000" cy="9144000"/></p:presentation>';
  }

  String _pptxPresentationRelsXml(int slideCount) {
    final rels = StringBuffer();
    rels.write('<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>');
    for (var i = 0; i < slideCount; i++) {
      rels.write('<Relationship Id="rId${i + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '$rels</Relationships>';
  }

  String _pptxContentTypes(int slideCount, {bool hasImages = false}) {
    final slideOverrides = StringBuffer();
    for (var i = 1; i <= slideCount; i++) {
      slideOverrides.write(
        '<Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
      );
    }
    final imageDefaults = hasImages
        ? '<Default Extension="jpg" ContentType="image/jpeg"/><Default Extension="png" ContentType="image/png"/>'
        : '';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '$imageDefaults'
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
        '$slideOverrides</Types>';
  }

  String _pptxRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>'
        '</Relationships>';
  }

  // ── Excel ───────────────────────────────────────────────────────────────────

  Uint8List _toExcel(String title, String body, List<String> sources) {
    final excel = Excel.createExcel();
    final sheet = excel['Document'];

    // Title row
    final titleCell = sheet.cell(CellIndex.indexByString('A1'));
    titleCell.value = TextCellValue(title);
    titleCell.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('FF6C63FF'),
      fontColorHex: ExcelColor.white,
      bold: true,
      fontSize: 14,
    );

    // Header row
    final headerA = sheet.cell(CellIndex.indexByString('A2'));
    headerA.value = TextCellValue('Section');
    headerA.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('FFF3F0FF'),
      fontColorHex: ExcelColor.fromHexString('FF6C63FF'),
      bold: true,
      fontSize: 12,
    );

    final headerB = sheet.cell(CellIndex.indexByString('B2'));
    headerB.value = TextCellValue('Contenu');
    headerB.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('FFF3F0FF'),
      fontColorHex: ExcelColor.fromHexString('FF6C63FF'),
      bold: true,
      fontSize: 12,
    );

    final cleanBody = _cleanBodyForDocgen(_stripLeadingTitle(body, title));
    final sections = _splitSections(cleanBody);
    var row = 3;
    for (final entry in sections.entries) {
      final cellA = sheet.cell(CellIndex.indexByString('A$row'));
      cellA.value = TextCellValue(entry.key);
      cellA.cellStyle = CellStyle(
        bold: true,
        fontSize: 11,
      );

      final cellB = sheet.cell(CellIndex.indexByString('B$row'));
      cellB.value = TextCellValue(entry.value);
      cellB.cellStyle = CellStyle(
        fontSize: 11,
      );
      row++;
    }

    final sourceText = sources.isEmpty
        ? 'Aucune source web explicite.'
        : sources.map((s) {
            final emDashIdx = s.indexOf(' — ');
            final urlPart = emDashIdx != -1 ? s.substring(emDashIdx + 3).trim() : s;
            final decoded = _decodeRedirectUrl(urlPart);
            final domain = _extractDomain(decoded);
            return '$domain: $decoded';
          }).join('\n');

    final sourceLabel = sheet.cell(CellIndex.indexByString('A$row'));
    sourceLabel.value = TextCellValue('Sources');
    sourceLabel.cellStyle = CellStyle(
      bold: true,
      fontSize: 11,
      backgroundColorHex: ExcelColor.fromHexString('FFF3F0FF'),
      fontColorHex: ExcelColor.fromHexString('FF6C63FF'),
    );

    final sourceValue = sheet.cell(CellIndex.indexByString('B$row'));
    sourceValue.value = TextCellValue(sourceText);
    sourceValue.cellStyle = CellStyle(
      fontSize: 11,
    );

    try {
      sheet.setColumnWidth(0, 30.0);
      sheet.setColumnWidth(1, 80.0);
    } catch (_) {
      // API may differ between package versions
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? <int>[]);
  }

  // ── Image generation (PNG/JPG) ──────────────────────────────────────────────

  Future<Uint8List> _toImage(String prompt, {required String format}) async {
    final encodedPrompt = Uri.encodeComponent(prompt);
    final seed = DateTime.now().millisecondsSinceEpoch % 10000;
    final url = 'https://image.pollinations.ai/prompt/$encodedPrompt'
        '?width=1024&height=1024&nologo=true&seed=$seed';

    try {
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode == 200) {
        return Uint8List.fromList(response.bodyBytes);
      }
      throw Exception('Image generation failed: HTTP ${response.statusCode}');
    } catch (e) {
      throw Exception('Image generation failed: $e');
    }
  }

  /// Fetch an illustration image from Pollinations AI for a given topic.
  /// Returns null if the generation fails (graceful fallback).
  Future<Uint8List?> _fetchIllustration(String topic) async {
    final prompt = 'Professional illustration, clean modern design, no text, no watermark, no logo, high quality, about: $topic';
    final encoded = Uri.encodeComponent(prompt);
    final seed = DateTime.now().millisecondsSinceEpoch % 10000;
    final url = 'https://image.pollinations.ai/prompt/$encoded'
        '?width=1024&height=1024&nologo=true&seed=$seed';
    try {
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode == 200) {
        return Uint8List.fromList(response.bodyBytes);
      }
      print('[DocGen] Illustration fetch failed: HTTP ${response.statusCode}');
      return null;
    } catch (e) {
      print('[DocGen] Illustration fetch error: $e');
      return null;
    }
  }

  // ── OOXML ZIP helper ────────────────────────────────────────────────────────

  Uint8List _createOoxmlZip({
    required String contentTypes,
    required String rels,
    required Map<String, List<int>> partFiles,
  }) {
    final archive = Archive();

    archive.addFile(ArchiveFile('[Content_Types].xml', contentTypes.length, utf8.encode(contentTypes)));
    archive.addFile(ArchiveFile('_rels/.rels', rels.length, utf8.encode(rels)));

    for (final entry in partFiles.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }

    final zipBytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipBytes ?? <int>[]);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Map<String, String> _splitSections(String body) {
    final result = <String, String>{};
    final headingPattern = RegExp(r'\n##+\s+');
    if (!body.contains(headingPattern)) {
      result['Contenu'] = body.trim();
      return result;
    }
    final chunks = body.split(headingPattern);
    // Preamble before first heading
    String preamble = '';
    if (!body.trimLeft().startsWith(RegExp(r'##+\s+'))) {
      final firstChunk = chunks.first.trim();
      if (firstChunk.isNotEmpty) preamble = firstChunk;
    }
    for (var i = 1; i < chunks.length; i++) {
      final trimmed = chunks[i].trim();
      if (trimmed.isEmpty) continue;
      final lines = trimmed.split('\n');
      final heading = lines.first.trim();
      final content = lines.skip(1).join('\n').trim();
      if (heading.isEmpty) continue;

      final lower = heading.toLowerCase();
      if (lower == 'titre' || lower.startsWith('titre :') || lower.startsWith('titre:')) {
        continue; // Skip LLM-generated duplicate title section
      }
      if (lower.contains('source') ||
          lower.contains('référence') ||
          lower.contains('reference') ||
          lower.contains('bibliographie')) {
        continue; // Skip LLM-generated sources section — handled separately
      }

      result[heading] = content;
    }
    if (preamble.isNotEmpty) {
      result['Introduction'] = preamble;
    }
    if (result.isEmpty) {
      result['Contenu'] = body.trim();
    }
    return result;
  }

  String _xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
