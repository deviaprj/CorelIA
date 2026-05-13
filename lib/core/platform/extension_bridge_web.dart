import 'dart:async';
import 'dart:js' as js;
import 'package:flutter/foundation.dart';
import 'browser_action.dart';
import 'platform_service.dart';

/// Bridge extension Chrome — reçoit les CustomEvents du extension_bridge.js.
/// Utilise dart:js pour l'accès dynamique aux propriétés JS
/// (l'extension Chrome ne cible pas WASM, dart:js est sûr).
class ExtensionBridge {
  final _selectedTextController = StreamController<String>.broadcast();
  final _pageContentController = StreamController<Map<String, String>>.broadcast();
  final _actionResultController = StreamController<BrowserActionResult>.broadcast();
  final _pendingActions = <String, Completer<BrowserActionResult>>{};

  bool _isExtension = false;
  bool _initialized = false;

  bool get isExtension => _isExtension;
  Stream<String> get onSelectedText => _selectedTextController.stream;
  Stream<Map<String, String>> get onPageContent => _pageContentController.stream;
  Stream<BrowserActionResult> get onActionResult => _actionResultController.stream;

  void init() {
    if (_initialized) return;
    _initialized = true;

    // Utiliser PlatformService (Uri.base.scheme) au lieu de js.context
    // car js.context['window']['location'] échoue en mode minifié.
    _isExtension = PlatformService.isExtension;
    debugPrint('[ExtensionBridge] isExtension: $_isExtension');

    if (!_isExtension) return;
    _setupListeners();
  }

  void _setupListeners() {
    _addWindowListener('corely_selected_text', (js.JsObject event) {
      final detail = event['detail'] as js.JsObject?;
      if (detail == null) return;
      final text = _getString(detail, 'text');
      if (text.isNotEmpty) {
        debugPrint('[ExtensionBridge] Selected text: ${text.length} chars');
        _selectedTextController.add(text);
      }
    });

    _addWindowListener('corely_page_content', (js.JsObject event) {
      final detail = event['detail'] as js.JsObject?;
      if (detail == null) return;
      final title = _getString(detail, 'title');
      final url = _getString(detail, 'url');
      final content = _getString(detail, 'content');
      if (title.isNotEmpty || content.isNotEmpty) {
        _pageContentController.add({'title': title, 'url': url, 'content': content});
      }
    });

    _addWindowListener('corely_browser_action_result', (js.JsObject event) {
      final detail = event['detail'] as js.JsObject?;
      if (detail == null) return;

      final result = BrowserActionResult.fromJson({
        'actionId': _getString(detail, 'actionId'),
        'action': _getString(detail, 'action'),
        'success': _getBool(detail, 'success') ?? false,
        'data': detail['data'],
        'error': _getString(detail, 'error'),
      });

      // Complete pending future
      final completer = _pendingActions.remove(result.actionId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(result);
      }

      // Broadcast to stream
      _actionResultController.add(result);
    });
  }

  /// Demander au content script d'extraire le contenu de la page.
  void requestPageContent() {
    if (!_isExtension) return;
    try {
      js.context.callMethod('dispatchCustomEvent', ['corely_request_page_content', null]);
    } catch (e) {
      debugPrint('[ExtensionBridge] Error dispatching requestPageContent: $e');
    }
  }

  /// Exécuter une action navigateur (ouvrir un URL, cliquer, remplir, etc.).
  /// Retourne le résultat de l'action via un Future avec timeout de 10 secondes.
  Future<BrowserActionResult> executeAction(BrowserAction action) async {
    if (!_isExtension) {
      return BrowserActionResult(
        actionId: action.actionId,
        action: action.action,
        success: false,
        error: 'Extension not available',
      );
    }

    final completer = Completer<BrowserActionResult>();
    _pendingActions[action.actionId] = completer;

    try {
      final jsDetail = js.JsObject.jsify(action.toJson());
      js.context.callMethod('dispatchCustomEvent', ['corely_browser_action', jsDetail]);
    } catch (e) {
      _pendingActions.remove(action.actionId);
      return BrowserActionResult(
        actionId: action.actionId,
        action: action.action,
        success: false,
        error: e.toString(),
      );
    }

    // Timeout 10 secondes
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pendingActions.remove(action.actionId);
        return BrowserActionResult(
          actionId: action.actionId,
          action: action.action,
          success: false,
          error: 'Action timed out',
        );
      },
    );
  }

  // ── JS helpers ──────────────────────────────────────────────────────────

  /// Ajoute un event listener via dart:js en utilisant allowInterop
  /// pour éviter les erreurs de type en mode minifié.
  void _addWindowListener(String type, void Function(js.JsObject) callback) {
    try {
      // js.context est le contexte global (window en navigateur)
      js.context.callMethod('addEventListener', [
        type,
        js.allowInterop((event) {
          callback(event as js.JsObject);
        }),
      ]);
    } catch (e) {
      debugPrint('[ExtensionBridge] Error adding listener for $type: $e');
    }
  }

  String _getString(js.JsObject obj, String key) {
    try {
      final value = obj[key];
      if (value is String) return value;
      return '';
    } catch (_) {
      return '';
    }
  }

  bool? _getBool(js.JsObject obj, String key) {
    try {
      final value = obj[key];
      if (value is bool) return value;
      return null;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _selectedTextController.close();
    _pageContentController.close();
    _actionResultController.close();
    for (final c in _pendingActions.values) {
      if (!c.isCompleted) c.completeError('Bridge disposed');
    }
    _pendingActions.clear();
  }
}