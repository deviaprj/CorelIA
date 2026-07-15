import 'dart:convert';
import 'dart:io' as io;

import '../desktop_tool.dart';
import '../permissions/desktop_permission_service.dart';
import '../../../features/chat/data/file_upload_service.dart';

/// Outil de gestion de documents par lots.
///
/// Reutilise les services existants (FileUploadService, DocumentGenerationService)
/// pour le traitement par lots de documents.
///
/// Operations : summarize, extract_text, list_documents.
class DocumentTool extends DesktopTool {
  final DesktopPermissionService _permissions;
  final FileUploadService? _fileUploadService;

  DocumentTool({
    DesktopPermissionService? permissions,
    FileUploadService? fileUploadService,
  })  : _permissions = permissions ?? desktopPermissionService,
        _fileUploadService = fileUploadService;

  @override
  String get id => 'document';

  @override
  String get name => 'Documents';

  @override
  String get description =>
      'Analyse et traite des documents (PDF, DOCX, XLSX, PPTX, TXT, MD). '
      'Capable de lister, extraire du texte, resumer. '
      'Utilise pour analyser des rapports, extraire des donnees, traiter des lots de fichiers.';

  @override
  String get category => 'fichiers';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['summarize', 'extract_text', 'list_documents'],
            'description': 'Action a effectuer',
          },
          'path': {
            'type': 'string',
            'description': 'Chemin du fichier ou dossier a traiter',
          },
        },
        'required': ['action', 'path'],
      };

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<DesktopToolResult> execute(Map<String, dynamic> params) async {
    if (!_permissions.isGranted('filesystem')) {
      return DesktopToolResult.fail('Permission fichier requise');
    }

    final action = params['action'] as String? ?? 'extract_text';
    final path = params['path'] as String?;

    return switch (action) {
      'extract_text' => _extractText(path),
      'list_documents' => _listDocuments(path),
      _ => DesktopToolResult.fail('Action inconnue : $action'),
    };
  }

  Future<DesktopToolResult> _extractText(String? path) async {
    if (path == null) return DesktopToolResult.fail('Chemin requis');

    final file = io.File(path);
    if (!await file.exists()) return DesktopToolResult.fail('Fichier introuvable : $path');

    try {
      final fileService = _fileUploadService ?? FileUploadService();
      final ext = path.split('.').last.toLowerCase();

      // Pour l'instant : lecture basique
      // L'extraction avancee (PDF/DOCX/XLSX) viendra via FileUploadService
      if (['txt', 'md', 'csv', 'json'].contains(ext)) {
        final content = await file.readAsString();
        return DesktopToolResult.ok(
          content.length > 5000 ? content.substring(0, 5000) : content,
          metadata: {
            'path': path,
            'size': await file.length(),
            'extension': ext,
            'truncated': content.length > 5000,
          },
        );
      }

      // Binaire : retourne les metadonnees
      final stat = await file.stat();
      return DesktopToolResult.ok(
        'Fichier ${ext.toUpperCase()} : ${stat.size} octets\n'
        'Modifie le : ${stat.modified}',
        metadata: {
          'path': path,
          'size': stat.size,
          'extension': ext,
          'note': 'Extraction texte non supportee pour ce format. Utilisez le chat avec piece jointe.',
        },
      );
    } catch (e) {
      return DesktopToolResult.fail('Erreur extraction : $e');
    }
  }

  Future<DesktopToolResult> _listDocuments(String? path) async {
    final dirPath = path ?? io.Platform.environment['HOME'] ?? '/home';
    final dir = io.Directory(dirPath);

    if (!await dir.exists()) return DesktopToolResult.fail('Dossier introuvable : $dirPath');

    final docExtensions = [
      'pdf', 'docx', 'xlsx', 'pptx', 'txt', 'md', 'csv', 'json',
      'html', 'xml', 'rtf', 'odt', 'ods', 'odp',
    ];

    try {
      final docs = <Map<String, dynamic>>[];
      await for (final entity in dir.list(recursive: false)) {
        if (entity is io.File) {
          final ext = entity.path.split('.').last.toLowerCase();
          if (docExtensions.contains(ext)) {
            final stat = await entity.stat();
            docs.add({
              'name': entity.path.split('/').last,
              'path': entity.path,
              'size': stat.size,
              'extension': ext,
              'modified': stat.modified.toIso8601String(),
            });
          }
        }
        if (docs.length >= 100) break;
      }

      docs.sort((a, b) => (b['modified'] as String).compareTo(a['modified'] as String));

      return DesktopToolResult.ok(
        const JsonEncoder.withIndent('  ').convert(docs),
        metadata: {'count': docs.length, 'path': dirPath},
      );
    } catch (e) {
      return DesktopToolResult.fail('Erreur listage : $e');
    }
  }
}
