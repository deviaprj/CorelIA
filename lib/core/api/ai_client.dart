import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Exception IA : porte le code HTTP et un message lisible.
class AiException implements Exception {
  const AiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'AiException($statusCode): $message';
}

/// Client HTTP partagé par tous les fournisseurs IA : un seul pool de
/// connexions par process.
final http.Client aiHttpClient = http.Client();

/// Convertit une [AiException] en message utilisateur.
String formatAiError(AiException e) {
  final msg = e.message;
  if (msg.contains('image') || msg.contains('image_url')) {
    return "Analyse d'image indisponible pour le moment. Réessayez plus tard.";
  }
  if (msg.contains('Clé API') || msg.contains('Worker')) return msg;
  if (msg.contains('429') || msg.contains('Trop de requêtes')) {
    return 'Limite de requêtes atteinte. Réessayez dans un instant.';
  }
  return 'Erreur IA. Réessayez.';
}

/// Envoie une requête POST et expose le flux SSE sous forme de chunks texte
/// `content` (format OpenAI/DeepSeek).
Stream<String> streamOpenAiSse({
  required String url,
  required Map<String, String> headers,
  required String body,
  required String providerLabel,
  Duration timeout = const Duration(seconds: 120),
}) async* {
  final request = http.Request('POST', Uri.parse(url))
    ..headers.addAll(headers)
    ..body = body;

  final http.StreamedResponse response;
  try {
    response = await aiHttpClient.send(request).timeout(timeout);
  } catch (e) {
    throw AiException('Erreur réseau : $e');
  }

  if (response.statusCode == 401) {
    throw const AiException('Clé API invalide', statusCode: 401);
  }
  if (response.statusCode == 429) {
    throw const AiException('Trop de requêtes, réessayez plus tard',
        statusCode: 429);
  }
  if (response.statusCode != 200) {
    final err = await response.stream.bytesToString();
    debugPrint('[$providerLabel] Erreur ${response.statusCode}: $err');
    throw AiException('Erreur API ${response.statusCode}',
        statusCode: response.statusCode);
  }

  await for (final line
      in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
    if (!line.startsWith('data: ')) continue;
    final data = line.substring(6).trim();
    if (data == '[DONE]') break;
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final delta = (json['choices'] as List?)?.firstOrNull?['delta'];
      final content = delta is Map ? delta['content'] as String? : null;
      if (content != null && content.isNotEmpty) yield content;
    } catch (_) {
      // Événement SSE non parsable : ignoré.
    }
  }
}

/// Client DeepSeek direct.
///
/// Utilisé uniquement en développement ou lorsque le Worker Cloudflare n'est
/// pas configuré : en production, les clés vivent côté Worker et le client
/// mobile passe par [CloudflareWorkerClient].
class DeepSeekClient {
  const DeepSeekClient({required this.apiKey});

  final String apiKey;

  Stream<String> streamChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    int maxTokens = AppConfig.maxTokens,
    double? temperature,
    bool enableSearch = false,
  }) {
    if (apiKey.isEmpty) {
      throw const AiException('Clé API DeepSeek manquante', statusCode: 401);
    }

    final effectiveModel = model ?? AppConfig.deepSeekModel;
    final body = <String, dynamic>{
      'model': effectiveModel,
      'stream': true,
      'messages': messages,
      if (temperature != null) 'temperature': temperature,
      if (enableSearch) 'enable_search': true,
      // DeepSeek Reasoner utilise max_completion_tokens.
      if (effectiveModel == AppConfig.deepSeekReasonerModel)
        'max_completion_tokens': maxTokens
      else
        'max_tokens': maxTokens,
    };

    return streamOpenAiSse(
      url: AppConfig.deepSeekBaseUrl,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      },
      body: jsonEncode(body),
      providerLabel: 'DeepSeek',
    );
  }
}
