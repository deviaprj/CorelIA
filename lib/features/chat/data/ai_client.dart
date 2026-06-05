import 'dart:convert';
import 'package:flutter/foundation.dart';
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
    bool enableSearch = true,
    String? model,
    double? temperature,
  }) async* {
    if (apiKey.isEmpty) {
      throw const AiException('Clé API DeepSeek manquante', statusCode: 401);
    }

    final bodyMap = <String, dynamic>{
      'model': model ?? AppConstants.deepSeekModel,
      'stream': true,
      'messages': [
        if (systemPrompt != null && systemPrompt.isNotEmpty)
          {'role': 'system', 'content': systemPrompt},
        ...messages,
      ],
    };

    // DeepSeek Reasoner uses max_completion_tokens instead of max_tokens
    final effectiveModel = model ?? AppConstants.deepSeekModel;
    if (effectiveModel == AppConstants.deepSeekReasonerModel) {
      bodyMap['max_completion_tokens'] = maxTokens;
    } else {
      bodyMap['max_tokens'] = maxTokens;
    }

    if (temperature != null) {
      bodyMap['temperature'] = temperature;
    }

    if (enableSearch) {
      bodyMap['enable_search'] = true;
    }

    final body = jsonEncode(bodyMap);

    final request = http.Request('POST', Uri.parse(AppConstants.deepSeekBaseUrl))
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = body;

    debugPrint('[DeepSeek] Request body: $body');

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
      final errBody = await response.stream.bytesToString();
      debugPrint('[DeepSeek] Error ${response.statusCode}: $errBody');
      throw AiException('Erreur API ${response.statusCode}: $errBody',
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
        final delta = (json['choices'] as List?)?.firstOrNull?['delta'];
        if (delta == null) continue;
        // DeepSeek Reasoner: skip reasoning_content (chain-of-thought)
        // Only yield the final 'content' output
        final content = delta['content'] as String?;
        if (content != null && content.isNotEmpty) yield content;
      } catch (_) {}
    }
  }
}

/// Client OpenRouter pour modèles Pro et gratuits
class OpenRouterClient {
  final String apiKey;
  OpenRouterClient({required this.apiKey});

  Stream<String> streamChat({
    required List<Map<String, dynamic>> messages,
    required String model,
    String? systemPrompt,
    int maxTokens = AppConstants.proMaxTokens,
    double? temperature,
    double? topP,
    double? frequencyPenalty,
  }) async* {
    final bodyMap = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'stream': true,
      'messages': [
        if (systemPrompt != null && systemPrompt.isNotEmpty)
          {'role': 'system', 'content': systemPrompt},
        ...messages,
      ],
    };
    if (temperature != null) bodyMap['temperature'] = temperature;
    if (topP != null) bodyMap['top_p'] = topP;
    if (frequencyPenalty != null) bodyMap['frequency_penalty'] = frequencyPenalty;

    final body = jsonEncode(bodyMap);

    final request =
        http.Request('POST', Uri.parse(AppConstants.openRouterBaseUrl))
          ..headers.addAll({
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'HTTP-Referer': AppConstants.appWebUrl,
            'X-Title': AppConstants.appName,
          })
          ..body = body;

    final http.StreamedResponse response;
    try {
      response = await _httpClient.send(request);
    } catch (e) {
      throw AiException('Erreur réseau OpenRouter : $e');
    }
    if (response.statusCode == 429) {
      throw const AiException('OpenRouter limite de requetes atteinte', statusCode: 429);
    }
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

