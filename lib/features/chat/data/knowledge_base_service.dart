import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Entree de la base de connaissances conversationnelle.
class _KnowledgeEntry {
  final String query;
  final String response;
  final Map<String, int> vector;
  final DateTime createdAt;

  _KnowledgeEntry({
    required this.query,
    required this.response,
    required this.vector,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'query': query,
    'response': response,
    'vector': vector,
    'createdAt': createdAt.toIso8601String(),
  };

  factory _KnowledgeEntry.fromJson(Map<String, dynamic> json) => _KnowledgeEntry(
    query: json['query'] as String,
    response: json['response'] as String,
    vector: (json['vector'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v as int),
    ),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// Base de connaissances locale pour ameliorer les reponses futures.
///
/// Approche : bag-of-words + similarite cosinus. Legere, sans dependance
/// externe, fonctionne 100% offline.
class KnowledgeBaseService {
  static const String _prefsKey = 'knowledge_base_entries';
  static const int _maxEntries = 200;
  static const double _similarityThreshold = 0.72;

  List<_KnowledgeEntry> _entries = [];
  bool _loaded = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Charge les entrees depuis SharedPreferences.
  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _entries = list.map((e) => _KnowledgeEntry.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        debugPrint('[KnowledgeBase] init error: $e');
        _entries = [];
      }
    }
    _loaded = true;
  }

  /// Ajoute une Q/R reussie a la base.
  Future<void> add(String query, String response) async {
    await init();
    final vector = _buildVector(query);
    final entry = _KnowledgeEntry(
      query: query,
      response: response,
      vector: vector,
      createdAt: DateTime.now(),
    );
    _entries.add(entry);
    // Garder les plus recents si depassement
    if (_entries.length > _maxEntries) {
      _entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _entries = _entries.take(_maxEntries).toList();
    }
    await _persist();
    debugPrint('[KnowledgeBase] Entry added: "${query.substring(0, min(query.length, 30))}..."');
  }

  /// Cherche les meilleures reponses pour une requete.
  /// Retourne une liste de [response] tries par similarite decroissante.
  Future<List<String>> findSimilar(String query, {int limit = 3}) async {
    await init();
    if (_entries.isEmpty) return const [];

    final queryVector = _buildVector(query);
    final scored = _entries.map((e) {
      final sim = _cosineSimilarity(queryVector, e.vector);
      return MapEntry(e.response, sim);
    }).toList();

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored
        .where((s) => s.value >= _similarityThreshold)
        .take(limit)
        .map((s) => s.key)
        .toList();
  }

  /// Retourne un contexte systeme injectable si une reponse similaire existe.
  Future<String?> buildContextHint(String query) async {
    final similar = await findSimilar(query, limit: 1);
    if (similar.isEmpty) return null;
    return 'Contexte precedent utile : ${similar.first}';
  }

  /// Nombre d'entrees stockees.
  int get entryCount => _entries.length;

  /// Supprime toutes les entrees (debug / RGPD).
  Future<void> clear() async {
    _entries.clear();
    await _persist();
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Map<String, int> _buildVector(String text) {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\sÀ-ſ]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();

    final vector = <String, int>{};
    for (final word in words) {
      vector[word] = (vector[word] ?? 0) + 1;
    }
    return vector;
  }

  double _cosineSimilarity(Map<String, int> a, Map<String, int> b) {
    final allKeys = {...a.keys, ...b.keys};
    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (final key in allKeys) {
      final va = a[key] ?? 0;
      final vb = b[key] ?? 0;
      dotProduct += va * vb;
    }

    for (final v in a.values) {
      normA += v * v;
    }
    for (final v in b.values) {
      normB += v * v;
    }

    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _entries.map((e) => e.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(jsonList));
  }
}
