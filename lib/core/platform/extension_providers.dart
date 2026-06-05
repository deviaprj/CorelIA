import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'extension_bridge.dart';

/// Provider singleton pour l'ExtensionBridge.
/// Sur mobile, c'est un stub (isExtension = false).
/// Sur web/extension, il écoute les messages du background SW.
final extensionBridgeProvider = Provider<ExtensionBridge>((ref) {
  final bridge = ExtensionBridge();
  bridge.init();
  ref.onDispose(() => bridge.dispose());
  return bridge;
});

/// Stream du texte sélectionné reçu depuis l'extension Chrome.
/// Vide sur mobile. Sur extension, contient le texte sélectionné via
/// le menu contextuel "Demander à Corely".
final extensionSelectedTextProvider = StreamProvider<String>((ref) {
  final bridge = ref.watch(extensionBridgeProvider);
  return bridge.onSelectedText;
});

/// Stream du contenu de page reçu depuis l'extension Chrome.
final extensionPageContentProvider = StreamProvider<Map<String, String>>((ref) {
  final bridge = ref.watch(extensionBridgeProvider);
  return bridge.onPageContent;
});