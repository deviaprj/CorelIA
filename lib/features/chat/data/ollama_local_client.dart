import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../../../core/api/api_config.dart';

/// Client pour détecter et communiquer avec un serveur Ollama local.
///
/// Ollama local écoute par défaut sur `http://localhost:11434`.
/// Sur Android emulator, `localhost` du host est `10.0.2.2`.
/// Sur iOS simulator, `localhost` est accessible directement.
class OllamaLocalClient {
  static const _defaultPort = 11434;
  static final List<String> _candidateHosts = _buildCandidates();

  static List<String> _buildCandidates() {
    if (kIsWeb) return []; // Pas d'Ollama local en web pur
    if (Platform.isAndroid) {
      return [
        'http://10.0.2.2:$_defaultPort', // Android emulator → host
        'http://192.168.1.1:$_defaultPort', // Réseau local typique
        'http://localhost:$_defaultPort',
      ];
    }
    return [
      'http://localhost:$_defaultPort',
      'http://127.0.0.1:$_defaultPort',
    ];
  }

  /// URL d'un serveur Ollama local détecté, ou `null`.
  String? _detectedUrl;

  /// Retourne l'URL détectée ou `null`.
  String? get detectedUrl => _detectedUrl;

  /// Scan rapide pour trouver un serveur Ollama actif.
  /// Retourne l'URL du premier serveur répondant en < 500ms.
  Future<String?> detectLocalServer() async {
    if (kIsWeb) return null;

    for (final host in _candidateHosts) {
      try {
        final response = await http
            .get(Uri.parse('$host/api/tags'))
            .timeout(const Duration(milliseconds: 800));
        if (response.statusCode == 200) {
          _detectedUrl = host;
          debugPrint('[OllamaLocal] Serveur détecté : $host');
          return host;
        }
      } catch (_) {
        // Silencieux : on essaie le prochain candidat
      }
    }
    _detectedUrl = null;
    return null;
  }

  /// Liste les modèles disponibles sur le serveur local.
  Future<List<String>> listModels() async {
    final url = _detectedUrl ?? await detectLocalServer();
    if (url == null) return [];

    final response = await http.get(Uri.parse('$url/api/tags'));
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final models = (data['models'] as List?) ?? <dynamic>[];
    return models
        .map((m) => (m as Map<String, dynamic>)['name'] as String?)
        .whereType<String>()
        .toList();
  }

  /// Stream une réponse depuis Ollama local (endpoint `/api/chat`).
  Stream<String> streamChat({
    required List<Map<String, dynamic>> messages,
    String model = 'llama3.2',
    String? systemPrompt,
    int maxTokens = 4096,
  }) async* {
    final url = _detectedUrl ?? await detectLocalServer();
    if (url == null) {
      throw Exception(
        'Aucun serveur Ollama local détecté. '
        'Vérifiez que Ollama est lancé (http://localhost:11434).',
      );
    }

    final body = jsonEncode({
      'model': model,
      'stream': true,
      'messages': [
        if (systemPrompt != null && systemPrompt.isNotEmpty)
          {'role': 'system', 'content': systemPrompt},
        ...messages,
      ],
      'options': {'num_predict': maxTokens},
    });

    final request = http.Request('POST', Uri.parse('$url/api/chat'))
      ..headers['Content-Type'] = 'application/json'
      ..body = body;

    final streamedResponse = await http.Client().send(request);
    if (streamedResponse.statusCode != 200) {
      final err = await streamedResponse.stream.bytesToString();
      throw Exception('Ollama local error ${streamedResponse.statusCode}: $err');
    }

    await for (final line in streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final message = json['message'] as Map<String, dynamic>?;
        final content = message?['content'] as String?;
        if (content != null && content.isNotEmpty) yield content;

        final done = json['done'] as bool?;
        if (done == true) break;
      } catch (_) {
        // Ignorer les lignes malformées
      }
    }
  }
}
