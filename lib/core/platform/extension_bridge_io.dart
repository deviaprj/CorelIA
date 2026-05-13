import 'dart:async';
import 'package:flutter/foundation.dart';
import 'browser_action.dart';

/// Bridge extension Chrome — stub mobile (pas de chrome.runtime sur iOS/Android).
/// Le mobile utilise speech_to_text + flutter_tts directement.
class ExtensionBridge {
  final _selectedTextController = StreamController<String>.broadcast();
  final _pageContentController = StreamController<Map<String, String>>.broadcast();
  final _actionResultController = StreamController<BrowserActionResult>.broadcast();

  bool get isExtension => false;

  Stream<String> get onSelectedText => _selectedTextController.stream;
  Stream<Map<String, String>> get onPageContent => _pageContentController.stream;
  Stream<BrowserActionResult> get onActionResult => _actionResultController.stream;

  void init() {
    debugPrint('[ExtensionBridge] Non disponible sur mobile');
  }

  void requestPageContent() {
    debugPrint('[ExtensionBridge] Non disponible sur mobile');
  }

  /// Exécuter une action navigateur — stub mobile (toujours erreur).
  Future<BrowserActionResult> executeAction(BrowserAction action) async {
    return BrowserActionResult(
      actionId: action.actionId,
      action: action.action,
      success: false,
      error: 'Extension not available on mobile',
    );
  }

  void dispose() {
    _selectedTextController.close();
    _pageContentController.close();
    _actionResultController.close();
  }
}