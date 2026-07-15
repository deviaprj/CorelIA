import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants.dart';

/// Service de generation et comparaison d'embeddings vectoriels.
///
/// Utilise Ollama local (nomic-embed-text, 768 dims) si disponible.
/// Fallback : bag-of-words + cosinus (leger, offline).
class EmbeddingService {
  final String _ollamaBaseUrl;
  final http.Client _httpClient;
  bool _ollamaAvailable = false;
  bool _checked = false;

  EmbeddingService({
    String? ollamaBaseUrl,
    http.Client? httpClient,
  })  : _ollamaBaseUrl = ollamaBaseUrl ?? 'http://localhost:11434',
        _httpClient = httpClient ?? http.Client();

  /// Verifie si Ollama est accessible.
  Future<bool> get isAvailable async {
    if (_checked) return _ollamaAvailable;
    try {
      final response = await _httpClient
          .get(Uri.parse('$_ollamaBaseUrl/api/tags'))
          .timeout(const Duration(seconds: 2));
      _ollamaAvailable = response.statusCode == 200;
    } catch (_) {
      _ollamaAvailable = false;
    }
    _checked = true;
    debugPrint('[EmbeddingService] Ollama available: $_ollamaAvailable');
    return _ollamaAvailable;
  }

  /// Genere un vecteur d'embedding pour un texte.
  ///
  /// Retourne un vecteur de 768 dimensions (Ollama) ou un sparse vector (fallback).
  Future<List<double>> embed(String text) async {
    if (await isAvailable) {
      return _ollamaEmbed(text);
    }
    return _bagOfWordsVector(text);
  }

  /// Similarite cosinus entre deux vecteurs.
  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      // Si tailles differentes (hybride Ollama/BOW), utiliser BOW
      return _bagOfWordsSimilarity(a, b);
    }
    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  // ── Ollama ────────────────────────────────────────────────────────────────

  Future<List<double>> _ollamaEmbed(String text) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_ollamaBaseUrl/api/embeddings'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': 'nomic-embed-text',
              'prompt': text,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final embedding = data['embedding'] as List<dynamic>;
        return embedding.cast<double>();
      }
    } catch (e) {
      debugPrint('[EmbeddingService] Ollama embed error: $e');
    }
    // Fallback
    return _bagOfWordsVector(text);
  }

  // ── Bag-of-Words fallback ─────────────────────────────────────────────────

  List<double> _bagOfWordsVector(String text) {
    final words = <String, int>{};
    final tokens = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\sÀ-ſ]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2);

    for (final word in tokens) {
      words[word] = (words[word] ?? 0) + 1;
    }

    // Conversion en vecteur sparse (on garde la map pour compatibilite)
    // Format special : [hash1, count1, hash2, count2, ...]
    final vector = <double>[];
    for (final entry in words.entries) {
      vector.add(entry.key.hashCode.toDouble());
      vector.add(entry.value.toDouble());
    }
    return vector;
  }

  double _bagOfWordsSimilarity(List<double> a, List<double> b) {
    final mapA = <int, int>{};
    for (var i = 0; i < a.length; i += 2) {
      mapA[a[i].toInt()] = a[i + 1].toInt();
    }
    final mapB = <int, int>{};
    for (var i = 0; i < b.length; i += 2) {
      mapB[b[i].toInt()] = b[i + 1].toInt();
    }

    final allKeys = {...mapA.keys, ...mapB.keys};
    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (final key in allKeys) {
      final va = mapA[key] ?? 0;
      final vb = mapB[key] ?? 0;
      dotProduct += va * vb;
    }
    for (final v in mapA.values) {
      normA += v * v;
    }
    for (final v in mapB.values) {
      normB += v * v;
    }

    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
}
