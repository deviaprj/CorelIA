import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';
import '../../../core/models/attachment.dart';

/// Exception specifique au service d'upload de fichiers.
class FileUploadException implements Exception {
  final String message;
  const FileUploadException(this.message);
  @override
  String toString() => 'FileUploadException: $message';
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
        debugPrint('[FileUploadService] ${file.name} ignoree (${bytes.length ~/ 1024}KB > ${maxSingleBytes ~/ 1024}KB)');
        continue;
      }

      if (totalSize + bytes.length > maxTotalBytes) {
        debugPrint('[FileUploadService] Limite 5MB atteinte, ${result.files.length - attachments.length} fichier(s) ignore(s)');
        break;
      }

      final ext = _getExtension(file.name);
      final mime = _detectMimeType(file.name);
      final text = await extractText(bytes, ext, file.name);

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

  /// Extrait le texte d'un fichier déjà en mémoire.
  ///
  /// Public pour être testable sans passer par le sélecteur de fichiers :
  /// c'est ici que se joue la capacité de l'assistant à lire un document.
  Future<String> extractText(Uint8List bytes, String ext, String name) async {
    try {
      switch (ext) {
        case 'pdf':
          return await _extractPdf(bytes);
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

  /// Décode un fichier texte en détectant son encodage.
  ///
  /// Un `.txt` n'est pas forcément de l'UTF-8 : le Bloc-notes Windows écrit de
  /// l'UTF-16 (« Unicode ») ou du CP1252 (« ANSI »). Décoder ces fichiers en
  /// UTF-8 de force remplaçait chaque accent par U+FFFD ; l'IA décrivait alors
  /// le document comme un binaire illisible.
  String _decodeTextFile(Uint8List bytes) {
    if (bytes.isEmpty) return '';

    if (_startsWith(bytes, const [0xEF, 0xBB, 0xBF])) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (_startsWith(bytes, const [0xFF, 0xFE])) {
      return _decodeUtf16(bytes.sublist(2), bigEndian: false);
    }
    if (_startsWith(bytes, const [0xFE, 0xFF])) {
      return _decodeUtf16(bytes.sublist(2), bigEndian: true);
    }

    try {
      return utf8.decode(bytes);
    } on FormatException {
      // Repli « ANSI » (CP1252) : conserve les accents au lieu de les perdre.
      return _decodeCp1252(bytes);
    }
  }

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static String _decodeUtf16(Uint8List bytes, {required bool bigEndian}) {
    final buffer = StringBuffer();
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final unit = bigEndian
          ? (bytes[i] << 8) | bytes[i + 1]
          : (bytes[i + 1] << 8) | bytes[i];
      buffer.writeCharCode(unit);
    }
    return buffer.toString();
  }

  /// Octets 0x80–0x9F du CP1252 : indéfinis en Latin-1 mais très courants
  /// (€, apostrophes et guillemets typographiques, tirets…).
  static const List<int> _cp1252High = [
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
  ];

  static String _decodeCp1252(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (byte < 0x80 || byte >= 0xA0) {
        buffer.writeCharCode(byte);
      } else {
        buffer.writeCharCode(_cp1252High[byte - 0x80]);
      }
    }
    return buffer.toString();
  }

  /// Extrait le texte d'un PDF.
  ///
  /// PDFium (via `pdfrx`) est la source primaire : c'est un vrai moteur PDF, il
  /// gère les flux compressés, les polices CID et l'ordre de lecture réel. Il
  /// n'est pas disponible sur le Web (PDF.js est chargé depuis un CDN, ce qui
  /// violerait l'autonomie de l'extension) ni en test VM (pas de libpdfium) :
  /// on retombe alors sur le scanner pure-Dart ci-dessous, sans dépendance
  /// native. Si aucun des deux n'aboutit, on renvoie un marqueur explicite —
  /// jamais du charabia, qui ferait décrire le document comme illisible.
  Future<String> _extractPdf(Uint8List bytes) async {
    if (!kIsWeb) {
      try {
        final fromPdfium = await _extractWithPdfium(bytes);
        if (_isUsablePdfText(fromPdfium)) return fromPdfium;
      } catch (e, st) {
        debugPrint('[FileUploadService] PDFium indisponible : $e');
        debugPrint(st.toString());
      }
    }

    try {
      final withoutEngine = _extractPdfTextWithoutEngine(bytes);
      if (_isUsablePdfText(withoutEngine) &&
          _looksLikeNaturalText(withoutEngine)) {
        return withoutEngine;
      }
    } catch (e, st) {
      debugPrint('[FileUploadService] Extraction PDF (repli) échouée : $e');
      debugPrint(st.toString());
    }

    return '${Attachment.unreadableMarkerPrefix} PDF sans couche texte '
        'exploitable (scan, image, chiffrement ou police non gérée).';
  }

  /// Extraction PDF sans moteur natif (Web, tests, PDFium indisponible).
  ///
  /// On ne lit **que** les flux de contenu référencés par `/Contents`. Balayer
  /// tous les flux ramassait les polices, les CMap et les métadonnées XMP :
  /// leur contenu passait pour du texte, d'où des réponses du type « ce
  /// document est un binaire illisible ».
  String _extractPdfTextWithoutEngine(Uint8List bytes) {
    // latin1 : 1 caractère = 1 octet, les index restent alignés sur les octets.
    final raw = latin1.decode(bytes);

    final streams = <_PdfStream>[];
    for (final id in _contentStreamObjectIds(raw)) {
      final stream = _objectStream(raw, id);
      if (stream != null) streams.add(stream);
    }
    // PDF atypique sans `/Contents` repérable : dernier recours, balayage des
    // flux, filtré de la même façon (voir [_extractTextFromStreams]).
    if (streams.isEmpty) streams.addAll(_findPdfStreams(bytes));

    return _extractTextFromStreams(streams);
  }

  /// Numéros d'objets désignés par les entrées `/Contents` du document.
  ///
  /// `/Contents` n'apparaît que dans les dictionnaires de page : c'est le moyen
  /// fiable d'isoler les vrais flux de contenu sans analyser tout le PDF.
  static Set<int> _contentStreamObjectIds(String raw) {
    final ids = <int>{};
    final contentsRegex = RegExp(r'/Contents\s*(\[[^\]]*\]|\d+\s+\d+\s+R)');
    for (final match in contentsRegex.allMatches(raw)) {
      final value = match.group(1)!;
      for (final ref in RegExp(r'(\d+)\s+\d+\s+R').allMatches(value)) {
        final id = int.tryParse(ref.group(1)!);
        if (id != null) ids.add(id);
      }
    }
    return ids;
  }

  /// Flux de l'objet numéro [id] (`id 0 obj … stream … endstream`).
  static _PdfStream? _objectStream(String raw, int id) {
    final objRegex = RegExp('(?:^|[^0-9])$id\\s+\\d+\\s+obj\\b');
    final objectMatch = objRegex.firstMatch(raw);
    if (objectMatch == null) return null;

    final bodyStart = objectMatch.end;
    final streamIndex = raw.indexOf('stream', bodyStart);
    if (streamIndex == -1) return null;
    final endObjIndex = raw.indexOf('endobj', bodyStart);
    if (endObjIndex != -1 && streamIndex > endObjIndex) return null;

    final dictionary = raw.substring(bodyStart, streamIndex);
    var dataStart = streamIndex + 'stream'.length;
    if (dataStart < raw.length && raw.codeUnitAt(dataStart) == 0x0D) dataStart++;
    if (dataStart < raw.length && raw.codeUnitAt(dataStart) == 0x0A) dataStart++;

    final endStreamIndex = raw.indexOf('endstream', dataStart);
    if (endStreamIndex == -1) return null;

    // `/Length` donne la taille exacte : plus fiable que rogner les espaces,
    // qui pouvait amputer le dernier octet de données.
    final declaredLength =
        _declaredStreamLength(dictionary, dataStart, raw.length);
    var dataEnd =
        declaredLength != null ? dataStart + declaredLength : endStreamIndex;
    if (declaredLength == null) {
      while (dataEnd > dataStart &&
          _isPdfWhitespace(raw.codeUnitAt(dataEnd - 1))) {
        dataEnd--;
      }
    }
    if (dataEnd <= dataStart) return null;

    return _PdfStream(
      data: Uint8List.fromList(latin1.encode(raw.substring(dataStart, dataEnd))),
      dictionary: dictionary,
    );
  }

  /// Longueur déclarée par `/Length`, ou `null` si absente/indirecte/invalide.
  static int? _declaredStreamLength(
    String dictionary,
    int dataStart,
    int rawLength,
  ) {
    final match = RegExp(r'/Length\s+(\d+)').firstMatch(dictionary);
    if (match == null) return null;
    // `/Length 12 0 R` est une référence indirecte, pas une taille.
    if (RegExp(r'^\s+\d+\s+R\b').hasMatch(dictionary.substring(match.end))) {
      return null;
    }
    final length = int.tryParse(match.group(1)!);
    if (length == null || length <= 0 || dataStart + length > rawLength) {
      return null;
    }
    return length;
  }

  /// Texte reconstitué à partir de flux PDF (décompressés si nécessaire).
  static String _extractTextFromStreams(List<_PdfStream> streams) {
    final allTexts = <String>[];
    for (final stream in streams) {
      if (stream.data.isEmpty) continue;
      var data = stream.data;
      if (stream.dictionary.contains('/FlateDecode')) {
        final decompressed = _inflatePdfStream(data);
        if (decompressed == null || decompressed.isEmpty) continue;
        data = decompressed;
      }
      final decoded = utf8.decode(data, allowMalformed: true);
      if (!_looksLikeContentStream(decoded)) continue;
      final texts = _extractContentStreamFragments(decoded)
          .where(_looksLikeText)
          .toList();
      if (texts.isNotEmpty) allTexts.addAll(texts);
    }
    if (allTexts.isEmpty) return '';
    return _groupIntoParagraphs(_deduplicateStrings(allTexts));
  }

  /// Vrai si [text] ressemble à de la prose.
  ///
  /// Un flux de contenu en police CID produit des indices de glyphes, souvent
  /// imprimables (donc acceptés par [_looksLikeText]) mais sans mots : suites de
  /// symboles isolés ou de caractères uniques. Ce filtre les écarte. PDFium n'en
  /// a pas besoin : il applique le ToUnicode du document.
  static bool _looksLikeNaturalText(String text) {
    final tokens =
        text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.length < 3) return false;
    var wordLike = 0;
    for (final token in tokens) {
      final letters = _letterRegex.allMatches(token).length;
      if (letters >= 3 && letters * 2 >= token.length) wordLike++;
    }
    return wordLike / tokens.length >= 0.3;
  }

  static final RegExp _letterRegex = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]');

  /// Extrait le texte de chaque page via PDFium (pdfrx).
  ///
  /// Renvoie une chaîne vide quand le document n'a pas de couche texte (scan,
  /// image, vectoriel) ; lève si le moteur natif est indisponible — l'appelant
  /// bascule alors sur le scanner pure-Dart.
  Future<String> _extractWithPdfium(Uint8List bytes) async {
    final document = await PdfDocument.openData(bytes, sourceName: 'upload');

    try {
      final pages = <String>[];
      for (final page in document.pages) {
        final text = (await page.loadText()).fullText.trim();
        if (text.isNotEmpty) pages.add(text);
      }
      return pages.join('\n\n');
    } finally {
      await document.dispose();
    }
  }

  /// Vrai si l'extraction a produit du texte exploitable (et non un gabarit).
  static bool _isUsablePdfText(String text) {
    final trimmed = text.trim();
    return trimmed.isNotEmpty &&
        !trimmed.startsWith('[') &&
        _looksLikeText(trimmed);
  }

  /// Vrai si [text] ressemble à du texte lisible, et non à des octets binaires
  /// (police, image, table de références) décodés en force. Un échec explicite
  /// vaut mieux qu'une extraction silencieusement corrompue : ce garde-fou
  /// évite d'injecter du bruit binaire dans le contexte de l'IA.
  static bool _looksLikeText(String text) {
    if (text.isEmpty) return false;
    var printable = 0;
    var total = 0;
    for (final rune in text.runes) {
      total++;
      if (rune == 0xFFFD) continue;
      if (rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D) {
        continue;
      }
      printable++;
    }
    return total > 0 && printable / total >= 0.85;
  }

  /// Décompresse un flux PDF `/FlateDecode`.
  ///
  /// Le format PDF embarque du zlib (RFC 1950, en-tête + Adler-32), alors que
  /// `inflateBuffer` de `archive` attend du deflate brut : il échoue sur tous
  /// les vrais PDF. On utilise donc [ZLibDecoder], avec un repli deflate brut
  /// pour les producteurs non conformes. Renvoie `null` si rien n'aboutit.
  static Uint8List? _inflatePdfStream(Uint8List data) {
    try {
      final out = const ZLibDecoder().decodeBytes(data);
      if (out.isNotEmpty) return Uint8List.fromList(out);
    } catch (_) {}

    try {
      final out = inflateBuffer(data);
      if (out != null && out.isNotEmpty) return Uint8List.fromList(out);
    } catch (_) {}

    return null;
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

  /// Vrai si [decoded] contient un opérateur d'affichage de texte : signature
  /// d'un flux de contenu, par opposition à une police ou une image.
  static bool _looksLikeContentStream(String decoded) {
    return decoded.contains('Tj') ||
        decoded.contains('TJ') ||
        decoded.contains("T'");
  }

  /// Extrait les fragments de texte d'un flux de contenu PDF déjà décodé.
  ///
  /// Couvre les opérandes littéraux `(…)` (`Tj`, `TJ`, `'`) et hexadécimaux
  /// `<…>` (polices CID). Tout `(…)` d'un flux de contenu est un fragment de
  /// texte : la validation du flux est faite en amont.
  static List<String> _extractContentStreamFragments(String content) {
    final results = <String>[];

    final parenRegex = RegExp(r'\(((?:\\.|[^\\()])*)\)');
    for (final m in parenRegex.allMatches(content)) {
      final t = m.group(1);
      if (t == null) continue;
      final clean = _unescapePdfString(t);
      if (clean.isNotEmpty) results.add(clean);
    }

    results.addAll(_extractHexStrings(content));
    return results;
  }

  /// Décode les littéraux hexadécimaux `<…>` (polices CID / sous-ensembles).
  static List<String> _extractHexStrings(String raw) {
    final results = <String>[];
    final hexRegex = RegExp(r'<([0-9A-Fa-f\s]+)>');
    for (final m in hexRegex.allMatches(raw)) {
      final hex = m.group(1)?.replaceAll(RegExp(r'\s+'), '');
      if (hex == null || hex.isEmpty || hex.length.isOdd) continue;
      try {
        final hexBytes = <int>[];
        for (var i = 0; i < hex.length; i += 2) {
          hexBytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
        }
        final decoded = utf8.decode(hexBytes, allowMalformed: true).trim();
        if (decoded.length > 2) results.add(decoded);
      } catch (_) {}
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
        currentLine.write('$fragment ');
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
      buffer.writeln('--- $table ---');
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
          final numA = int.tryParse(a.name.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
          final numB = int.tryParse(b.name.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
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

  static String _unescapePdfString(String s) {
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
