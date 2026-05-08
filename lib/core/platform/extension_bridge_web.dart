import 'dart:async';
import 'dart:js' as js;
import 'package:flutter/foundation.dart';

/// Bridge extension Chrome — reçoit les CustomEvents du extension_bridge.js.
/// Utilise dart:js pour l'accès dynamique aux propriétés JS
/// (l'extension Chrome ne cible pas WASM, dart:js est sûr).
class ExtensionBridge {
  final _selectedTextController = StreamController<String>.broadcast();
  final _pageContentController = StreamController<Map<String, String>>.broadcast();

  bool _isExtension = false;
  bool _initialized = false;

  bool get isExtension => _isExtension;
  Stream<String> get onSelectedText => _selectedTextController.stream;
  Stream<Map<String, String>> get onPageContent => _pageContentController.stream;

  void init() {
    if (_initialized) return;
    _initialized = true;

    _isExtension = _detectChromeExtension();
    debugPrint('[ExtensionBridge] isExtension: $_isExtension');

    if (!_isExtension) return;
    _setupListeners();
  }

  bool _detectChromeExtension() {
    try {
      final protocol = (js.context['window'] as js.JsObject)['location']['protocol'];
      return protocol == 'chrome-extension:';
    } catch (_) {
      return false;
    }
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

  // ── JS helpers ──────────────────────────────────────────────────────────

  void _addWindowListener(String type, void Function(js.JsObject) callback) {
    try {
      final window = js.context['window'] as js.JsObject;
      window.callMethod('addEventListener', [type, callback]);
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

  void dispose() {
    _selectedTextController.close();
    _pageContentController.close();
  }
}