import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/api/dio_client.dart';
import 'models/search_result.dart';

/// Exception spécifique au service de recherche.
class SearchException implements Exception {
  final String message;
  const SearchException(this.message);
  @override
  String toString() => 'SearchException: $message';
}

/// Résultat de recherche simplifié pour usage interne.
class WebSearchResult {
  final String title;
  final String url;
  final String snippet;
  const WebSearchResult({required this.title, required this.url, required this.snippet});
}

/// Service de recherche web.
///
/// Mode backend : utilise `/search` du backend FastAPI (legacy).
/// Mode direct  : parse DuckDuckGo HTML pour fonctionner sans backend.
class SearchService {
  final Dio _dio;

  SearchService({Dio? dio}) : _dio = dio ?? DioClientFactory.create();

  /// Recherche web via le backend (legacy — nécessite backend PC).
  Future<SearchResult> search(String query, {String? lang}) async {
    try {
      final response = await _dio.get(
        '/search',
        queryParameters: {
          'q': query,
          if (lang != null) 'lang': lang,
        },
      );

      if (response.statusCode == 200 && response.data is Map) {
        return SearchResult.fromJson(response.data as Map<String, dynamic>);
      }
      throw const SearchException('Réponse inattendue du serveur de recherche');
    } on DioException catch (e) {
      final msg = e.response?.data?['detail'] as String?;
      throw SearchException(msg ?? 'Erreur réseau lors de la recherche');
    } catch (e) {
      throw SearchException(e.toString());
    }
  }

  /// Recherche web directe via DuckDuckGo — aucun backend requis.
  ///
  /// Parse le HTML de DuckDuckGo lite pour extraire les résultats.
  /// Fonctionne sur mobile avec n'importe quelle connexion internet.
  Future<List<WebSearchResult>> searchDirect(String query, {int numResults = 5}) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36',
          'Accept': 'text/html',
        },
      ));

      final response = await dio.get(
        'https://html.duckduckgo.com/html/',
        queryParameters: {'q': query},
      );

      if (response.statusCode == 200) {
        return _parseDuckDuckGoHtml(response.data as String, numResults);
      }
      throw SearchException('HTTP ${response.statusCode}');
    } on DioException catch (e) {
      throw SearchException('Réseau: ${e.message}');
    } catch (e) {
      throw SearchException(e.toString());
    }
  }

  /// Parse le HTML DuckDuckGo pour extraire les résultats.
  List<WebSearchResult> _parseDuckDuckGoHtml(String html, int maxResults) {
    final results = <WebSearchResult>[];

    // Pattern pour les résultats DuckDuckGo HTML
    // Chaque résultat est dans un <div class="result">...</div>
    final resultPattern = RegExp(
      r'<div class="result[^"]*"[^>]*>.*?<h[^>]*class="result__a"[^>]*href="/l/\?kh=-?\d+&amp;u=([^"]+)"[^>]*>(.*?)</a>.*?<a[^>]*class="result__snippet"[^>]*>(.*?)</a>.*?</div>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in resultPattern.allMatches(html)) {
      if (results.length >= maxResults) break;

      final encodedUrl = match.group(1) ?? '';
      final title = _cleanHtml(match.group(2) ?? 'Sans titre');
      final snippet = _cleanHtml(match.group(3) ?? '');

      // Decoder l'URL encodée
      final url = Uri.decodeFull(encodedUrl.replaceAll('&amp;', '&'));

      results.add(WebSearchResult(title: title, url: url, snippet: snippet));
    }

    // Fallback pattern si le premier ne matche pas
    if (results.isEmpty) {
      final fallbackPattern = RegExp(
        r'<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>.*?<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
        caseSensitive: false,
        dotAll: true,
      );
      for (final match in fallbackPattern.allMatches(html)) {
        if (results.length >= maxResults) break;
        final rawUrl = match.group(1) ?? '';
        final title = _cleanHtml(match.group(2) ?? 'Sans titre');
        final snippet = _cleanHtml(match.group(3) ?? '');

        // Gérer les URLs DuckDuckGo encodées
        String url = rawUrl;
        if (url.startsWith('/l/?')) {
          final uMatch = RegExp(r'[?&]u=([^&]+)').firstMatch(url);
          if (uMatch != null) {
            url = Uri.decodeFull(uMatch.group(1)!);
          }
        }
        results.add(WebSearchResult(title: title, url: url, snippet: snippet));
      }
    }

    return results;
  }

  /// Nettoie les balises HTML d'une chaîne.
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

  /// Formate les résultats de recherche pour l'IA.
  ///
  /// Retourne une chaîne à injecter dans le contexte système.
  String formatForAi(List<WebSearchResult> results, String query) {
    if (results.isEmpty) {
      return 'Aucun résultat de recherche web trouvé pour "$query".';
    }

    final buffer = StringBuffer()
      ..writeln('Résultats de recherche web pour "$query" :\n');

    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('${i + 1}. ${r.title}');
      buffer.writeln('   URL: ${r.url}');
      buffer.writeln('   ${r.snippet}\n');
    }

    return buffer.toString();
  }
}
