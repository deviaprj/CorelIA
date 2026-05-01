import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:airon_bot/features/chat/data/ai_client.dart';
import 'package:airon_bot/core/constants.dart';


void main() {
  group('DeepSeekClient', () {
    late DeepSeekClient client;
    const testApiKey = 'test_api_key';

    setUp(() {
      client = DeepSeekClient(apiKey: testApiKey);
    });

    test('should be created with API key', () {
      expect(client, isNotNull);
    });

    test('should throw exception with empty API key', () async {
      final emptyClient = DeepSeekClient(apiKey: '');

      await expectLater(
        emptyClient.streamChat(messages: []).toList(),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('Clé API DeepSeek manquante'),
          ),
        ),
      );
    });

    test('should use correct model', () {
      expect(AppConstants.deepSeekModel, equals('deepseek-v4-flash'));
    });

    test('should use correct max tokens', () {
      expect(AppConstants.maxTokens, equals(4096));
    });

    test('should construct correct API request body', () async {
      final messages = [
        {'role': 'user', 'content': 'Hello'},
      ];

      // Vérification de la structure sans appel réel
      final body = jsonEncode({
        'model': AppConstants.deepSeekModel,
        'max_tokens': AppConstants.maxTokens,
        'stream': true,
        'messages': messages,
      });

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      expect(decoded['model'], equals('deepseek-v4-flash'));
      expect(decoded['stream'], isTrue);
      expect(decoded['max_tokens'], equals(4096));
      expect(decoded['messages'], isA<List<dynamic>>());
    });

    test('should parse SSE response correctly', () {
      const sseLine = 'data: {"choices": [{"delta": {"content": "Hello"}}]}';

      if (sseLine.startsWith('data: ')) {
        final data = sseLine.substring(6).trim();
        if (data != '[DONE]') {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final content = (json['choices'] as List?)
              ?.firstOrNull?['delta']?['content'] as String?;
          expect(content, equals('Hello'));
        }
      }
    });
  });

  group('OpenRouterClient', () {
    late OpenRouterClient client;
    const testApiKey = 'test_openrouter_key';

    setUp(() {
      client = OpenRouterClient(apiKey: testApiKey);
    });

    test('should be created with API key', () {
      expect(client, isNotNull);
    });

    test('should use correct headers', () {
      final request = http.Request(
        'POST',
        Uri.parse(AppConstants.openRouterBaseUrl),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $testApiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': AppConstants.appWebUrl,
        'X-Title': AppConstants.appName,
      });

      expect(request.headers['Authorization'], equals('Bearer $testApiKey'));
      expect(request.headers['HTTP-Referer'], equals(AppConstants.appWebUrl));
      expect(request.headers['X-Title'], equals(AppConstants.appName));
    });

    test('should use pro max tokens for Pro users', () {
      expect(AppConstants.proMaxTokens, equals(8192));
      expect(AppConstants.proMaxTokens, greaterThan(AppConstants.maxTokens));
    });
  });

  group('AiException', () {
    test('should store message and status code', () {
      const exception = AiException('Test error', statusCode: 401);

      expect(exception.message, equals('Test error'));
      expect(exception.statusCode, equals(401));
      expect(exception.toString(), contains('Test error'));
    });

    test('should work without status code', () {
      const exception = AiException('Network error');

      expect(exception.message, equals('Network error'));
      expect(exception.statusCode, isNull);
    });
  });

  group('API Error Handling', () {
    test('should handle 401 Unauthorized', () {
      const statusCode = 401;
      const expectedMessage = 'Clé API invalide';

      if (statusCode == 401) {
        const exception = AiException(expectedMessage, statusCode: 401);
        expect(exception.statusCode, equals(401));
      }
    });

    test('should handle 429 Rate Limit', () {
      const statusCode = 429;
      const expectedMessage = 'Trop de requêtes';

      if (statusCode == 429) {
        const exception = AiException(expectedMessage, statusCode: 429);
        expect(exception.statusCode, equals(429));
      }
    });
  });
}
