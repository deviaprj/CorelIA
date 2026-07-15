import 'package:url_launcher/url_launcher.dart';

import '../desktop_tool.dart';
import '../permissions/desktop_permission_service.dart';

/// Outil de controle du navigateur systeme.
///
/// Operations : open_url, open_search.
class BrowserTool extends DesktopTool {
  final DesktopPermissionService _permissions;

  BrowserTool({DesktopPermissionService? permissions})
      : _permissions = permissions ?? desktopPermissionService;

  @override
  String get id => 'browser';

  @override
  String get name => 'Navigateur';

  @override
  String get description =>
      'Ouvre des URLs dans le navigateur systeme. '
      'Utilise pour ouvrir des pages web, des recherches, des services en ligne.';

  @override
  String get category => 'systeme';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['open_url', 'open_search'],
            'description': 'Action a effectuer',
          },
          'url': {
            'type': 'string',
            'description': 'URL a ouvrir',
          },
          'query': {
            'type': 'string',
            'description': 'Requete de recherche (pour open_search)',
          },
        },
        'required': ['action'],
      };

  @override
  Future<bool> get isAvailable async {
    return await canLaunchUrl(Uri.parse('https://google.com'));
  }

  @override
  Future<DesktopToolResult> execute(Map<String, dynamic> params) async {
    final action = params['action'] as String? ?? 'open_url';

    return switch (action) {
      'open_url' => _openUrl(params['url'] as String?),
      'open_search' => _openSearch(params['query'] as String?),
      _ => DesktopToolResult.fail('Action inconnue : $action'),
    };
  }

  Future<DesktopToolResult> _openUrl(String? url) async {
    if (url == null || url.isEmpty) {
      return DesktopToolResult.fail('URL requise');
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return DesktopToolResult.fail('URL invalide : $url');

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launched) {
        return DesktopToolResult.ok('URL ouverte : $url');
      }
      return DesktopToolResult.fail('Impossible d\'ouvrir : $url');
    } catch (e) {
      return DesktopToolResult.fail('Erreur navigateur : $e');
    }
  }

  Future<DesktopToolResult> _openSearch(String? query) async {
    if (query == null || query.isEmpty) {
      return DesktopToolResult.fail('Requete de recherche requise');
    }

    final encoded = Uri.encodeQueryComponent(query);
    final uri = Uri.parse('https://www.google.com/search?q=$encoded');

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launched) {
        return DesktopToolResult.ok('Recherche lancee : $query');
      }
      return DesktopToolResult.fail('Impossible de lancer la recherche');
    } catch (e) {
      return DesktopToolResult.fail('Erreur recherche : $e');
    }
  }
}
