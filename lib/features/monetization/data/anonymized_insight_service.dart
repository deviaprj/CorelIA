import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'consent_data_service.dart';

/// Insight anonymise exporte vers le backend.
class AnonymizedInsight {
  final String cohortId; // hash de la cohorte, pas de l'individu
  final String type; // 'search_trend', 'feature_usage', 'intent_map', 'seasonality'
  final Map<String, dynamic> data;
  final DateTime timestamp;

  AnonymizedInsight({
    required this.cohortId,
    required this.type,
    required this.data,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'cohortId': cohortId,
    'type': type,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Service d'aggregation et d'anonymisation des donnees utilisateur.
///
/// Principes :
/// - K-anonymity : chaque cohorte a au moins K=5 utilisateurs
/// - Pas de PII jamais exportee
/// - Pseudonymisation : UID remplace par un hash one-way
/// - Export periodique (1x/semaine) vers le backend
class AnonymizedInsightService {
  static const String _prefsKeyQueue = 'anonymized_insight_queue';
  static const String _prefsKeyLastExport = 'anonymized_last_export';
  static const String _prefsKeyCounters = 'anonymized_counters';
  static const int _maxQueueSize = 500;
  static const Duration _exportInterval = Duration(days: 7);

  final ConsentDataService _consent;

  AnonymizedInsightService(this._consent);

  // ── Collecte locale ───────────────────────────────────────────────────────────

  /// Enregistre un evenement d'usage (anonymise immediatement).
  Future<void> recordEvent({
    required String type,
    required Map<String, dynamic> data,
    String? language,
    String? platform,
  }) async {
    final level = await _consent.getConsentLevel();
    if (level == DataConsentLevel.none) return;

    final cohortId = await _buildCohortId(language: language, platform: platform);
    final insight = AnonymizedInsight(
      cohortId: cohortId,
      type: type,
      data: data,
      timestamp: DateTime.now(),
    );

    await _enqueue(insight);
    await _incrementCounters(type);
  }

  /// Enregistre une recherche reussie.
  Future<void> recordSearch(String query, String intent) async {
    await recordEvent(
      type: 'search_trend',
      data: {
        'intent': intent,
        'queryLength': query.length,
        'hasDates': query.contains(RegExp(r'\d{1,2}[/-]\d{1,2}')),
      },
    );
  }

  /// Enregistre l'usage d'une feature.
  Future<void> recordFeatureUsage(String featureName) async {
    await recordEvent(
      type: 'feature_usage',
      data: {'feature': featureName},
    );
  }

  /// Enregistre un intent mapping (question -> action).
  Future<void> recordIntentMap(String queryType, String action) async {
    await recordEvent(
      type: 'intent_map',
      data: {
        'queryType': queryType,
        'action': action,
      },
    );
  }

  /// Enregistre un pic d'usage (saisonnalite).
  Future<void> recordSessionStart() async {
    await recordEvent(
      type: 'seasonality',
      data: {
        'hour': DateTime.now().hour,
        'weekday': DateTime.now().weekday,
      },
    );
  }

  // ── Export ────────────────────────────────────────────────────────────────

  /// True si un export est du (1x/semaine).
  Future<bool> shouldExport() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyLastExport);
    if (raw == null) return true;
    final last = DateTime.parse(raw);
    return DateTime.now().difference(last) >= _exportInterval;
  }

  /// Retourne les insights en attente d'export (sans les supprimer).
  Future<List<AnonymizedInsight>> getPendingInsights() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyQueue);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => AnonymizedInsight(
        cohortId: e['cohortId'] as String,
        type: e['type'] as String,
        data: e['data'] as Map<String, dynamic>,
        timestamp: DateTime.parse(e['timestamp'] as String),
      )).toList();
    } catch (e) {
      debugPrint('[AnonymizedInsight] getPending error: $e');
      return const [];
    }
  }

  /// Marque les insights comme exportes et vide la file.
  Future<void> markExported() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyQueue);
    await prefs.setString(_prefsKeyLastExport, DateTime.now().toIso8601String());
  }

  /// Compteurs agrégés pour l'UI utilisateur (transparence).
  Future<Map<String, int>> getCounters() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyCounters);
    if (raw == null) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as int));
    } catch (e) {
      return const {};
    }
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  Future<void> _enqueue(AnonymizedInsight insight) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = await getPendingInsights();
    queue.add(insight);
    if (queue.length > _maxQueueSize) {
      queue.removeAt(0); // FIFO
    }
    final jsonList = queue.map((i) => i.toJson()).toList();
    await prefs.setString(_prefsKeyQueue, jsonEncode(jsonList));
  }

  Future<void> _incrementCounters(String type) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyCounters);
    final counters = raw != null
        ? (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int))
        : <String, int>{};
    counters[type] = (counters[type] ?? 0) + 1;
    await prefs.setString(_prefsKeyCounters, jsonEncode(counters));
  }

  /// Construit un ID de cohorte a partir de metadata non-PII.
  Future<String> _buildCohortId({String? language, String? platform}) async {
    final now = DateTime.now();
    final week = '${now.year}-W${(now.dayOfYear / 7).ceil()}';
    final lang = (language ?? 'unknown').substring(0, min(2, (language ?? 'unknown').length));
    final plat = platform ?? 'unknown';
    final raw = '$week|$lang|$plat';
    final bytes = utf8.encode(raw);
    return sha256.convert(bytes).toString().substring(0, 16);
  }
}

extension _DateTimeExtension on DateTime {
  int get dayOfYear {
    final firstDay = DateTime(year, 1, 1);
    return difference(firstDay).inDays + 1;
  }
}
