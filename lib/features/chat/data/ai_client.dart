import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';
import '../../../core/logger.dart';

final _log = const AppLogger('AiClient');

/// Exception IA — porte le code HTTP et le message
class AiException implements Exception {
  final String message;
  final int? statusCode;
  const AiException(this.message, {this.statusCode});
  @override
  String toString() => 'AiException($statusCode): $message';
}

/// Durees de timeout pour les appels API IA.
const _connectTimeout = Duration(seconds: 15);
const _streamIdleTimeout = Duration(seconds: 120);

/// Cree un client HTTP avec timeout de connexion.
http.Client _createClient() {
  final client = http.Client();
  return _TimeoutClient(client, _connectTimeout);
}

/// Wrapper HTTP client qui applique un timeout de connexion.
/// Le package `http` ne supporte pas nativement les timeouts.
class _TimeoutClient extends http.BaseClient {
  final http.Client _inner;
  final Duration _timeout;

  _TimeoutClient(this._inner, this._timeout);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request).timeout(
      _timeout,
      onTimeout: () =>
          throw const AiException('Delai de connexion depasse. Verifiez votre reseau.'),
    );
  }

  @override
  void close() => _inner.close();
}

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
      throw const AiException('Cle API DeepSeek manquante', statusCode: 401);
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

    _log.info('Sending request', {'model': effectiveModel, 'bodySize': body.length});

    final client = _createClient();
    try {
      final http.StreamedResponse response;
      try {
        response = await client.send(request);
      } on TimeoutException {
        throw const AiException('DeepSeek ne repond pas. Verifiez votre connexion.');
      } catch (e) {
        throw AiException('Erreur reseau : $e');
      }

      if (response.statusCode == 401) {
        throw const AiException('Cle API invalide', statusCode: 401);
      }
      if (response.statusCode == 429) {
        throw const AiException('Trop de requetes, reessayez dans un moment', statusCode: 429);
      }
      if (response.statusCode != 200) {
        final errBody = await response.stream.bytesToString();
        _log.error('API error', {'statusCode': response.statusCode, 'body': errBody});
        throw AiException('Erreur API ${response.statusCode}: $errBody',
            statusCode: response.statusCode);
      }

      // Stream avec timeout d'inactivite : si aucun token pendant 120s, on arrete
      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(_streamIdleTimeout, onTimeout: (sink) {
            _log.warn('Stream idle timeout — no tokens received for ${_streamIdleTimeout.inSeconds}s');
            sink.close();
          });

      await for (final line in stream) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') break;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final delta = (json['choices'] as List?)?.firstOrNull?['delta'];
          if (delta == null) continue;
          // DeepSeek Reasoner: skip reasoning_content (chain-of-thought)
          final content = delta['content'] as String?;
          if (content != null && content.isNotEmpty) yield content;
        } catch (_) {}
      }
    } finally {
      client.close();
    }
  }
}

/// Client OpenRouter pour modeles Pro et gratuits
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

    _log.info('Sending request', {'model': model, 'bodySize': body.length});

    final client = _createClient();
    try {
      final http.StreamedResponse response;
      try {
        response = await client.send(request);
      } on TimeoutException {
        throw const AiException('OpenRouter ne repond pas. Verifiez votre connexion.');
      } catch (e) {
        throw AiException('Erreur reseau OpenRouter : $e');
      }

      if (response.statusCode == 429) {
        throw const AiException('OpenRouter limite de requetes atteinte', statusCode: 429);
      }
      if (response.statusCode != 200) {
        final err = await response.stream.bytesToString();
        _log.error('API error', {'statusCode': response.statusCode, 'body': err});
        throw AiException('OpenRouter error ${response.statusCode}: $err',
            statusCode: response.statusCode);
      }

      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(_streamIdleTimeout, onTimeout: (sink) {
            _log.warn('Stream idle timeout');
            sink.close();
          });

      await for (final line in stream) {
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
    } finally {
      client.close();
    }
  }
}
