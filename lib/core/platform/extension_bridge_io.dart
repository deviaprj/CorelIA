import 'dart:async';
import 'package:flutter/foundation.dart';

/// Bridge extension Chrome — stub mobile (pas de chrome.runtime sur iOS/Android).
class ExtensionBridge {
  final _selectedTextController = StreamController<String>.broadcast();
  final _pageContentController = StreamController<Map<String, String>>.broadcast();

  bool get isExtension => false;

  Stream<String> get onSelectedText => _selectedTextController.stream;
  Stream<Map<String, String>> get onPageContent => _pageContentController.stream;

  void init() {
    debugPrint('[ExtensionBridge] Non disponible sur mobile');
  }

  void requestPageContent() {
    debugPrint('[ExtensionBridge] Non disponible sur mobile');
  }

  void dispose() {
    _selectedTextController.close();
    _pageContentController.close();
  }
}