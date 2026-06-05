import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/constants.dart';

/// Résultat de recherche unifié (prix, carte, lien).
class SmartSearchResult {
  final String type; // 'price', 'card', 'link'
  final String title;
  final String? snippet;
  final String? value; // pour les prix
  final String? url;
  final String? sourceUrl;

  const SmartSearchResult({
    required this.type,
    required this.title,
    this.snippet,
    this.value,
    this.url,
    this.sourceUrl,
  });

  factory SmartSearchResult.fromJson(Map<String, dynamic> json) {
    return SmartSearchResult(
      type: json['type'] as String? ?? 'card',
      title: json['title'] as String? ?? '',
      snippet: json['snippet'] as String?,
      value: json['value'] as String?,
      url: json['url'] as String?,
      sourceUrl: json['source_url'] as String?,
    );
  }
}

/// Réponse du moteur de recherche intelligent.
class SmartSearchResponse {
  final String intent;
  final Map<String, dynamic> params;
  final String query;
  final List<SmartSearchResult> results;
  final List<Map<String, String>> sources;

  const SmartSearchResponse({
    required this.intent,
    required this.params,
    required this.query,
    required this.results,
    required this.sources,
  });

  factory SmartSearchResponse.fromJson(Map<String, dynamic> json) {
    final resultsList = (json['results'] as List<dynamic>? ?? [])
        .map((r) => SmartSearchResult.fromJson(r as Map<String, dynamic>))
        .toList();
    final sourcesList = (json['sources'] as List<dynamic>? ?? [])
        .map((s) {
          final m = s as Map<String, dynamic>;
          return <String, String>{
            'url': m['url'] as String? ?? '',
            'title': m['title'] as String? ?? '',
          };
        })
        .toList();
    return SmartSearchResponse(
      intent: json['intent'] as String? ?? 'general',
      params: json['params'] as Map<String, dynamic>? ?? {},
      query: json['query'] as String? ?? '',
      results: resultsList,
      sources: sourcesList,
    );
  }

  /// Vrai prix extraits (type == 'price').
  List<SmartSearchResult> get prices =>
      results.where((r) => r.type == 'price' && (r.value?.isNotEmpty ?? false)).toList();

  /// Cartes résultats (type == 'card').
  List<SmartSearchResult> get cards =>
      results.where((r) => r.type == 'card').toList();

  /// Liens directs (type == 'link').
  List<SmartSearchResult> get links =>
      results.where((r) => r.type == 'link').toList();

  bool get hasConcreteResults => prices.isNotEmpty || cards.isNotEmpty;
}

/// SearchServiceGlobal — moteur de recherche unifié et intelligent.
///
/// Remplace toutes les méthodes search* spécifiques (flights, hotels, products, etc.)
/// par un seul point d'entrée qui délègue au backend `/search_smart`.
///
/// Le backend :
/// 1. Classifie l'intent avec un LLM (vol, hôtel, produit, restaurant, etc.)
/// 2. Extrait les paramètres (villes, dates, prix, condition...)
/// 3. Scrape plusieurs sources en parallèle
/// 4. Retourne des résultats structurés (prix, cartes, liens)
///
/// Côté client, ce service formate les résultats en markdown pour le chat.
class SearchServiceGlobal {
  final Dio _dio;

  SearchServiceGlobal() : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  String get _backendUrl => AppConstants.backendBaseUrl;

  /// Recherche intelligente unifiée.
  ///
  /// [query] : requête en langage naturel (ex: "vol Paris Marseille 2 juin").
  /// Retourne [SmartSearchResponse] avec tous les résultats structurés.
  Future<SmartSearchResponse> search(String query) async {
    // 1. Essayer le backend /search_smart
    if (_backendUrl.isNotEmpty && !_backendUrl.contains('localhost')) {
      try {
        final resp = await _dio.get<Map<String, dynamic>>(
          '$_backendUrl/search_smart',
          queryParameters: {'q': query},
          options: Options(
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );
        if (resp.statusCode == 200 && resp.data != null) {
          final response = SmartSearchResponse.fromJson(resp.data!);
          debugPrint('[SearchServiceGlobal] Backend OK: intent=${response.intent}, '
              'results=${response.results.length}');
          return response;
        }
      } catch (e) {
        debugPrint('[SearchServiceGlobal] Backend search_smart failed: $e');
      }
    }

    // 2. Fallback : retourner une réponse vide (le ChatNotifier utilisera les anciennes méthodes)
    debugPrint('[SearchServiceGlobal] Fallback: returning empty response');
    return SmartSearchResponse(
      intent: 'general',
      params: {},
      query: query,
      results: [],
      sources: [],
    );
  }

  /// Scrape une URL via le backend /scrape.
  Future<Map<String, dynamic>> scrape(String url, {Map<String, String>? selectors}) async {
    if (_backendUrl.isEmpty || _backendUrl.contains('localhost')) {
      throw Exception('Backend URL not configured');
    }
    final resp = await _dio.get<Map<String, dynamic>>(
      '$_backendUrl/scrape',
      queryParameters: {
        'url': url,
        if (selectors != null) 'selectors': jsonEncode(selectors),
      },
      options: Options(
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    if (resp.statusCode == 200 && resp.data != null) {
      return resp.data!;
    }
    throw Exception('Scrape failed: ${resp.statusCode}');
  }

  /// Extract media (video/image) from a URL via the backend /download_media endpoint.
  Future<Map<String, dynamic>> downloadMedia(String url, {String mediaType = 'auto'}) async {
    if (_backendUrl.isEmpty || _backendUrl.contains('localhost')) {
      throw Exception('Backend URL not configured');
    }
    final resp = await _dio.post<Map<String, dynamic>>(
      '$_backendUrl/download_media',
      data: {'url': url, 'media_type': mediaType},
      options: Options(
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    if (resp.statusCode == 200 && resp.data != null) {
      return resp.data!;
    }
    throw Exception('Download media failed: ${resp.statusCode}');
  }

  /// Crawl a website recursively via the backend /crawl endpoint.
  Future<Map<String, dynamic>> crawl(String url, {int maxDepth = 2, int maxPages = 20}) async {
    if (_backendUrl.isEmpty || _backendUrl.contains('localhost')) {
      throw Exception('Backend URL not configured');
    }
    final resp = await _dio.post<Map<String, dynamic>>(
      '$_backendUrl/crawl',
      data: {'url': url, 'max_depth': maxDepth, 'max_pages': maxPages, 'same_domain': true},
      options: Options(
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 45),
      ),
    );
    if (resp.statusCode == 200 && resp.data != null) {
      return resp.data!;
    }
    throw Exception('Crawl failed: ${resp.statusCode}');
  }

  // ── Formatters (remplacent les anciens format* de EnhancedSearchService) ──

  static String formatMarkdown(SmartSearchResponse response, String originalQuery) {
    final intent = response.intent;
    final results = response.results;
    if (results.isEmpty && response.sources.isEmpty) {
      return '_Aucun résultat trouvé pour "$originalQuery"._';
    }

    final buf = StringBuffer();

    switch (intent) {
      case 'flights':
        buf.writeln('## ✈️ Vols trouvés');
        buf.writeln();
        final prices = response.prices;
        if (prices.isNotEmpty) {
          buf.writeln('### 💰 Prix détectés');
          for (final p in prices.take(6)) {
            buf.writeln('- **${p.value}** — ${p.title}');
            if (p.sourceUrl != null && p.sourceUrl!.isNotEmpty) {
              buf.writeln('  [Voir l\'offre](${p.sourceUrl})');
            }
          }
          buf.writeln();
        }
        final cards = response.cards;
        if (cards.isNotEmpty) {
          buf.writeln('### 🔍 Résultats');
          for (final c in cards.take(6)) {
            buf.writeln('- ${c.title}');
            if (c.snippet != null && c.snippet!.isNotEmpty) {
              buf.writeln('  ${c.snippet}');
            }
          }
          buf.writeln();
        }
        _writeLinksSection(buf, response.links);
        break;

      case 'hotels':
        buf.writeln('## 🏨 Hébergements');
        buf.writeln();
        final prices = response.prices;
        if (prices.isNotEmpty) {
          buf.writeln('| Établissement | Prix |');
          buf.writeln('|--------------|------|');
          for (final p in prices.take(8)) {
            buf.writeln('| ${p.title} | **${p.value}** |');
          }
          buf.writeln();
        }
        _writeLinksSection(buf, response.links);
        break;

      case 'products':
      case 'secondhand':
        buf.writeln(intent == 'secondhand'
            ? '## 🔄 Occasion/Reconditionné'
            : '## 🛒 Résultats produits');
        buf.writeln();
        final prices = response.prices;
        if (prices.isNotEmpty) {
          buf.writeln('| Produit | Prix | Source |');
          buf.writeln('|---------|------|--------|');
          for (final p in prices.take(8)) {
            final source = p.sourceUrl != null && p.sourceUrl!.isNotEmpty
                ? _extractDomain(p.sourceUrl!)
                : 'Web';
            buf.writeln('| ${p.title} | **${p.value}** | $source |');
          }
          buf.writeln();
        }
        final cards = response.cards;
        if (cards.isNotEmpty) {
          for (final c in cards.take(6)) {
            buf.writeln('- ${c.title}');
            if (c.snippet != null && c.snippet!.isNotEmpty && c.snippet != c.title) {
              buf.writeln('  ${c.snippet}');
            }
          }
          buf.writeln();
        }
        _writeLinksSection(buf, response.links);
        break;

      case 'restaurants':
        buf.writeln('## 🍽️ Restaurants');
        buf.writeln();
        final cards = response.cards;
        if (cards.isNotEmpty) {
          for (final c in cards.take(8)) {
            buf.writeln('- ${c.title}');
            if (c.snippet != null && c.snippet!.isNotEmpty) {
              buf.writeln('  ${c.snippet}');
            }
          }
          buf.writeln();
        }
        _writeLinksSection(buf, response.links);
        break;

      case 'events':
        buf.writeln('## 🎭 Événements');
        buf.writeln();
        final cards = response.cards;
        if (cards.isNotEmpty) {
          for (final c in cards.take(8)) {
            buf.writeln('- **${c.title}**');
            if (c.snippet != null && c.snippet!.isNotEmpty) {
              buf.writeln('  ${c.snippet}');
            }
          }
          buf.writeln();
        }
        _writeLinksSection(buf, response.links);
        break;

      case 'weather':
        buf.writeln('## ☀️ Météo');
        buf.writeln();
        final cards = response.cards;
        for (final c in cards.take(3)) {
          buf.writeln(c.title);
        }
        break;

      default:
        buf.writeln('## 🔍 Résultats');
        buf.writeln();
        for (final r in results.take(10)) {
          if (r.type == 'link' && r.url != null) {
            buf.writeln('- [${r.title}](${r.url})');
          } else {
            buf.writeln('- **${r.title}** ${r.value != null ? "— ${r.value}" : ""}');
          }
          if (r.snippet != null && r.snippet!.isNotEmpty) {
            buf.writeln('  ${r.snippet}');
          }
        }
    }

    // Add sources footer
    if (response.sources.isNotEmpty) {
      buf.writeln();
      buf.writeln('*Sources : ${response.sources.map((s) => s['title'] ?? s['url'] ?? '').where((t) => t.isNotEmpty).join(", ")}*');
    }

    return buf.toString();
  }

  static void _writeLinksSection(StringBuffer buf, List<SmartSearchResult> links) {
    if (links.isEmpty) return;
    buf.writeln('### 🔗 Voir aussi');
    final seen = <String>{};
    for (final link in links) {
      if (link.url == null || link.url!.isEmpty) continue;
      if (!seen.add(link.url!)) continue;
      buf.writeln('- [${link.title}](${link.url})');
    }
    buf.writeln();
  }

  static String _extractDomain(String url) {
    try {
      return Uri.parse(url).host.replaceAll('www.', '');
    } catch (_) {
      return url;
    }
  }
}
