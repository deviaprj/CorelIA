import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'search_service.dart';

/// Entrée de cache avec TTL.
class _CacheEntry {
  final List<WebSearchResult> results;
  final DateTime cachedAt;

  const _CacheEntry({required this.results, required this.cachedAt});

  bool get isExpired =>
      DateTime.now().difference(cachedAt).inMinutes >= _SearchCacheService._defaultTtlMinutes;

  Map<String, dynamic> toJson() => {
        'results': results.map((r) => {
              'title': r.title,
              'url': r.url,
              'snippet': r.snippet,
            }).toList(),
        'cachedAt': cachedAt.toIso8601String(),
      };

  static _CacheEntry? fromJson(Map<String, dynamic> json) {
    try {
      final resultsList = json['results'] as List<dynamic>;
      final results = resultsList.map((r) {
        final m = r as Map<String, dynamic>;
        return WebSearchResult(
          title: m['title'] as String? ?? '',
          url: m['url'] as String? ?? '',
          snippet: m['snippet'] as String? ?? '',
        );
      }).toList();
      final cachedAt = DateTime.parse(json['cachedAt'] as String);
      return _CacheEntry(results: results, cachedAt: cachedAt);
    } catch (e) {
      debugPrint('[SearchCache] Deserialization error: $e');
      return null;
    }
  }
}

/// Service de cache pour les résultats de recherche web.
/// LRU en mémoire (max 100) + persistance SharedPreferences.
/// TTL configurable (défaut 15 minutes).
class _SearchCacheService {
  static const _defaultTtlMinutes = 15;
  static const _maxEntries = 100;
  static const _prefsKey = 'search_cache_entries';
  static const _prefsDatesKey = 'search_cache_dates';

  final Map<String, _CacheEntry> _memoryCache = {};
  bool _prefsLoaded = false;

  /// Récupère les résultats en cache si disponibles et non expirés.
  List<WebSearchResult>? get(String query, {String? lang}) {
    final key = _cacheKey(query, lang);
    final entry = _memoryCache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _memoryCache.remove(key);
      return null;
    }
    debugPrint('[SearchCache] Cache HIT: "$query"');
    return entry.results;
  }

  /// Stocke les résultats en cache.
  void put(String query, List<WebSearchResult> results, {String? lang}) {
    final key = _cacheKey(query, lang);

    // LRU : supprimer la plus ancienne entrée si limite atteinte
    if (_memoryCache.length >= _maxEntries && !_memoryCache.containsKey(key)) {
      _evictOldest();
    }

    _memoryCache[key] = _CacheEntry(
      results: results,
      cachedAt: DateTime.now(),
    );
    debugPrint('[SearchCache] Cached: "$query" (${results.length} results)');

    _persistToPrefs();
  }

  /// Invalide toutes les entrées expirées.
  void invalidateExpired() {
    _memoryCache.removeWhere((_, entry) => entry.isExpired);
    _persistToPrefs();
  }

  /// Vide tout le cache.
  void clear() {
    _memoryCache.clear();
    _persistToPrefs();
  }

  /// Nombre d'entrées en cache.
  int get size => _memoryCache.length;

  String _cacheKey(String query, String? lang) {
    final normalized = query.trim().toLowerCase();
    final langSuffix = lang != null ? '_$lang' : '';
    final raw = '$normalized$langSuffix';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  void _evictOldest() {
    if (_memoryCache.isEmpty) return;
    String? oldestKey;
    DateTime? oldestDate;
    for (final entry in _memoryCache.entries) {
      if (oldestDate == null || entry.value.cachedAt.isBefore(oldestDate)) {
        oldestKey = entry.key;
        oldestDate = entry.value.cachedAt;
      }
    }
    if (oldestKey != null) {
      _memoryCache.remove(oldestKey);
    }
  }

  /// Persiste le cache vers SharedPreferences (async, fire-and-forget).
  void _persistToPrefs() {
    _doPersist();
  }

  Future<void> _doPersist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = _memoryCache.entries
          .where((e) => !e.value.isExpired)
          .map((e) => {'key': e.key, ...e.value.toJson()})
          .toList();
      await prefs.setString(_prefsKey, jsonEncode(entries));
    } catch (e) {
      debugPrint('[SearchCache] Persist error: $e');
    }
  }

  /// Charge le cache depuis SharedPreferences (appelé une seule fois).
  Future<void> loadFromPrefs() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final key = m['key'] as String?;
        if (key == null) continue;
        final entry = _CacheEntry.fromJson(m);
        if (entry != null && !entry.isExpired) {
          _memoryCache[key] = entry;
        }
      }
      debugPrint('[SearchCache] Loaded ${_memoryCache.length} entries from prefs');
    } catch (e) {
      debugPrint('[SearchCache] Load error: $e');
    }
  }
}

/// Singleton accessible depuis n'importe quel provider.
final searchCache = _SearchCacheService();