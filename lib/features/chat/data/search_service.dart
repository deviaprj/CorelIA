import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/constants.dart';

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

/// Service de recherche web — 100% autonome avec fallback multi-provider.
///
/// Mode backend (primary) : utilise `/search` du backend FastAPI deploye.
/// Mode direct (fallback) : parse DuckDuckGo HTML pour fonctionner sans backend.
/// L'APK reste toujours autonome meme si le backend cloud est indisponible.
class SearchService {
  final Dio _dio;

  SearchService({Dio? dio}) : _dio = dio ?? DioClientFactory.create();

  /// Recherche web fiable avec fallback : backend cloud → DuckDuckGo direct.
  Future<List<WebSearchResult>> searchWithFallback(String query, {String? lang}) async {
    // 1. Essayer le backend cloud (si configure et disponible)
    final backendUrl = AppConstants.backendBaseUrl;
    if (backendUrl.isNotEmpty && !backendUrl.contains('localhost')) {
      try {
        final results = await _searchBackend(query, lang: lang);
        if (results.isNotEmpty) return results;
      } catch (e) {
        debugPrint('[SearchService] Backend indisponible, fallback client-side : $e');
      }
    }

    // 2. Fallback client-side : DuckDuckGo HTML scraping (autonome)
    return searchDirect(query);
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
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36',
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
