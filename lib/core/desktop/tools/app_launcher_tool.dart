import 'dart:io' as io;

import '../desktop_tool.dart';
import '../permissions/desktop_permission_service.dart';

/// Outil de lancement d'applications externes.
///
/// Operations : launch, list.
class AppLauncherTool extends DesktopTool {
  final DesktopPermissionService _permissions;

  AppLauncherTool({DesktopPermissionService? permissions})
      : _permissions = permissions ?? desktopPermissionService;

  @override
  String get id => 'app_launcher';

  @override
  String get name => 'Applications';

  @override
  String get description =>
      'Lance des applications installees sur le systeme. '
      'Utilise pour ouvrir des logiciels, executer des commandes simples.';

  @override
  String get category => 'systeme';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['launch', 'list'],
            'description': 'Action a effectuer',
          },
          'command': {
            'type': 'string',
            'description': 'Commande ou chemin de l\'application a lancer',
          },
          'args': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Arguments de la commande',
          },
        },
        'required': ['action'],
      };

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<DesktopToolResult> execute(Map<String, dynamic> params) async {
    if (!_permissions.isGranted(id)) {
      final granted = await _permissions.requestPermission(this);
      if (!granted.isGranted) {
        return DesktopToolResult.fail('Permission refusee pour AppLauncher');
      }
    }

    final action = params['action'] as String? ?? 'launch';

    return switch (action) {
      'launch' => _launch(params['command'] as String?, params['args'] as List<dynamic>?),
      'list' => _listApps(),
      _ => DesktopToolResult.fail('Action inconnue : $action'),
    };
  }

  Future<DesktopToolResult> _launch(String? command, List<dynamic>? args) async {
    if (command == null || command.isEmpty) {
      return DesktopToolResult.fail('Commande requise');
    }

    try {
      final processArgs = args?.map((a) => a.toString()).toList() ?? [];
      final result = await io.Process.run(command, processArgs);

      final output = StringBuffer();
      if (result.stdout.toString().isNotEmpty) {
        output.writeln(result.stdout);
      }
      if (result.stderr.toString().isNotEmpty) {
        output.writeln('[stderr] ${result.stderr}');
      }

      return DesktopToolResult.ok(
        output.toString().isEmpty ? 'Lance : $command' : output.toString(),
        metadata: {'exitCode': result.exitCode, 'command': command},
      );
    } catch (e) {
      return DesktopToolResult.fail('Erreur lancement : $e');
    }
  }

  Future<DesktopToolResult> _listApps() async {
    try {
      // Lister les .desktop files sur Linux
      if (io.Platform.isLinux) {
        final result = await io.Process.run('ls', [
          '/usr/share/applications/',
        ]);
        final apps = (result.stdout as String)
            .split('\n')
            .where((l) => l.endsWith('.desktop'))
            .map((l) => l.replaceAll('.desktop', ''))
            .take(50)
            .toList();
        return DesktopToolResult.ok(apps.join('\n'),
            metadata: {'count': apps.length});
      }

      // Windows
      if (io.Platform.isWindows) {
        final result = await io.Process.run('powershell', [
          '-Command',
          'Get-StartApps | Select-Object -First 50 -ExpandProperty Name',
        ]);
        return DesktopToolResult.ok(result.stdout.toString().trim());
      }

      return DesktopToolResult.fail('Non supporte sur cette plateforme');
    } catch (e) {
      return DesktopToolResult.fail('Erreur listage apps : $e');
    }
  }
}
