import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';

/// Exception IA — porte le code HTTP et le message
class AiException implements Exception {
  final String message;
  final int? statusCode;
  const AiException(this.message, {this.statusCode});
  @override
  String toString() => 'AiException($statusCode): $message';
}

/// Singleton HTTP client pour éviter les fuites mémoire
final _httpClient = http.Client();

/// Client DeepSeek-V3 avec streaming SSE
class DeepSeekClient {
  final String apiKey;
  DeepSeekClient({required this.apiKey});

  Stream<String> streamChat({
    required List<Map<String, dynamic>> messages,
    String? systemPrompt,
    int maxTokens = AppConstants.maxTokens,
  }) async* {
    if (apiKey.isEmpty) {
      throw const AiException('Clé API DeepSeek manquante', statusCode: 401);
    }

    final body = jsonEncode({
      'model': AppConstants.deepSeekModel,
      'max_tokens': maxTokens,
      'stream': true,
      'messages': [
        if (systemPrompt != null && systemPrompt.isNotEmpty)
          {'role': 'system', 'content': systemPrompt},
        ...messages,
      ],
    });

    final request = http.Request('POST', Uri.parse(AppConstants.deepSeekBaseUrl))
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = body;

    final http.StreamedResponse response;
    try {
      response = await _httpClient.send(request);
    } catch (e) {
      throw AiException('Erreur réseau : $e');
    }

    if (response.statusCode == 401) {
      throw const AiException('Clé API invalide', statusCode: 401);
    }
    if (response.statusCode == 429) {
      throw const AiException('Trop de requêtes, réessayez dans un moment', statusCode: 429);
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw AiException('Erreur API ${response.statusCode}: $body',
          statusCode: response.statusCode);
    }

    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data == '[DONE]') break;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final content = (json['choices'] as List?)
            ?.firstOrNull?['delta']?['content'] as String?;
        if (content != null && content.isNotEmpty) yield content;
      } catch (_) {}
    }
  }
}

/// Client OpenRouter pour modèles Pro (Mistral / Groq)
class OpenRouterClient {
  final String apiKey;
  OpenRouterClient({required this.apiKey});

  Stream<String> streamChat({
    required List<Map<String, dynamic>> messages,
    required String model,
    String? systemPrompt,
    int maxTokens = AppConstants.proMaxTokens,
  }) async* {
    final body = jsonEncode({
      'model': model,
      'max_tokens': maxTokens,
      'stream': true,
      'messages': [
        if (systemPrompt != null && systemPrompt.isNotEmpty)
          {'role': 'system', 'content': systemPrompt},
        ...messages,
      ],
    });

    final request =
        http.Request('POST', Uri.parse(AppConstants.openRouterBaseUrl))
          ..headers.addAll({
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'HTTP-Referer': AppConstants.appWebUrl,
            'X-Title': AppConstants.appName,
          })
          ..body = body;

    final response = await _httpClient.send(request);
    if (response.statusCode != 200) {
      final err = await response.stream.bytesToString();
      throw AiException('OpenRouter error ${response.statusCode}: $err',
          statusCode: response.statusCode);
    }

    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data == '[DONE]') break;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final content = (json['choices'] as List?)
            ?.firstOrNull?['delta']?['content'] as String?;
        if (content != null && content.isNotEmpty) yield content;
      } catch (_) {}
    }
  }
}
