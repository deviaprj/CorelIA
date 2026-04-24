import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/api/api_config.dart';
import '../../../core/api/dio_client.dart';
import 'ai_client.dart';
import 'models/chat_request.dart';
import '../domain/message.dart';

/// Exception spécifique au service chat backend.
class ChatApiException implements Exception {
  final String message;
  final int? statusCode;

  const ChatApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ChatApiException($statusCode): $message';
}

/// Service proxy vers le backend FastAPI pour le chat IA.
///
/// Responsabilités :
/// - Envoyer les messages au backend avec JWT auth
/// - Recevoir le streaming SSE des réponses
/// - Gérer les fallback silencieux (Ollama local → Backend → Direct API)
class ChatApiService {
  final Dio _dio;

  ChatApiService({Dio? dio}) : _dio = dio ?? DioClientFactory.create();

  /// Stream une réponse depuis le backend.
  ///
  /// Le backend gère lui-même le chaînage fallback.
  Stream<String> streamChat({
    required String conversationId,
    required List<Message> history,
    String? systemPrompt,
    String? model,
    bool useSearch = false,
    bool useOllamaLocal = false,
    String? ollamaLocalUrl,
    int maxTokens = 4096,
  }) async* {
    final request = ChatRequest(
      conversationId: conversationId,
      messages: history.map(ChatMessage.fromDomain).toList(),
      systemPrompt: systemPrompt,
      model: model,
      useSearch: useSearch,
      useOllamaLocal: useOllamaLocal,
      ollamaLocalUrl: ollamaLocalUrl,
      maxTokens: maxTokens,
    );

    try {
      final response = await _dio.post(
        '/chat/stream',
        data: request.toJson(),
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
        ),
      );

      final stream = response.data.stream as Stream<List<int>>;
      final lines = stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') break;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final token = json['token'] as String?;
          if (token != null && token.isNotEmpty) yield token;
        } catch (_) {
          // Ligne non-JSON : ignorer ou logger en debug
          debugPrint('[ChatApi] Ligne SSE ignorée : $line');
        }
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      String message = 'Erreur de communication avec le serveur';
      if (data is Map && data['detail'] != null) {
        message = data['detail'] as String;
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        message = 'Connexion impossible. Vérifiez votre réseau.';
      }
      throw ChatApiException(message, statusCode: status);
    } catch (e) {
      throw ChatApiException(e.toString());
    }
  }

  /// Fallback direct vers l'API DeepSeek si le backend est injoignable.
  /// Cette méthode est un filet de sécurité ; les clés API ne sont utilisées
  /// qu'en dernier recours pour éviter une interruption totale du service.
  Stream<String> fallbackStream({
    required List<Message> history,
    String? systemPrompt,
    int maxTokens = 4096,
  }) {
    final client = DeepSeekClient(apiKey: ''); // Clé compilée utilisée par défaut
    return client.streamChat(
      messages: history.map((m) => m.toApiMap()).toList(),
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
    );
  }
}
