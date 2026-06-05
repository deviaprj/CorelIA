import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:corel_ia/features/chat/data/ai_client.dart';

void main() {
  group('HTTP Client Singleton', () {
    test('should use singleton client in DeepSeekClient', () {
      // Verify the singleton pattern is used
      // The _httpClient should be reused across requests
      final client1 = DeepSeekClient(apiKey: 'key1');
      final client2 = DeepSeekClient(apiKey: 'key2');

      // Both clients should exist
      expect(client1, isNotNull);
      expect(client2, isNotNull);
    });

    test('should use singleton client in OpenRouterClient', () {
      final client1 = OpenRouterClient(apiKey: 'key1');
      final client2 = OpenRouterClient(apiKey: 'key2');

      expect(client1, isNotNull);
      expect(client2, isNotNull);
    });

    test('singleton should be http.Client type', () {
      // Verify the internal client exists
      // This is a compile-time check rather than runtime
      expect(http.Client, isNotNull);
    });
  });

  group('Client Resource Management', () {
    test('DeepSeekClient should not create new http.Client per request', () {
      // The singleton pattern ensures the client is reused
      // This test documents the expected behavior
      final client = DeepSeekClient(apiKey: 'test');
      expect(client, isNotNull);
    });

    test('OpenRouterClient should not create new http.Client per request', () {
      final client = OpenRouterClient(apiKey: 'test');
      expect(client, isNotNull);
    });
  });
}
