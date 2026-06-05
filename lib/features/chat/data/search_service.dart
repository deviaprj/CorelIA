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
  ///
  /// **Robustesse** : essaie 3 endpoints en cascade, limite la taille HTML,
  /// patterns fallback multiples pour s'adapter aux changements de markup.
  Future<List<WebSearchResult>> searchDirect(String query, {int numResults = 5}) async {
    const endpoints = [
      'https://html.duckduckgo.com/html/',
      'https://lite.duckduckgo.com/lite/',
      'https://duckduckgo.com/html/',
    ];

    const userAgents = [
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    ];

    var endpointIndex = 0;
    var lastError = '';

    for (final endpoint in endpoints) {
      try {
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: {
            if (!kIsWeb) 'User-Agent': userAgents[endpointIndex % userAgents.length],
            'Accept': 'text/html,application/xhtml+xml',
          },
        ));

        final response = await dio.get<dynamic>(
          endpoint,
          queryParameters: {'q': query},
        );

        if (response.statusCode == 200) {
          final rawHtml = response.data as String;
          // Protection contre les réponses HTML gigantesques (limite ~500KB)
          final html = rawHtml.length > 500000 ? rawHtml.substring(0, 500000) : rawHtml;

          var results = _parseDuckDuckGoHtml(html, numResults);
          if (results.isEmpty) {
            results = _parseDuckDuckGoHtmlFallback(html, numResults);
          }
          if (results.isNotEmpty) {
            debugPrint('[SearchService] searchDirect OK via $endpoint (${results.length} résultats)');
            return results;
          }
          debugPrint('[SearchService] Endpoint $endpoint : 0 résultats, passage au suivant');
        }
      } on DioException catch (e) {
        lastError = 'DioException $endpoint : ${e.message}';
        debugPrint('[SearchService] $lastError');
      } catch (e) {
        lastError = 'Exception $endpoint : $e';
        debugPrint('[SearchService] $lastError');
      }
      endpointIndex++;
    }

    throw SearchException('Tous les endpoints DuckDuckGo ont échoué. Dernier : $lastError');
  }

  // ── URL Decoding ───────────────────────────────────────────────────────────

  /// Décode une URL de redirection DuckDuckGo.
  /// Supporte les formats : /l/?u=URL, /l/?uddg=URL, /l/?kh=...&u=URL
  static String? decodeDdgUrl(String rawUrl) {
    if (rawUrl.isEmpty) return null;
    // Déjà une URL absolue
    if (rawUrl.startsWith('http')) return rawUrl;

    // Format : /l/?uddg=https%3A%2F%2F...
    final uddg = RegExp(r'[?&]uddg=([^&]+)').firstMatch(rawUrl);
    if (uddg != null) {
      try {
        return Uri.decodeComponent(uddg.group(1)!);
      } catch (_) {}
    }

    // Format : /l/?u=https%3A%2F%2F... ou /l/?kh=...&u=URL
    final uMatch = RegExp(r'[?&]u=([^&]+)').firstMatch(rawUrl);
    if (uMatch != null) {
      try {
        return Uri.decodeComponent(uMatch.group(1)!);
      } catch (_) {}
    }

    // Format : //duckduckgo.com/l/?uddg=...
    if (rawUrl.startsWith('//')) {
      return decodeDdgUrl('/' + rawUrl.substring(2));
    }

    return null;
  }

  /// Parse le HTML DuckDuckGo pour extraire les resultats.
  /// Architecture multi-pattern : teste plusieurs structures HTML courantes.
  List<WebSearchResult> _parseDuckDuckGoHtml(String html, int maxResults) {
    final results = <WebSearchResult>[];

    // Pattern 1 : resultats avec lien encode /l/?kh=...&u=URL (ancien layout)
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

    // Pattern 2 : liens directs sans encodage
    if (results.isEmpty) {
      final pattern2 = RegExp(
        r'<a[^>]*class="result__a"[^>]*href="(https?://[^"]+)"[^>]*>(.*?)</a>.*?'
        r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
        caseSensitive: false,
        dotAll: true,
      );
      for (final match in pattern2.allMatches(html)) {
        if (results.length >= maxResults) break;
        final url = match.group(1) ?? '';
        final title = _cleanHtml(match.group(2) ?? 'Sans titre');
        final snippet = _cleanHtml(match.group(3) ?? '');
        results.add(WebSearchResult(title: title, url: url, snippet: snippet));
      }
    }

    // Pattern 3 : DuckDuckGo uddg redirect (nouveau layout)
    if (results.isEmpty) {
      final pattern3 = RegExp(
        r'<a[^>]*class="result__a"[^>]*href="(/l/\?[^"]*uddg=[^"]+)"[^>]*>(.*?)</a>.*?'
        r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
        caseSensitive: false,
        dotAll: true,
      );
      for (final match in pattern3.allMatches(html)) {
        if (results.length >= maxResults) break;
        final rawUrl = match.group(1) ?? '';
        final title = _cleanHtml(match.group(2) ?? 'Sans titre');
        final snippet = _cleanHtml(match.group(3) ?? '');
        final url = decodeDdgUrl(rawUrl) ?? rawUrl;
        results.add(WebSearchResult(title: title, url: url, snippet: snippet));
      }
    }

    return results;
  }

  /// Fallback parsing si le premier pattern ne match pas.
  List<WebSearchResult> _parseDuckDuckGoHtmlFallback(String html, int maxResults) {
    final results = <WebSearchResult>[];

    // Fallback classique — tout lien result__a
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
        final decoded = decodeDdgUrl(url);
        if (decoded != null) url = decoded;
      }
      results.add(WebSearchResult(title: title, url: url, snippet: snippet));
    }

    // Fallback avec liens absolus directs (pas de redirection DuckDuckGo)
    if (results.isEmpty) {
      final directPattern = RegExp(
        r'<a[^>]*class="result__a"[^>]*href="(https?://[^"]+)"[^>]*>(.*?)</a>',
        caseSensitive: false,
        dotAll: true,
      );
      for (final match in directPattern.allMatches(html)) {
        if (results.length >= maxResults) break;
        final url = match.group(1) ?? '';
        final title = _cleanHtml(match.group(2) ?? 'Sans titre');
        if (url.isNotEmpty && !url.contains('duckduckgo.com')) {
          results.add(WebSearchResult(title: title, url: url, snippet: ''));
        }
      }
    }

    // Fallback ultra-souple : tout lien avec titre + snippet proche
    if (results.isEmpty) {
      final ultraPattern = RegExp(
        r'<a[^>]*href="([^"]+)"[^>]*>([^<]{10,200})</a>.*?'
        r'<[^>]*>([^<]{20,500})</[^>]*>',
        caseSensitive: false,
        dotAll: true,
      );
      for (final match in ultraPattern.allMatches(html)) {
        if (results.length >= maxResults) break;
        final rawUrl = match.group(1) ?? '';
        final title = _cleanHtml(match.group(2) ?? 'Sans titre');
        final snippet = _cleanHtml(match.group(3) ?? '');
        if (rawUrl.startsWith('http') && !rawUrl.contains('duckduckgo.com')) {
          results.add(WebSearchResult(title: title, url: rawUrl, snippet: snippet));
        }
      }
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