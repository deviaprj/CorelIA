import 'desktop_tool.dart';

/// Registre global des outils desktop disponibles.
///
/// Les outils sont enregistres au demarrage et appeles par :
/// - Le slash command `/tool <id> <params>` dans le ChatNotifier
/// - L'AgentRunner pour le mode agent autonome
class DesktopToolRegistry {
  final Map<String, DesktopTool> _tools = {};

  /// Enregistre un outil.
  void register(DesktopTool tool) {
    _tools[tool.id] = tool;
  }

  /// Enregistre plusieurs outils.
  void registerAll(Iterable<DesktopTool> tools) {
    for (final tool in tools) {
      register(tool);
    }
  }

  /// Desenregistre un outil.
  void unregister(String toolId) {
    _tools.remove(toolId);
  }

  /// Retourne un outil par son ID, ou null.
  DesktopTool? get(String toolId) => _tools[toolId];

  /// Tous les outils enregistres.
  List<DesktopTool> get all => _tools.values.toList();

  /// Tous les outils disponibles (filtre ceux non disponibles).
  Future<List<DesktopTool>> get available async {
    final results = <DesktopTool>[];
    for (final tool in _tools.values) {
      if (await tool.isAvailable) {
        results.add(tool);
      }
    }
    return results;
  }

  /// Outils groupes par categorie.
  Map<String, List<DesktopTool>> get byCategory {
    final map = <String, List<DesktopTool>>{};
    for (final tool in _tools.values) {
      map.putIfAbsent(tool.category, () => []).add(tool);
    }
    return map;
  }

  /// Format OpenAI function calling pour tous les outils.
  List<Map<String, dynamic>> get functionDefinitions {
    return _tools.values.map((t) => {
          'type': 'function',
          'function': {
            'name': t.id,
            'description': t.description,
            'parameters': t.parametersSchema,
          },
        }).toList();
  }

  /// Executer un outil par ID.
  Future<DesktopToolResult> execute(
    String toolId,
    Map<String, dynamic> params,
  ) async {
    final tool = _tools[toolId];
    if (tool == null) {
      return DesktopToolResult.fail('Outil inconnu : $toolId');
    }
    if (!await tool.isAvailable) {
      return DesktopToolResult.fail('Outil non disponible : $toolId');
    }
    return tool.execute(params);
  }
}

/// Singleton du registre.
final desktopToolRegistry = DesktopToolRegistry();
