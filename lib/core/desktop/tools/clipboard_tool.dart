import 'package:flutter/services.dart';

import '../desktop_tool.dart';

/// Outil d'acces au presse-papiers systeme.
///
/// Operations : read_text, write_text.
class ClipboardTool extends DesktopTool {
  @override
  String get id => 'clipboard';

  @override
  String get name => 'Presse-papiers';

  @override
  String get description =>
      'Lit et ecrit dans le presse-papiers systeme. '
      'Utilise pour copier du texte genere, recuperer du texte copie.';

  @override
  String get category => 'systeme';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['read_text', 'write_text'],
            'description': 'Action a effectuer',
          },
          'text': {
            'type': 'string',
            'description': 'Texte a copier (pour write_text)',
          },
        },
        'required': ['action'],
      };

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<DesktopToolResult> execute(Map<String, dynamic> params) async {
    final action = params['action'] as String? ?? 'read_text';

    return switch (action) {
      'read_text' => _readText(),
      'write_text' => _writeText(params['text'] as String?),
      _ => DesktopToolResult.fail('Action inconnue : $action'),
    };
  }

  Future<DesktopToolResult> _readText() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && data!.text!.isNotEmpty) {
        return DesktopToolResult.ok(data.text!);
      }
      return DesktopToolResult.ok('(presse-papiers vide)');
    } catch (e) {
      return DesktopToolResult.fail('Erreur lecture presse-papiers : $e');
    }
  }

  Future<DesktopToolResult> _writeText(String? text) async {
    if (text == null || text.isEmpty) {
      return DesktopToolResult.fail('Texte requis');
    }

    try {
      await Clipboard.setData(ClipboardData(text: text));
      return DesktopToolResult.ok('Texte copie dans le presse-papiers (${text.length} chars)');
    } catch (e) {
      return DesktopToolResult.fail('Erreur ecriture presse-papiers : $e');
    }
  }
}
