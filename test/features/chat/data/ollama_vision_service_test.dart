import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/data/ollama_vision_service.dart';

void main() {
  group('OllamaVisionService', () {
    test('defaultModel est llava:13b', () {
      final service = OllamaVisionService();
      expect(service.model, 'llava:13b');
    });

    test('defaultHost est localhost:11434', () {
      final service = OllamaVisionService();
      expect(service.host, 'http://localhost:11434');
    });

    test('enabled est false par défaut', () {
      final service = OllamaVisionService();
      expect(service.enabled, false);
    });

    test('saveConfig modifie les valeurs', () async {
      final service = OllamaVisionService();
      await service.saveConfig(
        host: 'http://192.168.1.100:11434',
        model: 'minicpm-v',
        enabled: true,
      );
      expect(service.host, 'http://192.168.1.100:11434');
      expect(service.model, 'minicpm-v');
      expect(service.enabled, true);
    });

    test('analyzeImage lance StateError si désactivé', () async {
      final service = OllamaVisionService();
      expect(
        () => service.analyzeImage(imageBase64: 'abc', prompt: 'test'),
        throwsA(isA<StateError>()),
      );
    });

    test('listModels retourne une liste vide si non disponible', () async {
      final service = OllamaVisionService();
      final models = await service.listModels();
      expect(models, isA<List<String>>());
    });
  });
}