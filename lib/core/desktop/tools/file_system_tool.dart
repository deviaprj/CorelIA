import 'dart:convert';
import 'dart:io' as io;

import '../desktop_tool.dart';
import '../permissions/desktop_permission_service.dart';

/// Outil de manipulation du systeme de fichiers local.
///
/// Operations : read, write, list, search, info.
/// Securite : limite aux dossiers autorises par l'utilisateur.
class FileSystemTool extends DesktopTool {
  final DesktopPermissionService _permissions;

  /// Chemins autorises par l'utilisateur.
  final Set<String> _allowedPaths = {
    io.Platform.environment['HOME'] ?? '/home',
  };

  FileSystemTool({DesktopPermissionService? permissions})
      : _permissions = permissions ?? desktopPermissionService;

  @override
  String get id => 'filesystem';

  @override
  String get name => 'Fichiers';

  @override
  String get description =>
      'Lit, ecrit, liste et recherche des fichiers sur le disque local. '
      'Utilise pour ouvrir des documents, parcourir des dossiers, '
      'lire le contenu de fichiers texte/PDF/DOCX/XLSX.';

  @override
  String get category => 'fichiers';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['read', 'write', 'list', 'search', 'info'],
            'description': 'Action a effectuer',
          },
          'path': {
            'type': 'string',
            'description': 'Chemin du fichier ou dossier',
          },
          'content': {
            'type': 'string',
            'description': 'Contenu a ecrire (pour action write)',
          },
          'pattern': {
            'type': 'string',
            'description': 'Pattern de recherche (pour action search)',
          },
          'recursive': {
            'type': 'boolean',
            'description': 'Recursif (pour list/search)',
            'default': false,
          },
          'maxResults': {
            'type': 'integer',
            'description': 'Nombre max de resultats',
            'default': 50,
          },
        },
        'required': ['action'],
      };

  @override
  Future<bool> get isAvailable async => true; // Toujours dispo sur desktop

  bool _isAllowed(String path) {
    final normalized = io.File(path).absolute.path;
    return _allowedPaths.any((allowed) => normalized.startsWith(allowed));
  }

  @override
  Future<DesktopToolResult> execute(Map<String, dynamic> params) async {
    if (!_permissions.isGranted(id)) {
      final granted = await _permissions.requestPermission(this);
      if (!granted.isGranted) {
        return DesktopToolResult.fail('Permission refusee pour FileSystem');
      }
    }

    final action = params['action'] as String? ?? 'read';
    final path = params['path'] as String?;

    return switch (action) {
      'read' => _handleRead(path),
      'write' => _handleWrite(path, params['content'] as String?),
      'list' => _handleList(path, params['recursive'] as bool? ?? false),
      'search' => _handleSearch(
          path, params['pattern'] as String? ?? '*', params['recursive'] as bool? ?? false, params['maxResults'] as int? ?? 50),
      'info' => _handleInfo(path),
      _ => DesktopToolResult.fail('Action inconnue : $action'),
    };
  }

  Future<DesktopToolResult> _handleRead(String? path) async {
    if (path == null) return DesktopToolResult.fail('Chemin requis');
    if (!_isAllowed(path)) return DesktopToolResult.fail('Acces refuse : $path');

    final file = io.File(path);
    if (!await file.exists()) return DesktopToolResult.fail('Fichier introuvable : $path');

    try {
      final size = await file.length();
      if (size > 5 * 1024 * 1024) {
        return DesktopToolResult.fail('Fichier trop volumineux (> 5 MB)');
      }
      final content = await file.readAsString();
      return DesktopToolResult.ok(content, metadata: {
        'path': file.absolute.path,
        'size': size,
        'extension': path.split('.').last,
      });
    } catch (e) {
      return DesktopToolResult.fail('Erreur lecture : $e');
    }
  }

  Future<DesktopToolResult> _handleWrite(String? path, String? content) async {
    if (path == null) return DesktopToolResult.fail('Chemin requis');
    if (content == null) return DesktopToolResult.fail('Contenu requis');
    if (!_isAllowed(path)) return DesktopToolResult.fail('Acces refuse : $path');

    try {
      final file = io.File(path);
      await file.writeAsString(content);
      return DesktopToolResult.ok('Fichier ecrit : ${file.absolute.path}');
    } catch (e) {
      return DesktopToolResult.fail('Erreur ecriture : $e');
    }
  }

  Future<DesktopToolResult> _handleList(String? path, bool recursive) async {
    final dir = io.Directory(path ?? io.Platform.environment['HOME'] ?? '/home');
    if (!_isAllowed(dir.path)) return DesktopToolResult.fail('Acces refuse : ${dir.path}');

    try {
      final entries = await dir.list(recursive: recursive).take(100).toList();
      final result = entries.map((e) {
        final isDir = e is io.Directory;
        return {
          'name': e.path.split('/').last,
          'path': e.path,
          'type': isDir ? 'directory' : 'file',
        };
      }).toList();

      return DesktopToolResult.ok(
        const JsonEncoder.withIndent('  ').convert(result),
        metadata: {'count': result.length, 'path': dir.absolute.path},
      );
    } catch (e) {
      return DesktopToolResult.fail('Erreur listage : $e');
    }
  }

  Future<DesktopToolResult> _handleSearch(
      String? path, String pattern, bool recursive, int maxResults) async {
    final dir = io.Directory(path ?? io.Platform.environment['HOME'] ?? '/home');
    if (!_isAllowed(dir.path)) return DesktopToolResult.fail('Acces refuse : ${dir.path}');

    try {
      final results = <String>[];
      await for (final entity in dir.list(recursive: recursive)) {
        if (entity.path.contains(pattern)) {
          results.add(entity.path);
          if (results.length >= maxResults) break;
        }
      }
      return DesktopToolResult.ok(
        results.join('\n'),
        metadata: {'count': results.length, 'pattern': pattern},
      );
    } catch (e) {
      return DesktopToolResult.fail('Erreur recherche : $e');
    }
  }

  Future<DesktopToolResult> _handleInfo(String? path) async {
    if (path == null) return DesktopToolResult.fail('Chemin requis');
    if (!_isAllowed(path)) return DesktopToolResult.fail('Acces refuse : $path');

    try {
      final file = io.File(path);
      if (!await file.exists()) return DesktopToolResult.fail('Introuvable : $path');

      final stat = await file.stat();
      final info = {
        'path': file.absolute.path,
        'size': stat.size,
        'modified': stat.modified.toIso8601String(),
        'accessed': stat.accessed.toIso8601String(),
        'type': stat.type.toString(),
        'extension': path.split('.').last,
      };
      return DesktopToolResult.ok(
        const JsonEncoder.withIndent('  ').convert(info),
        metadata: info,
      );
    } catch (e) {
      return DesktopToolResult.fail('Erreur info : $e');
    }
  }
}
