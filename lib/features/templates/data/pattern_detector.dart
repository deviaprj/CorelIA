import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../chat/data/embedding_service.dart';

/// Donnees d'une requete enregistree pour la detection de patterns.
class _RequestRecord {
  final String text;
  final List<double> embedding;
  final DateTime timestamp;

  _RequestRecord({
    required this.text,
    required this.embedding,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'embedding': embedding,
        'timestamp': timestamp.toIso8601String(),
      };

  factory _RequestRecord.fromJson(Map<String, dynamic> json) => _RequestRecord(
        text: json['text'] as String,
        embedding: (json['embedding'] as List<dynamic>).cast<double>(),
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

/// Cluster de requetes similaires — candidat pour un template.
class PatternSuggestion {
  final String name;
  final String description;
  final String suggestedCategory;
  final String suggestedContent;
  final List<String> exampleRequests;
  final double confidence;

  const PatternSuggestion({
    required this.name,
    required this.description,
    required this.suggestedCategory,
    required this.suggestedContent,
    required this.exampleRequests,
    required this.confidence,
  });
}

/// Detecteur de patterns recurrents dans les requetes utilisateur.
///
/// Utilise les embeddings pour grouper les requetes similaires et suggerer
/// des templates lorsque des patterns se repetent.
class PatternDetector {
  static const String _prefsKey = 'pattern_detector_records';
  static const int _checkInterval = 20; // Verifier tous les 20 messages
  static const int _minClusterSize = 5; // Au moins 5 requetes similaires
  static const double _similarityThreshold = 0.82;

  final EmbeddingService _embeddingService;
  final List<_RequestRecord> _records = [];
  int _messageCount = 0;
  bool _loaded = false;

  PatternDetector({EmbeddingService? embeddingService})
      : _embeddingService = embeddingService ?? EmbeddingService();

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final e in list) {
          _records.add(_RequestRecord.fromJson(e as Map<String, dynamic>));
        }
      } catch (e) {
        debugPrint('[PatternDetector] Load error: $e');
      }
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _records.map((r) => r.toJson()).toList();
    // Garder les 500 plus recents max
    final trimmed = jsonList.length > 500
        ? jsonList.sublist(jsonList.length - 500)
        : jsonList;
    await prefs.setString(_prefsKey, jsonEncode(trimmed));
  }

  /// Enregistre une requete utilisateur et verifie les patterns.
  ///
  /// Retourne une suggestion si un pattern recurrent est detecte.
  Future<PatternSuggestion?> recordRequest(String text) async {
    await _ensureLoaded();

    // Generer l'embedding
    final embedding = await _embeddingService.embed(text);

    // Stocker
    _records.add(_RequestRecord(
      text: text,
      embedding: embedding,
      timestamp: DateTime.now(),
    ));

    // Garder max 500
    while (_records.length > 500) {
      _records.removeAt(0);
    }

    _messageCount++;
    await _persist();

    // Verifier les patterns periodiquement
    if (_messageCount % _checkInterval == 0) {
      return _detectPatterns();
    }

    return null;
  }

  /// Analyse les records pour trouver des clusters de requetes similaires.
  Future<PatternSuggestion?> _detectPatterns() async {
    if (_records.length < _minClusterSize * 2) return null;

    // Trouver les paires similaires
    final clusters = <List<int>>[];

    for (var i = 0; i < _records.length; i++) {
      var foundCluster = false;
      for (final cluster in clusters) {
        // Comparer au premier element du cluster
        final sim = _embeddingService.cosineSimilarity(
          _records[i].embedding,
          _records[cluster.first].embedding,
        );
        if (sim >= _similarityThreshold) {
          cluster.add(i);
          foundCluster = true;
          break;
        }
      }
      if (!foundCluster) {
        clusters.add([i]);
      }
    }

    // Trouver le plus grand cluster
    List<int>? bestCluster;
    for (final cluster in clusters) {
      if (cluster.length >= _minClusterSize) {
        if (bestCluster == null || cluster.length > bestCluster.length) {
          bestCluster = cluster;
        }
      }
    }

    if (bestCluster == null) return null;

    // Creer une suggestion a partir du cluster
    final exampleRequests =
        bestCluster.take(5).map((i) => _records[i].text).toList();

    // Utiliser la requete la plus representative (la plus recente) comme base
    final baseText = _records[bestCluster.last].text;

    // Extraire une categorie suggeree
    final category = _guessCategory(exampleRequests);

    // Generer un nom de template
    final name = _generateTemplateName(category, exampleRequests);

    return PatternSuggestion(
      name: name,
      description: 'Pattern detecte (${bestCluster.length} requetes similaires)',
      suggestedCategory: category,
      suggestedContent: baseText,
      exampleRequests: exampleRequests,
      confidence: (bestCluster.length / _minClusterSize).clamp(0.0, 1.0),
    );
  }

  String _guessCategory(List<String> requests) {
    final text = requests.join(' ').toLowerCase();
    if (text.contains('mail') || text.contains('email') || text.contains('envoyer')) {
      return 'email';
    }
    if (text.contains('rapport') || text.contains('compte rendu') || text.contains('bilan')) {
      return 'report';
    }
    if (text.contains('presentation') || text.contains('diapo') || text.contains('slides')) {
      return 'presentation';
    }
    if (text.contains('cherche') || text.contains('trouve') || text.contains('recherche')) {
      return 'search';
    }
    return 'general';
  }

  String _generateTemplateName(String category, List<String> requests) {
    final labels = {
      'email': 'Email type',
      'report': 'Rapport recurrent',
      'presentation': 'Presentation type',
      'search': 'Recherche frequente',
      'general': 'Template suggere',
    };
    return '${labels[category] ?? "Template"} (${requests.length}×)';
  }

  /// Reinitialise les donnees (debug / RGPD).
  Future<void> clear() async {
    _records.clear();
    _messageCount = 0;
    await _persist();
  }

  /// Nombre de records stockes.
  int get recordCount => _records.length;
}

/// Singleton du detecteur de patterns.
final patternDetector = PatternDetector();
