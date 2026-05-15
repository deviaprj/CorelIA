import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/constants.dart';
import 'search_cache_service.dart';

/// Exception specifique au service de recherche.
class SearchException implements Exception {
  final String message;
  const SearchException(this.message);
  @override
  String toString() => 'SearchException: $message';
}

/// Resultat de recherche simplifie pour usage interne.
class WebSearchResult {
  final String title;
  final String url;
  final String snippet;
  const WebSearchResult({required this.title, required this.url, required this.snippet});
}

/// Resultat instantané DuckDuckGo (réponse courte, pas de clic nécessaire).
class InstantAnswer {
  final String title;
  final String abstractText;
  final String source;
  final String url;
  const InstantAnswer({
    required this.title,
    required this.abstractText,
    required this.source,
    required this.url,
  });
}

/// Service de recherche web — 100% autonome avec fallback multi-provider.
///
/// Mode backend (primary) : utilise `/search` du backend FastAPI deploye.
/// Mode direct (fallback) : parse DuckDuckGo HTML pour fonctionner sans backend.
/// L'APK reste toujours autonome meme si le backend cloud est indisponible.
///
/// Améliorations :
/// - Debounce : les recherches identiques en moins de 2s sont fusionnées
/// - Instant Answer : DuckDuckGo Instant Answer API pour les définitions/facts rapides
/// - Mode hors-ligne : retourne les résultats en cache si aucune connexion
class SearchService {
  final Dio _dio;

  // ── Debounce ──────────────────────────────────────────────────────────────
  DateTime? _lastSearchTime;
  String? _lastSearchQuery;
  List<WebSearchResult>? _lastSearchResults;
  static const _debounceWindow = Duration(seconds: 2);

  SearchService({Dio? dio}) : _dio = dio ?? DioClientFactory.create();

  /// Recherche web fiable avec fallback : backend cloud → DuckDuckGo direct.
  /// Utilise le cache si disponible et non expiré.
  /// Inclut un debounce pour éviter les recherches dupliquées.
  Future<List<WebSearchResult>> searchWithFallback(String query, {String? lang}) async {
    // 0. Debounce — si la même recherche a été faite récemment, réutiliser
    if (_lastSearchQuery == query &&
        _lastSearchTime != null &&
        DateTime.now().difference(_lastSearchTime!) < _debounceWindow &&
        _lastSearchResults != null) {
      debugPrint('[SearchService] Debounce HIT: "$query"');
      return _lastSearchResults!;
    }

    // 1. Vérifier le cache
    final cached = searchCache.get(query, lang: lang);
    if (cached != null) return cached;

    // 2. Essayer le backend cloud (si configure et disponible)
    final backendUrl = AppConstants.backendBaseUrl;
    if (backendUrl.isNotEmpty && !backendUrl.contains('localhost')) {
      try {
        final results = await _searchBackend(query, lang: lang);
        if (results.isNotEmpty) {
          searchCache.put(query, results, lang: lang);
          _updateDebounce(query, results);
          return results;
        }
      } catch (e) {
        debugPrint('[SearchService] Backend indisponible, fallback client-side : $e');
      }
    }

    // 3. Fallback client-side : DuckDuckGo HTML scraping (autonome)
    try {
      final results = await searchDirect(query);
      if (results.isNotEmpty) {
        searchCache.put(query, results, lang: lang);
        _updateDebounce(query, results);
        return results;
      }
    } catch (e) {
      debugPrint('[SearchService] DuckDuckGo direct échoué : $e');
    }

    // 4. Dernier recours : résultats en cache expirés (mode hors-ligne)
    final expiredResults = searchCache.get(query, lang: lang);
    if (expiredResults != null) {
      debugPrint('[SearchService] Mode hors-ligne : cache expiré pour "$query"');
      return expiredResults;
    }

    return [];
  }

  void _updateDebounce(String query, List<WebSearchResult> results) {
    _lastSearchQuery = query;
    _lastSearchResults = results;
    _lastSearchTime = DateTime.now();
  }

  /// Recherche DuckDuckGo Instant Answer — définitions, faits rapides.
  /// Retourne une réponse courte si disponible, null sinon.
  Future<InstantAnswer?> getInstantAnswer(String query) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        headers: {'Accept': 'application/json'},
      ));

      final response = await dio.get<Map<String, dynamic>>(
        'https://api.duckduckgo.com/',
        queryParameters: {
          'q': query,
          'format': 'json',
          'no_html': '1',
          'skip_disambig': '1',
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data!;
        final abstractText = data['AbstractText'] as String? ?? '';
        if (abstractText.isNotEmpty) {
          return InstantAnswer(
            title: data['Heading'] as String? ?? query,
            abstractText: abstractText,
            source: data['AbstractSource'] as String? ?? 'DuckDuckGo',
            url: data['AbstractURL'] as String? ?? '',
          );
        }
      }
    } catch (e) {
      debugPrint('[SearchService] Instant Answer non disponible : $e');
    }
    return null;
  }

  /// Recherche web via le backend cloud.
  Future<List<WebSearchResult>> _searchBackend(String query, {String? lang}) async {
    try {
      final response = await _dio.get<dynamic>(
        '/search',
        queryParameters: {
          'q': query,
          if (lang != null) 'lang': lang,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];
        return results.map((r) {
          final m = r as Map<String, dynamic>;
          return WebSearchResult(
            title: m['title'] as String? ?? 'Sans titre',
            url: m['url'] as String? ?? '',
            snippet: m['snippet'] as String? ?? '',
          );
        }).toList();
      }
      throw const SearchException('Reponse inattendue du serveur de recherche');
    } on DioException catch (e) {
      throw SearchException('Backend recherche : ${e.message}');
    }
  }

  /// Recherche web directe via DuckDuckGo — aucun backend requis.
  ///
  /// Parse le HTML de DuckDuckGo lite pour extraire les resultats.
  /// Fonctionne sur mobile avec n'importe quelle connexion internet.
  /// Timeout : 8 secondes max.
  Future<List<WebSearchResult>> searchDirect(String query, {int numResults = 5}) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: {
          if (!kIsWeb) 'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36',
          'Accept': 'text/html',
        },
      ));

      final response = await dio.get<dynamic>(
        'https://html.duckduckgo.com/html/',
        queryParameters: {'q': query},
      );

      if (response.statusCode == 200) {
        final results = _parseDuckDuckGoHtml(response.data as String, numResults);
        if (results.isNotEmpty) return results;
        // Si aucun resultat, essayer le parsing alternatif
        return _parseDuckDuckGoHtmlFallback(response.data as String, numResults);
      }
      throw SearchException('HTTP ${response.statusCode}');
    } on DioException catch (e) {
      throw SearchException('Reseau DuckDuckGo : ${e.message}');
    } catch (e) {
      throw SearchException(e.toString());
    }
  }

  /// Parse le HTML DuckDuckGo pour extraire les resultats.
  List<WebSearchResult> _parseDuckDuckGoHtml(String html, int maxResults) {
    final results = <WebSearchResult>[];

    // Pattern 1 : resultats avec lien encode /l/?kh=...&u=URL
    final pattern1 = RegExp(
      r'<div class="result[^"]*"[^>]*>.*?'
      r'<a[^>]*class="result__a"[^>]*href="/l/\?[^"]*&u=([^"]+)"[^>]*>(.*?)</a>.*?'
      r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>.*?'
      r'</div>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in pattern1.allMatches(html)) {
      if (results.length >= maxResults) break;
      final encodedUrl = match.group(1) ?? '';
      final title = _cleanHtml(match.group(2) ?? 'Sans titre');
      final snippet = _cleanHtml(match.group(3) ?? '');
      final url = Uri.decodeFull(encodedUrl.replaceAll('&amp;', '&'));
      results.add(WebSearchResult(title: title, url: url, snippet: snippet));
    }

    return results;
  }

  /// Fallback parsing si le premier pattern ne match pas.
  List<WebSearchResult> _parseDuckDuckGoHtmlFallback(String html, int maxResults) {
    final results = <WebSearchResult>[];

    final fallbackPattern = RegExp(
      r'<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>.*?'
      r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in fallbackPattern.allMatches(html)) {
      if (results.length >= maxResults) break;
      final rawUrl = match.group(1) ?? '';
      final title = _cleanHtml(match.group(2) ?? 'Sans titre');
      final snippet = _cleanHtml(match.group(3) ?? '');

      String url = rawUrl;
      if (url.startsWith('/l/?')) {
        final uMatch = RegExp(r'[?&]u=([^&]+)').firstMatch(url);
        if (uMatch != null) {
          url = Uri.decodeFull(uMatch.group(1)!);
        }
      }
      results.add(WebSearchResult(title: title, url: url, snippet: snippet));
    }

    return results;
  }

  /// Nettoie les balises HTML d'une chaine.
  String _cleanHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Formate les resultats de recherche pour l'IA.
  ///
  /// Retourne une chaine a injecter dans le contexte systeme.
  /// Limite a ~4000 tokens (environ 16000 caracteres).
  String formatForAi(List<WebSearchResult> results, String query) {
    if (results.isEmpty) {
      return 'Aucun resultat de recherche web trouve pour "$query".';
    }

    final buffer = StringBuffer()
      ..writeln('Resultats de recherche web pour "$query" :\n');

    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('${i + 1}. ${r.title}');
      buffer.writeln('   URL: ${r.url}');
      buffer.writeln('   ${r.snippet}\n');
    }

    // Limiter le contexte a ~16000 caracteres (approximation 4000 tokens)
    const maxChars = 16000;
    final context = buffer.toString();
    if (context.length > maxChars) {
      return '${context.substring(0, maxChars)}\n\n[Resultats tronques]';
    }
    return context;
  }

  /// Formate une réponse instantanée (DuckDuckGo Instant Answer) pour l'IA.
  /// Si une réponse instantanée est disponible, l'injecte en contexte système.
  String formatInstantAnswerForAi(InstantAnswer answer) {
    return 'Réponse rapide : ${answer.title}\n\n${answer.abstractText}\nSource: ${answer.source} (${answer.url})';
  }

  /// Formate les sources pour affichage utilisateur dans le chat (markdown inline).
  String formatSourcesForUi(List<WebSearchResult> results) {
    if (results.isEmpty) return '';
    final buffer = StringBuffer('\n\n---\n**Sources :**\n');
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('${i + 1}. [${r.title}](${r.url})');
    }
    return buffer.toString();
  }

  /// Retourne les sources sous forme de liste "titre|url" pour stockage
  /// dans le modèle Message et affichage UI structuré.
  List<String> formatSourcesAsList(List<WebSearchResult> results) {
    return results.map((r) => '${r.title}|${r.url}').toList();
  }
}