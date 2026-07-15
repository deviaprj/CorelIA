import '../desktop_tool.dart';

/// Outil de capture d'ecran (placeholder).
///
/// L'implementation native sera ajoutee ulterieurement via FFI.
/// Pour l'instant, renvoie une erreur informative.
class ScreenshotTool extends DesktopTool {
  @override
  String get id => 'screenshot';

  @override
  String get name => 'Capture ecran';

  @override
  String get description =>
      'Capture le contenu de l\'ecran ou d\'une fenetre active. '
      'Utilise pour documenter, analyser des interfaces, sauvegarder des informations visuelles.';

  @override
  String get category => 'media';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['capture_full_screen', 'capture_active_window', 'capture_region'],
            'description': 'Type de capture',
          },
        },
        'required': ['action'],
      };

  @override
  Future<bool> get isAvailable async => false; // Pas encore implemente

  @override
  Future<DesktopToolResult> execute(Map<String, dynamic> params) async {
    return DesktopToolResult.fail(
      'Capture ecran non disponible. '
      'Cette fonctionnalite sera ajoutee dans une prochaine mise a jour.',
    );
  }
}
