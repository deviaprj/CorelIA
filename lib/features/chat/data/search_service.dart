import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/app_config.dart';
import 'search_cache_service.dart';

/// Exception spécifique au service de recherche.
class SearchException implements Exception {
  const SearchException(this.message);

  final String message;

  @override
  String toString() => 'SearchException: $message';
}

/// Résultat de recherche web simplifié.
class WebSearchResult {
  const WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  final String title;
  final String url;
  final String snippet;
}

/// Résultat instantané DuckDuckGo (réponse courte, sans clic).
class InstantAnswer {
  const InstantAnswer({
    required this.title,
    required this.abstractText,
    required this.source,
    required this.url,
  });

  final String title;
  final String abstractText;
  final String source;
  final String url;
}

/// Recherche web autonome (aucun backend requis).
///
/// Scrape DuckDuckGo (HTML/lite) avec mise en cache et debounce, et interroge
/// l'API Instant Answer pour les questions factuelles.
class SearchService {
  SearchService({Dio? dio})
      : _dio = dio ??
            ApiClient.create(receiveTimeout: AppConfig.searchRequestTimeout);

  final Dio _dio;

  DateTime? _lastSearchTime;
  String? _lastSearchQuery;
  List<WebSearchResult>? _lastSearchResults;
  static const _debounceWindow = Duration(seconds: 2);

  /// Recherche web avec cache, debounce et repli hors-ligne.
  Future<List<WebSearchResult>> search(String query, {String? lang}) async {
    if (_lastSearchQuery == query &&
        _lastSearchTime != null &&
        DateTime.now().difference(_lastSearchTime!) < _debounceWindow &&
        _lastSearchResults != null) {
      return _lastSearchResults!;
    }

    final cached = searchCache.get(query, lang: lang);
    if (cached != null) return cached;

    // 1. Worker Cloudflare (recherche côté serveur, sans contrainte CORS).
    if (AppConfig.isWorkerConfigured) {
      try {
        final results = await _searchViaWorker(query);
        if (results.isNotEmpty) return _remember(query, results, lang);
      } catch (e) {
        debugPrint('[SearchService] Recherche via Worker échouée : $e');
      }
    }

    // 2. Repli : DuckDuckGo direct depuis le client.
    try {
      final results = await searchDirect(query);
      if (results.isNotEmpty) return _remember(query, results, lang);
    } catch (e) {
      debugPrint('[SearchService] Recherche directe échouée : $e');
    }

    // Dernier recours : cache expiré (mode hors-ligne).
    return searchCache.getExpired(query, lang: lang) ?? const [];
  }

  List<WebSearchResult> _remember(
    String query,
    List<WebSearchResult> results,
    String? lang,
  ) {
    searchCache.put(query, results, lang: lang);
    _lastSearchQuery = query;
    _lastSearchResults = results;
    _lastSearchTime = DateTime.now();
    return results;
  }

  /// Recherche via `GET $WORKER_URL/search`.
  Future<List<WebSearchResult>> _searchViaWorker(String query) async {
    final response = await _dio.get<dynamic>(
      '${AppConfig.workerBaseUrl}/search',
      queryParameters: {'q': query, 'limit': AppConfig.searchResultsLimit},
      options: Options(
        responseType: ResponseType.json,
        headers: {if (AppConfig.clientApiKey.isNotEmpty) 'X-API-Key': AppConfig.clientApiKey},
      ),
    );

    final data = response.data;
    if (data is! Map) return const [];

    final results = data['results'] as List<dynamic>? ?? const [];
    return results
        .whereType<Map<String, dynamic>>()
        .map(
          (r) => WebSearchResult(
            title: r['title'] as String? ?? 'Sans titre',
            url: r['url'] as String? ?? '',
            snippet: r['snippet'] as String? ?? '',
          ),
        )
        .toList();
  }

  /// Recherche DuckDuckGo en cascade sur plusieurs endpoints.
  Future<List<WebSearchResult>> searchDirect(
    String query, {
    int numResults = AppConfig.searchResultsLimit,
  }) async {
    const endpoints = [
      AppConfig.duckDuckGoHtmlEndpoint,
      AppConfig.duckDuckGoLiteEndpoint,
    ];
    var lastError = '';

    for (final endpoint in endpoints) {
      try {
        final response = await _dio.get<dynamic>(
          endpoint,
          queryParameters: {'q': query},
          options: Options(responseType: ResponseType.plain),
        );
        if (response.statusCode != 200) continue;

        final raw = response.data as String;
        final html = raw.length > 500000 ? raw.substring(0, 500000) : raw;
        final results = _parse(html, numResults);
        if (results.isNotEmpty) return results;
      } catch (e) {
        lastError = '$endpoint : $e';
        debugPrint('[SearchService] $lastError');
      }
    }

    throw SearchException('Tous les moteurs de recherche ont échoué. $lastError');
  }

  /// Réponse instantanée DuckDuckGo (définitions, faits rapides).
  Future<InstantAnswer?> getInstantAnswer(String query) async {
    try {
      final response = await _dio.get<dynamic>(
        AppConfig.duckDuckGoInstantAnswerEndpoint,
        queryParameters: {
          'q': query,
          'format': 'json',
          'no_html': '1',
          'skip_disambig': '1',
        },
        options: Options(responseType: ResponseType.json),
      );

      // DuckDuckGo peut répondre en HTML : on ignore alors la réponse.
      final data = response.data;
      if (data is! Map) return null;

      final abstractText = data['AbstractText'] as String? ?? '';
      if (abstractText.isEmpty) return null;
      return InstantAnswer(
        title: data['Heading'] as String? ?? query,
        abstractText: abstractText,
        source: data['AbstractSource'] as String? ?? 'DuckDuckGo',
        url: data['AbstractURL'] as String? ?? '',
      );
    } catch (e) {
      debugPrint('[SearchService] Instant Answer indisponible : $e');
      return null;
    }
  }

  /// Décode une URL de redirection DuckDuckGo (`/l/?uddg=…`).
  static String? decodeDdgUrl(String rawUrl) {
    if (rawUrl.isEmpty) return null;
    if (rawUrl.startsWith('http')) return rawUrl;

    final uddg = RegExp(r'[?&]uddg=([^&]+)').firstMatch(rawUrl);
    if (uddg != null) {
      try {
        return Uri.decodeComponent(uddg.group(1)!);
      } catch (_) {}
    }

    final uMatch = RegExp(r'[?&]u=([^&]+)').firstMatch(rawUrl);
    if (uMatch != null) {
      try {
        return Uri.decodeComponent(uMatch.group(1)!);
      } catch (_) {}
    }

    if (rawUrl.startsWith('//')) return decodeDdgUrl('/${rawUrl.substring(2)}');
    return null;
  }

  List<WebSearchResult> _parse(String html, int maxResults) {
    final results = <WebSearchResult>[];

    // Layout classique : liens de résultat + snippet associé.
    final pattern = RegExp(
      r'<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>.*?'
      r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final m in pattern.allMatches(html)) {
      if (results.length >= maxResults) break;
      results.add(WebSearchResult(
        title: _clean(m.group(2) ?? 'Sans titre'),
        url: decodeDdgUrl(m.group(1) ?? '') ?? (m.group(1) ?? ''),
        snippet: _clean(m.group(3) ?? ''),
      ));
    }

    // Repli : liens absolus sans snippet.
    if (results.isEmpty) {
      final direct = RegExp(
        r'<a[^>]*class="result__a"[^>]*href="(https?://[^"]+)"[^>]*>(.*?)</a>',
        caseSensitive: false,
        dotAll: true,
      );
      for (final m in direct.allMatches(html)) {
        if (results.length >= maxResults) break;
        final url = m.group(1) ?? '';
        if (url.isEmpty || url.contains('duckduckgo.com')) continue;
        results.add(WebSearchResult(
          title: _clean(m.group(2) ?? 'Sans titre'),
          url: url,
          snippet: '',
        ));
      }
    }

    return results;
  }

  static String _clean(String html) => html
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Formate les résultats pour le prompt système de l'IA.
  String formatForAi(List<WebSearchResult> results, String query) {
    if (results.isEmpty) {
      return 'Aucun résultat de recherche web pour « $query ».';
    }
    final buffer = StringBuffer('Résultats de recherche web pour « $query » :\n\n');
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buffer
        ..writeln('${i + 1}. ${r.title}')
        ..writeln('   URL: ${r.url}')
        ..writeln('   ${r.snippet}\n');
    }
    const maxChars = 16000;
    final context = buffer.toString();
    return context.length > maxChars
        ? '${context.substring(0, maxChars)}\n\n[Résultats tronqués]'
        : context;
  }

  String formatInstantAnswerForAi(InstantAnswer answer) =>
      'Réponse rapide : ${answer.title}\n\n${answer.abstractText}\n'
      'Source : ${answer.source} (${answer.url})';

  /// Sources sous forme `titre|url` pour stockage et affichage structuré.
  List<String> formatSourcesAsList(List<WebSearchResult> results) =>
      results.map((r) => '${r.title}|${r.url}').toList();
}
