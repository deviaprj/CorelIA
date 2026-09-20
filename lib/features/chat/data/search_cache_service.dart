import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';
import 'search_service.dart';

/// Entrée de cache avec TTL.
class _CacheEntry {
  const _CacheEntry({required this.results, required this.cachedAt});

  final List<WebSearchResult> results;
  final DateTime cachedAt;

  bool get isExpired =>
      DateTime.now().difference(cachedAt).inMinutes >=
      AppConfig.searchCacheTtlMinutes;

  Map<String, dynamic> toJson() => {
        'results': results
            .map((r) => {'title': r.title, 'url': r.url, 'snippet': r.snippet})
            .toList(),
        'cachedAt': cachedAt.toIso8601String(),
      };

  static _CacheEntry? fromJson(Map<String, dynamic> json) {
    try {
      final results = (json['results'] as List<dynamic>).map((r) {
        final m = r as Map<String, dynamic>;
        return WebSearchResult(
          title: m['title'] as String? ?? '',
          url: m['url'] as String? ?? '',
          snippet: m['snippet'] as String? ?? '',
        );
      }).toList();
      return _CacheEntry(
        results: results,
        cachedAt: DateTime.parse(json['cachedAt'] as String),
      );
    } catch (e) {
      debugPrint('[SearchCache] Désérialisation impossible : $e');
      return null;
    }
  }
}

/// Cache des résultats de recherche web : LRU en mémoire + persistance
/// SharedPreferences, avec TTL.
class SearchCacheService {
  static const _prefsKey = 'search_cache_entries';

  final Map<String, _CacheEntry> _memoryCache = {};
  bool _prefsLoaded = false;

  /// Résultats en cache s'ils sont encore valides.
  List<WebSearchResult>? get(String query, {String? lang}) {
    final entry = _memoryCache[_cacheKey(query, lang)];
    if (entry == null) return null;
    if (entry.isExpired) {
      _memoryCache.remove(_cacheKey(query, lang));
      return null;
    }
    return entry.results;
  }

  /// Résultats en cache même si le TTL est dépassé (mode hors-ligne).
  List<WebSearchResult>? getExpired(String query, {String? lang}) {
    final entry = _memoryCache[_cacheKey(query, lang)];
    if (entry == null || entry.results.isEmpty) return null;
    debugPrint('[SearchCache] Repli hors-ligne pour "$query"');
    return entry.results;
  }

  void put(String query, List<WebSearchResult> results, {String? lang}) {
    final key = _cacheKey(query, lang);
    if (_memoryCache.length >= AppConfig.searchCacheMaxEntries &&
        !_memoryCache.containsKey(key)) {
      _evictOldest();
    }
    _memoryCache[key] = _CacheEntry(results: results, cachedAt: DateTime.now());
    _persistToPrefs();
  }

  void clear() {
    _memoryCache.clear();
    _persistToPrefs();
  }

  int get size => _memoryCache.length;

  String _cacheKey(String query, String? lang) {
    final raw = '${query.trim().toLowerCase()}${lang != null ? '_$lang' : ''}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  void _evictOldest() {
    String? oldestKey;
    DateTime? oldestDate;
    for (final entry in _memoryCache.entries) {
      if (oldestDate == null || entry.value.cachedAt.isBefore(oldestDate)) {
        oldestKey = entry.key;
        oldestDate = entry.value.cachedAt;
      }
    }
    if (oldestKey != null) _memoryCache.remove(oldestKey);
  }

  void _persistToPrefs() => _doPersist();

  Future<void> _doPersist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = _memoryCache.entries
          .where((e) => !e.value.isExpired)
          .map((e) => {'key': e.key, ...e.value.toJson()})
          .toList();
      await prefs.setString(_prefsKey, jsonEncode(entries));
    } catch (e) {
      debugPrint('[SearchCache] Persistance impossible : $e');
    }
  }

  /// Restaure le cache persistant (au plus une fois par process).
  Future<void> loadFromPrefs() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      for (final item in jsonDecode(raw) as List<dynamic>) {
        final m = item as Map<String, dynamic>;
        final key = m['key'] as String?;
        if (key == null) continue;
        final entry = _CacheEntry.fromJson(m);
        if (entry != null && !entry.isExpired) _memoryCache[key] = entry;
      }
    } catch (e) {
      debugPrint('[SearchCache] Chargement impossible : $e');
    }
  }
}

/// Singleton accessible depuis n'importe où.
final searchCache = SearchCacheService();
