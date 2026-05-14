import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/constants.dart';
import 'search_service.dart';

/// Structured product result from Google Shopping.
class ProductResult {
  final String title;
  final String price;
  final String? oldPrice;
  final String source;
  final String link;
  final String? imageUrl;

  const ProductResult({
    required this.title,
    required this.price,
    this.oldPrice,
    required this.source,
    required this.link,
    this.imageUrl,
  });
}

/// Structured flight result.
class FlightResult {
  final String departure;
  final String arrival;
  final String date;
  final String price;
  final String airline;
  final int? stops;
  final String link;
  final String source;

  const FlightResult({
    required this.departure,
    required this.arrival,
    required this.date,
    required this.price,
    required this.airline,
    this.stops,
    required this.link,
    required this.source,
  });
}

/// Structured hotel/accommodation result.
class HotelResult {
  final String name;
  final String location;
  final String pricePerNight;
  final double? rating;
  final String? description;
  final String link;
  final String source;

  const HotelResult({
    required this.name,
    required this.location,
    required this.pricePerNight,
    this.rating,
    this.description,
    required this.link,
    required this.source,
  });
}

/// Enhanced search with support for products, flights, hotels.
/// Uses SerpAPI for structured results with DuckDuckGo fallback.
class EnhancedSearchService {
  final Dio _dio;

  EnhancedSearchService() : _dio = Dio();

  String? get _serpApiKey => AppConstants.serpApiKey;

  // ── Helpers ─────────────────────────────────────────────────────────────

  static String _s(dynamic v, [String def = '']) => (v as String?) ?? def;

  static String? _ns(dynamic v) => v as String?;

  static List<Map<String, dynamic>> _list(dynamic data, String key) {
    final raw = data[key];
    if (raw is List) return raw.cast<Map<String, dynamic>>();
    return [];
  }

  // ── Structured Google Shopping search ───────────────────────────────────

  Future<List<ProductResult>> searchProducts(String query,
      {String country = 'fr'}) async {
    final key = _serpApiKey;
    if (key == null || key.isEmpty) return [];

    try {
      final resp = await _dio.get('https://serpapi.com/search',
          queryParameters: {
            'engine': 'google_shopping',
            'q': query,
            'api_key': key,
            'gl': country,
            'hl': 'fr',
            'num': 10,
          });

      if (resp.statusCode != 200) return [];

      final results = _list(resp.data, 'shopping_results');
      return results.take(10).map((r) => ProductResult(
        title: _s(r['title']),
        price: _s(r['price'], _s(r['extracted_price']?.toString())),
        oldPrice: _ns(r['old_price']),
        source: _s(r['source']),
        link: _s(r['link'], _s(r['product_link'])),
        imageUrl: _ns(r['thumbnail']),
      )).toList();
    } catch (_) {
      return [];
    }
  }

  /// Search products via regular Google with shopping intent.
  Future<List<ProductResult>> searchGoogleShopping(String query,
      {String country = 'fr'}) async {
    final key = _serpApiKey;
    if (key == null || key.isEmpty) return [];

    try {
      final resp = await _dio.get('https://serpapi.com/search',
          queryParameters: {
            'engine': 'google',
            'q': '$query prix achat',
            'api_key': key,
            'gl': country,
            'hl': 'fr',
            'num': 20,
          });

      if (resp.statusCode != 200) return [];

      final results = <ProductResult>[];

      final organic = _list(resp.data, 'organic_results');
      for (final r in organic.take(10)) {
        final snippet = _s(r['snippet']);
        final price = _extractPrice(snippet);
        final link = _s(r['link']);
        if (price != null) {
          results.add(ProductResult(
            title: _s(r['title']),
            price: price,
            source: _extractDomain(link),
            link: link,
          ));
        }
      }

      final shopping = _list(resp.data, 'shopping_results');
      for (final s in shopping.take(10)) {
        results.add(ProductResult(
          title: _s(s['title']),
          price: _s(s['price'], _s(s['extracted_price']?.toString())),
          source: _s(s['source']),
          link: _s(s['link'], _s(s['product_link'])),
        ));
      }

      return results;
    } catch (_) {
      return [];
    }
  }

  // ── Flight search ────────────────────────────────────────────────────────

  Future<List<FlightResult>> searchFlights({
    required String from,
    required String to,
    required String departDate,
    String? returnDate,
    String country = 'fr',
  }) async {
    final key = _serpApiKey;
    if (key == null || key.isEmpty) return [];

    final query =
        'vol direct $from $to $departDate${returnDate != null ? ' retour $returnDate' : ''} pas cher';

    try {
      final resp = await _dio.get('https://serpapi.com/search',
          queryParameters: {
            'engine': 'google',
            'q': query,
            'api_key': key,
            'gl': country,
            'hl': 'fr',
            'num': 15,
          });

      if (resp.statusCode != 200) return [];

      final results = <FlightResult>[];
      final organic = _list(resp.data, 'organic_results');

      for (final r in organic) {
        final snippet = _s(r['snippet']);
        final price = _extractPrice(snippet);
        final link = _s(r['link']);
        if (price != null &&
            (snippet.contains('€') ||
                snippet.contains('EUR') ||
                snippet.contains('vol'))) {
          results.add(FlightResult(
            departure: from,
            arrival: to,
            date: departDate,
            price: price,
            airline: _s(r['title']),
            stops:
                snippet.contains('escale') || snippet.contains('stop') ? 1 : 0,
            link: link,
            source: _extractDomain(link),
          ));
        }
      }

      // Sort by price
      results.sort((a, b) {
        final pa =
            double.tryParse(a.price.replaceAll(RegExp(r'[^\d.]'), '')) ??
                double.infinity;
        final pb =
            double.tryParse(b.price.replaceAll(RegExp(r'[^\d.]'), '')) ??
                double.infinity;
        return pa.compareTo(pb);
      });

      // Generate direct search links to flight comparison sites
      final directLinks =
          _generateFlightLinks(from, to, departDate, returnDate);
      for (final link in directLinks) {
        results.add(FlightResult(
          departure: from,
          arrival: to,
          date: departDate,
          price: 'Rechercher',
          airline: link['name']!,
          link: link['url']!,
          source: link['name']!,
        ));
      }

      return results;
    } catch (_) {
      return [];
    }
  }

  List<Map<String, String>> _generateFlightLinks(
      String from, String to, String departDate, String? returnDate) {
    final links = <Map<String, String>>[];
    links.add({
      'name': 'Skyscanner',
      'url':
          'https://www.skyscanner.fr/transport/flights/${from.toLowerCase()}/${to.toLowerCase()}/$departDate/${returnDate ?? ''}',
    });
    links.add({
      'name': 'Google Flights',
      'url':
          'https://www.google.com/travel/flights?q=Flights+to+${to.toUpperCase()}+from+${from.toUpperCase()}+on+$departDate${returnDate != null ? '+return+$returnDate' : ''}',
    });
    links.add({
      'name': 'Kayak',
      'url':
          'https://www.kayak.fr/flights/$from-$to/$departDate${returnDate != null ? '/$returnDate' : ''}',
    });
    links.add({
      'name': 'Opodo',
      'url':
          'https://www.opodo.fr/flights/search?origin=$from&destination=$to&departureDate=$departDate${returnDate != null ? '&returnDate=$returnDate' : ''}',
    });
    return links;
  }

  // ── Hotel/Accommodation search ───────────────────────────────────────────

  Future<List<HotelResult>> searchHotels(String query,
      {String country = 'fr'}) async {
    final key = _serpApiKey;
    if (key == null || key.isEmpty) return [];

    try {
      final resp = await _dio.get('https://serpapi.com/search',
          queryParameters: {
            'engine': 'google',
            'q': '$query hotel reservation prix',
            'api_key': key,
            'gl': country,
            'hl': 'fr',
            'num': 15,
          });

      if (resp.statusCode != 200) return [];

      final results = <HotelResult>[];
      final organic = _list(resp.data, 'organic_results');

      for (final r in organic) {
        final snippet = _s(r['snippet']);
        final price = _extractPrice(snippet);
        final link = _s(r['link']);
        results.add(HotelResult(
          name: _s(r['title']),
          location: _extractLocation(snippet),
          pricePerNight: price ?? 'Voir prix',
          rating: _extractRating(snippet),
          description: snippet,
          link: link,
          source: _extractDomain(link),
        ));

        if (results.length >= 10) break;
      }

      // Add booking search links
      final encoded = Uri.encodeComponent(query
          .replaceAll('hotel', '')
          .replaceAll('logement', '')
          .trim());
      results.add(HotelResult(
        name: 'Rechercher sur Booking.com',
        location: '',
        pricePerNight: 'Rechercher',
        link: 'https://www.booking.com/searchresults.fr.html?ss=$encoded',
        source: 'Booking.com',
      ));
      results.add(HotelResult(
        name: 'Rechercher sur Airbnb',
        location: '',
        pricePerNight: 'Rechercher',
        link: 'https://www.airbnb.fr/s/$encoded/homes',
        source: 'Airbnb',
      ));

      return results;
    } catch (_) {
      return [];
    }
  }

  // ── General enhanced search (SerpAPI with DuckDuckGo fallback) ──────────

  Future<List<WebSearchResult>> enhancedSearch(String query,
      {String country = 'fr'}) async {
    final key = _serpApiKey;
    if (key == null || key.isEmpty) return [];

    try {
      final resp = await _dio.get('https://serpapi.com/search',
          queryParameters: {
            'engine': 'google',
            'q': query,
            'api_key': key,
            'gl': country,
            'hl': 'fr',
            'num': 10,
          });

      if (resp.statusCode != 200) return [];

      final organic = _list(resp.data, 'organic_results');
      return organic.take(10).map((r) => WebSearchResult(
        title: _s(r['title']),
        url: _s(r['link']),
        snippet: _s(r['snippet']),
      )).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Formatting helpers ───────────────────────────────────────────────────

  /// Format product results as rich markdown for chat.
  static String formatProducts(List<ProductResult> products, String query) {
    if (products.isEmpty) {
      return '_Aucun resultat produit trouve pour "$query"._';
    }

    final buf = StringBuffer();
    buf.writeln('## 🛍️ Résultats — $query');
    buf.writeln();
    buf.writeln('| Produit | Prix | Marchand |');
    buf.writeln('|---------|------|----------|');

    for (final p in products.take(8)) {
      final oldPrice = p.oldPrice != null ? ' ~~$p.oldPrice~~' : '';
      buf.writeln(
          '| [${_escapeMd(p.title)}](${p.link}) | **${_escapeMd(p.price)}**$oldPrice | ${_escapeMd(p.source)} |');
    }

    return buf.toString();
  }

  /// Format flight results as rich markdown.
  static String formatFlights(List<FlightResult> flights) {
    if (flights.isEmpty) return '_Aucun vol trouve._';

    final searchResults =
        flights.where((f) => f.airline != 'Rechercher').toList();
    final searchLinks =
        flights.where((f) => f.airline == 'Rechercher').toList();

    final buf = StringBuffer();
    buf.writeln('## ✈️ Vols trouvés');
    buf.writeln();

    if (searchResults.isNotEmpty) {
      for (final f in searchResults.take(5)) {
        final stops = f.stops != null && f.stops! > 0
            ? ' (${f.stops} escale(s))'
            : ' (direct)';
        buf.writeln('- **${f.price}** — ${f.airline}$stops');
        buf.writeln('  ${f.departure} → ${f.arrival}, ${f.date}');
        buf.writeln('  [Voir l\'offre](${f.link}) — _${f.source}_');
        buf.writeln();
      }
    }

    if (searchLinks.isNotEmpty) {
      buf.writeln('### 🔎 Comparateurs de vols');
      for (final link in searchLinks) {
        buf.writeln('- [Rechercher sur ${link.source}](${link.link})');
      }
    }

    return buf.toString();
  }

  /// Format hotel results as rich markdown.
  static String formatHotels(List<HotelResult> hotels, String query) {
    if (hotels.isEmpty) return '_Aucun logement trouve pour "$query"._';

    final buf = StringBuffer();
    buf.writeln('## 🏨 Hébergements — $query');
    buf.writeln();
    buf.writeln('| Établissement | Prix/nuit | Note |');
    buf.writeln('|--------------|-----------|------|');

    for (final h in hotels.take(8)) {
      final rating =
          h.rating != null ? '⭐${h.rating!.toStringAsFixed(1)}' : '-';
      buf.writeln(
          '| [${_escapeMd(h.name)}](${h.link}) | ${_escapeMd(h.pricePerNight)} | $rating |');
    }

    return buf.toString();
  }

  /// Format rich result summary when no structured results are available.
  static String formatRichSummary(
      List<WebSearchResult> results, String query, String category) {
    if (results.isEmpty) {
      return '_Aucun resultat trouve pour "$query". Essayez avec des termes differents._';
    }

    final buf = StringBuffer();
    final emoji = {
      'products': '🛍️',
      'flights': '✈️',
      'hotels': '🏨',
      'general': '🔍',
    }[category] ?? '🔍';

    buf.writeln('## $emoji Résultats — $query');
    buf.writeln();

    for (var i = 0; i < results.length && i < 5; i++) {
      final r = results[i];
      buf.writeln('${i + 1}. **[${_escapeMd(r.title)}](${r.url})**');
      if (r.snippet.isNotEmpty) {
        final maxLen = r.snippet.length > 300 ? 300 : r.snippet.length;
        buf.writeln('   ${_escapeMd(r.snippet.substring(0, maxLen))}');
      }
      buf.writeln();
    }

    return buf.toString();
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  static String? _extractPrice(String text) {
    final patterns = [
      RegExp(r'(\d[\d\s]*[\d.,]*\s?[€$])\s'),
      RegExp(r'(\d[\d\s]*[\d.,]*\s?(?:EUR|USD|€|\$))'),
      RegExp(r'prix[:\s]*(\d[\d\s]*[\d.,]*\s?[€$])'),
      RegExp(r'à partir de (\d[\d\s]*[\d.,]*\s?[€$])'),
      RegExp(r'dès (\d[\d\s]*[\d.,]*\s?[€$])'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) return match.group(1)?.trim();
    }
    return null;
  }

  static double? _extractRating(String text) {
    final match =
        RegExp(r'(\d[.,]\d)\s*(?:/5|sur\s*5|étoiles)').firstMatch(text);
    if (match != null) {
      return double.tryParse(match.group(1)!.replaceAll(',', '.'));
    }
    return null;
  }

  static String _extractLocation(String text) {
    final match = RegExp(
            r'à\s+([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)*)')
        .firstMatch(text);
    if (match != null) return match.group(1)!;
    final match2 = RegExp(r'dans\s+([A-ZÀ-Ÿ][a-zà-ÿ]+)').firstMatch(text);
    if (match2 != null) return match2.group(1)!;
    return '';
  }

  static String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceAll('www.', '');
    } catch (_) {
      return url;
    }
  }

  static String _escapeMd(String text) {
    return text
        .replaceAll('|', '\\|')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]');
  }
}
