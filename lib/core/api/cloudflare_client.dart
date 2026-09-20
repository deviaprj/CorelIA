import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'ai_client.dart';

/// Client de chat via le Worker Cloudflare (`$WORKER_URL/chat`).
///
/// Le Worker est la passerelle unique vers les modèles : il détient les clés
/// (secrets `wrangler`), applique le routage/fallback, le rate limiting et la
/// sanitisation des entrées. L'APK n'embarque aucune clé de fournisseur IA.
class CloudflareWorkerClient {
  const CloudflareWorkerClient({
    required this.chatUrl,
    required this.apiKey,
  });

  /// Endpoint SSE du Worker (ex. `https://api.zentic.fr/chat`).
  final String chatUrl;

  /// Clé publique (soft gate) envoyée dans `X-API-Key`.
  final String apiKey;

  bool get isConfigured => chatUrl.isNotEmpty;

  /// Stream une réponse du Worker.
  ///
  /// Le Worker peut répondre au format Workers AI (`{"content": "..."}`) ou
  /// OpenAI (`{"choices":[{"delta":{"content":"..."}}]}`) : les deux sont gérés.
  Stream<String> streamChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double temperature = 0.7,
    int maxTokens = AppConfig.maxTokens,
  }) async* {
    if (!isConfigured) {
      throw const AiException(
        'Worker Cloudflare non configuré (CLOUDFLARE_WORKER_URL manquant).',
      );
    }

    final body = jsonEncode({
      'messages': messages,
      'stream': true,
      'temperature': temperature,
      'max_tokens': maxTokens,
      if (model != null && model.isNotEmpty) 'model': model,
    });

    final request = http.Request('POST', Uri.parse(chatUrl))
      ..headers.addAll({
        if (apiKey.isNotEmpty) 'X-API-Key': apiKey,
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = body;

    final http.StreamedResponse response;
    try {
      response = await aiHttpClient.send(request).timeout(AppConfig.workerTimeout);
    } catch (e) {
      throw AiException('Worker injoignable : $e');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AiException(
        'Authentification Worker refusée (vérifiez CLIENT_API_KEY).',
        statusCode: 401,
      );
    }
    if (response.statusCode == 429) {
      throw const AiException('Trop de requêtes, réessayez plus tard',
          statusCode: 429);
    }
    if (response.statusCode >= 500) {
      throw AiException(
        'Service IA temporairement indisponible (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      final err = await response.stream.bytesToString();
      debugPrint('[CloudflareWorker] ${response.statusCode}: $err');
      throw AiException('Erreur Worker ${response.statusCode}',
          statusCode: response.statusCode);
    }

    await for (final line
        in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data == '[DONE]') break;

      try {
        final json = jsonDecode(data) as Map<String, dynamic>;

        // Format Workers AI.
        final direct = json['content'] as String?;
        if (direct != null && direct.isNotEmpty) {
          yield direct;
          continue;
        }

        // Format OpenAI (DeepSeek/Workers AI compatible).
        final delta = (json['choices'] as List?)?.firstOrNull?['delta'];
        final content = delta is Map ? delta['content'] as String? : null;
        if (content != null && content.isNotEmpty) yield content;
      } catch (_) {
        // Ligne SSE non parsable : ignorée.
      }
    }
  }
}
