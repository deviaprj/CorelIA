import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Service de vision via Ollama — stub web.
/// Sur web, Ollama n'est pas accessible (localhost uniquement, pas de réseau local depuis extension).
class OllamaVisionService {
  static const String defaultModel = 'llava:13b';
  static const String defaultHost = 'http://localhost:11434';

  String _host = defaultHost;
  String _model = defaultModel;
  bool _enabled = false;

  String get host => _host;
  String get model => _model;
  bool get enabled => _enabled;

  Future<void> loadConfig() async {}
  Future<void> saveConfig({String? host, String? model, bool? enabled}) async {}

  Future<bool> isAvailable() async => false;

  Future<String> analyzeImage({
    required String imageBase64,
    required String prompt,
  }) async {
    throw StateError('Ollama vision is not available on web');
  }

  Future<List<String>> listModels() async => [];
}

final ollamaVisionServiceProvider = Provider<OllamaVisionService>((ref) => OllamaVisionService());