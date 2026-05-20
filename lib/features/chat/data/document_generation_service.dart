import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
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
        fileBytes = _toDocx(title, body, sources);
        ext = 'docx';
        mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        break;
      case 'powerpoint':
        fileBytes = _toPptx(title, body, sources);
        ext = 'pptx';
        mimeType = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
        break;
      case 'excel':
        fileBytes = _toExcel(title, body, sources);
        ext = 'xlsx';
        mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
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
    final now = DateTime.now().toIso8601String();
    final sourceLines = sources.isEmpty
        ? 'Aucune source web explicite.'
        : sources.map((s) => '- $s').join('\n');

    return 'Titre: $title\n'
        'Genere par Corely: $now\n\n'
        '$body\n\n'
        'Sources:\n$sourceLines\n';
  }

  String _toMarkdown(String title, String body, List<String> sources) {
    final sourceLines = sources.isEmpty
        ? '- Aucune source web explicite.'
        : sources.map((s) => '- $s').join('\n');

    return '# $title\n\n'
        '$body\n\n'
        '## Sources\n$sourceLines\n';
  }

  // ── PDF ─────────────────────────────────────────────────────────────────────

  Future<Uint8List> _toPdf(String title, String body, List<String> sources) async {
    final doc = pw.Document();
    final sourceLines = sources.isEmpty
        ? 'Aucune source web explicite.'
        : sources.join('\n');

    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Text(title, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Text(body),
          pw.SizedBox(height: 20),
          pw.Text('Sources', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text(sourceLines),
        ],
      ),
    );

    return Uint8List.fromList(await doc.save());
  }

  // ── DOCX (real OOXML) ──────────────────────────────────────────────────────

  Uint8List _toDocx(String title, String body, List<String> sources) {
    final sections = _splitSections(body);
    final sourceText = sources.isEmpty ? 'Aucune source web explicite.' : sources.join('\n');

    final paragraphs = <String>[];
    paragraphs.add(_docxParagraph(title, true, 28));
    paragraphs.add(_docxParagraph('', false, 11));
    for (final entry in sections.entries) {
      paragraphs.add(_docxParagraph(entry.key, true, 16));
      for (final line in entry.value.split('\n')) {
        if (line.trim().isNotEmpty) {
          paragraphs.add(_docxParagraph(line.trim(), false, 11));
        }
      }
    }
    paragraphs.add(_docxParagraph('', false, 11));
    paragraphs.add(_docxParagraph('Sources', true, 16));
    paragraphs.add(_docxParagraph(sourceText, false, 11));

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
        'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">'
        '<w:body>$bodyXml<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>'
        '</w:sectPr></w:body></w:document>';

    return _createOoxmlZip(
      contentTypes: _docxContentTypes(),
      rels: _docxRels(),
      partFiles: {
        'word/document.xml': utf8.encode(documentXml),
        'word/_rels/document.xml.rels': utf8.encode(_docxDocumentRels()),
        'word/styles.xml': utf8.encode(_docxStyles()),
      },
    );
  }

  String _docxParagraph(String text, bool bold, int size) {
    final escaped = _xmlEscape(text);
    final boldAttr = bold ? ' w:b="1"' : '';
    return '<w:p><w:pPr><w:rPr><w:sz w:val="${size * 2}"/>$boldAttr</w:rPr></w:pPr>'
        '<w:r><w:rPr><w:sz w:val="${size * 2}"/>$boldAttr</w:rPr>'
        '<w:t xml:space="preserve">$escaped</w:t></w:r></w:p>';
  }

  String _docxContentTypes() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
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

  String _docxDocumentRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>';
  }

  String _docxStyles() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>'
        '</w:styles>';
  }

  // ── PPTX (real OOXML) ──────────────────────────────────────────────────────

  Uint8List _toPptx(String title, String body, List<String> sources) {
    final sections = _splitSections(body);
    final sourceText = sources.isEmpty ? 'Aucune source web explicite.' : sources.join('\n');

    final slides = <Map<String, String>>[];
    slides.add({'title': title, 'content': ''});
    for (final entry in sections.entries) {
      slides.add({'title': entry.key, 'content': entry.value});
    }
    slides.add({'title': 'Sources', 'content': sourceText});

    final slideXmls = <String, List<int>>{};
    final slideRelsXmls = <String, List<int>>{};
    final relTargets = <String>[];

    for (var i = 0; i < slides.length; i++) {
      final slideNum = i + 1;
      final slideFileName = 'ppt/slides/slide$slideNum.xml';
      final slideRelFileName = 'ppt/slides/_rels/slide$slideNum.xml.rels';
      slideXmls[slideFileName] = utf8.encode(_pptxSlideXml(slides[i]['title'] ?? '', slides[i]['content'] ?? ''));
      slideRelsXmls[slideRelFileName] = utf8.encode(_pptxSlideRelsXml());
      relTargets.add('<Relationship Id="rId$slideNum" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$slideNum.xml"/>');
    }

    final partFiles = <String, List<int>>{};
    partFiles['ppt/presentation.xml'] = utf8.encode(_pptxPresentationXml(slides.length));
    partFiles['ppt/_rels/presentation.xml.rels'] = utf8.encode(_pptxPresentationRelsXml(slides.length));
    for (final entry in slideXmls.entries) {
      partFiles[entry.key] = entry.value;
    }
    for (final entry in slideRelsXmls.entries) {
      partFiles[entry.key] = entry.value;
    }

    return _createOoxmlZip(
      contentTypes: _pptxContentTypes(slides.length),
      rels: _pptxRels(),
      partFiles: partFiles,
    );
  }

  String _pptxSlideXml(String title, String content) {
    final escapedTitle = _xmlEscape(title);
    final escapedContent = _xmlEscape(content);
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/>'
        '<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="274630"/>'
        '<a:ext cx="8229600" cy="1143000"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:r><a:rPr lang="fr-FR" sz="2800" b="1" dirty="0"/>'
        '<a:t>$escapedTitle</a:t></a:r></a:p></p:txBody></p:sp>'
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Content"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="1600200"/>'
        '<a:ext cx="8229600" cy="4572000"/></a:xfrm>'
        '<a:prstGeom prst="rect"/></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:r><a:rPr lang="fr-FR" sz="1400" dirty="0"/>'
        '<a:t>${escapedContent.length > 3000 ? escapedContent.substring(0, 3000) : escapedContent}</a:t></a:r></a:p></p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';
  }

  String _pptxSlideRelsXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
        '</Relationships>';
  }

  String _pptxPresentationXml(int slideCount) {
    final slideIdList = StringBuffer();
    for (var i = 0; i < slideCount; i++) {
      slideIdList.write('<p:sldId id="${256 + i}" r:id="rId${i + 1}"/>');
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

  String _pptxContentTypes(int slideCount) {
    final slideOverrides = StringBuffer();
    for (var i = 1; i <= slideCount; i++) {
      slideOverrides.write(
        '<Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
      );
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
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

    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue(title);
    sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('Section');
    sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue('Contenu');

    final sections = _splitSections(body);
    var row = 3;
    for (final entry in sections.entries) {
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(entry.key);
      sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(entry.value);
      row++;
    }

    sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue('Sources');
    sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(sources.join('\n'));

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? <int>[]);
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
    final chunks = body.split(RegExp(r'\n##+\s+'));
    for (final chunk in chunks) {
      final trimmed = chunk.trim();
      if (trimmed.isEmpty) continue;
      final lines = trimmed.split('\n');
      final heading = lines.first.trim();
      final content = lines.skip(1).join('\n').trim();
      result[heading.isEmpty ? 'Section' : heading] = content;
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
