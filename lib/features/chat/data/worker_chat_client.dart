import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';
import 'ai_client.dart';

/// Client de chat via le Worker Cloudflare (api.zentic.fr/chat).
///
/// Le Worker Cloudflare est le point d'entrée sécurisé pour toutes les
/// requêtes LLM. Il gère :
/// - La chaîne de fallback (Workers AI → DeepSeek → OpenRouter)
/// - Le rate limiting (100 req/min/IP)
/// - La sanitization des entrées (prompt injection, XSS)
/// - L'authentification par clé secrète partagée
///
/// Les clés API DeepSeek/OpenRouter sont stockées uniquement dans les
/// secrets du Worker, jamais dans l'APK client.
class WorkerChatClient {
  final String _apiSecretKey;
  final String _chatUrl;

  WorkerChatClient({
    String? chatUrl,
    String? apiSecretKey,
  })  : _chatUrl = chatUrl ?? AppConstants.workerChatUrl,
        _apiSecretKey = apiSecretKey ?? AppConstants.apiSecretKey;

  /// Vérifie si le Worker est configuré et joignable.
  bool get isConfigured =>
      _chatUrl.isNotEmpty && _apiSecretKey.isNotEmpty;

  /// Stream une réponse du Worker Cloudflare via SSE.
  ///
  /// Le Worker route automatiquement vers le meilleur modèle disponible.
  /// [messages] : historique au format API ([{'role': 'user', 'content': '...'}]).
  /// [model] : override du modèle (optionnel, laissé à 'auto' par défaut).
  /// [temperature] : créativité (0.0-2.0).
  /// [maxTokens] : longueur max de la réponse.
  Stream<String> streamChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    if (!isConfigured) {
      throw const AiException(
        'Worker Cloudflare non configuré. Vérifiez BACKEND_URL et API_SECRET_KEY.',
      );
    }

    final bodyMap = <String, dynamic>{
      'messages': messages,
      'stream': true,
      'temperature': temperature,
      'max_tokens': maxTokens,
    };
    if (model != null && model.isNotEmpty) {
      bodyMap['model'] = model;
    }

    final body = jsonEncode(bodyMap);
    debugPrint('[WorkerChat] → $_chatUrl (${messages.length} messages)');

    final request = http.Request('POST', Uri.parse(_chatUrl))
      ..headers.addAll({
        'Authorization': 'Bearer $_apiSecretKey',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = body;

    final http.StreamedResponse response;
    try {
      response = await request.send();
    } catch (e) {
      throw AiException('Erreur réseau vers le Worker : $e');
    }

    if (response.statusCode == 401) {
      throw const AiException(
        'Authentification Worker échouée. Vérifiez API_SECRET_KEY.',
        statusCode: 401,
      );
    }
    if (response.statusCode == 429) {
      throw const AiException(
        'Trop de requêtes. Réessayez dans une minute.',
        statusCode: 429,
      );
    }
    if (response.statusCode == 400) {
      final errBody = await response.stream.bytesToString();
      debugPrint('[WorkerChat] 400: $errBody');
      throw AiException('Requête invalide : $errBody', statusCode: 400);
    }
    if (response.statusCode == 502) {
      throw const AiException(
        'Service IA temporairement indisponible. Réessayez.',
        statusCode: 502,
      );
    }
    if (response.statusCode != 200) {
      final errBody = await response.stream.bytesToString();
      throw AiException(
        'Erreur Worker ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    // ── Parser le flux SSE du Worker ──
    // Le Worker renvoie des chunks SSE au format :
    //   data: {"content":"..."}      (Workers AI)
    //   data: {"choices":[{"delta":{"content":"..."}}]}  (DeepSeek/OpenRouter)
    //   data: [DONE]
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data == '[DONE]') break;

      try {
        final json = jsonDecode(data) as Map<String, dynamic>;

        // Format Workers AI : {"content": "..."}
        final directContent = json['content'] as String?;
        if (directContent != null && directContent.isNotEmpty) {
          yield directContent;
          continue;
        }

        // Format DeepSeek/OpenRouter : {"choices": [{...}]}
        final choices = json['choices'] as List?;
        if (choices != null) {
          for (final choice in choices) {
            if (choice is Map<String, dynamic>) {
              final delta = choice['delta'] as Map<String, dynamic>?;
              if (delta != null) {
                final content = delta['content'] as String?;
                if (content != null && content.isNotEmpty) {
                  yield content;
                }
              }
            }
          }
        }
      } catch (_) {
        // Ligne non parseable — ignorer
      }
    }
  }

  /// Version non-streaming : collecte toute la réponse puis la retourne.
  Future<String> completeChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async {
    if (!isConfigured) {
      throw const AiException('Worker Cloudflare non configuré.');
    }

    final body = jsonEncode({
      'messages': messages,
      'stream': false,
      'temperature': temperature,
      'max_tokens': maxTokens,
      if (model != null && model.isNotEmpty) 'model': model,
    });

    final response = await http.post(
      Uri.parse(_chatUrl),
      headers: {
        'Authorization': 'Bearer $_apiSecretKey',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['message']?['content'] as String? ?? '';
    }

    throw AiException(
      'Worker chat failed: ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }
}
