import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/constants.dart';
import 'search_service.dart';
import 'iata_codes.dart';

/// Structured product result.
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

/// Enhanced search service.
///
/// Strategy:
/// 1. Backend /scrape endpoint for structured data extraction
/// 2. SerpAPI for structured data when API key is available
/// 3. DuckDuckGo/Google direct scraping for real prices/offers
/// 4. Direct links to comparators as fallback
///
/// The service now attempts real extraction of prices, availability,
/// and concrete offers rather than just generating search links.
class EnhancedSearchService {
  final Dio _dio;

  EnhancedSearchService() : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 10),
  ));

  String? get _serpApiKey => AppConstants.serpApiKey;

  String get _backendUrl => AppConstants.backendBaseUrl;

  // ── Backend Scraping ─────────────────────────────────────────────────────

  /// Scrape a URL via the backend /scrape endpoint.
  /// Returns structured data (prices, cards, links) extracted from the page.
  Future<Map<String, dynamic>?> scrapeBackend(String url,
      {Map<String, String>? selectors}) async {
    if (_backendUrl.isEmpty || _backendUrl.contains('localhost')) return null;
    try {
      final params = <String, dynamic>{'url': url};
      if (selectors != null && selectors.isNotEmpty) {
        params['selectors'] = jsonEncode(selectors);
      }
      final resp = await _dio.get<Map<String, dynamic>>(
        '$_backendUrl/scrape',
        queryParameters: params,
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      if (resp.statusCode == 200 && resp.data != null) {
        return resp.data;
      }
    } catch (e) {
      debugPrint('[EnhancedSearch] Backend scrape failed: $e');
    }
    return null;
  }

  /// Search Google for [query] and scrape the result snippets for prices/offers.
  Future<List<Map<String, String>>> _scrapeGoogleForPrices(String query,
      {int numResults = 8}) async {
    final results = <Map<String, String>>[];
    try {
      final encoded = Uri.encodeComponent(query);
      final url = 'https://www.google.com/search?q=$encoded&num=$numResults';
      final scraped = await scrapeBackend(url, selectors: {
        'snippet': 'div[data-sokoban-container] .VwiC3b, .g .VwiC3b, .g span.emphasize',
        'title': 'h3, div[data-sokoban-container] h3',
        'link': 'a[href^="http"]',
        'price': 'span, div, b',
      });
      if (scraped == null) return results;

      final data = scraped['data'] as List<dynamic>? ?? [];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        if (item['field'] == 'cards') {
          final values = item['values'] as List<dynamic>? ?? [];
          for (final v in values) {
            if (v is! Map<String, dynamic>) continue;
            final text = v['text'] as String? ?? '';
            final price = _extractPrice(text);
            if (price != null || text.length > 40) {
              results.add({
                'title': text.split('\n').first.trim(),
                'snippet': text,
                'price': price ?? '',
                'source': 'Google',
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[EnhancedSearch] Google price scraping failed: $e');
    }
    return results;
  }

  /// Search DuckDuckGo and extract prices/offers from result snippets.
  Future<List<Map<String, String>>> _scrapeDdgForPrices(String query,
      {int numResults = 8}) async {
    final results = <Map<String, String>>[];
    try {
      final searchService = SearchService();
      final webResults = await searchService.searchDirect(query, numResults: numResults);
      for (final r in webResults) {
        final price = _extractPrice('${r.title} ${r.snippet}');
        results.add({
          'title': r.title,
          'snippet': r.snippet,
          'price': price ?? '',
          'source': 'Web',
        });
      }
    } catch (e) {
      debugPrint('[EnhancedSearch] DDG price scraping failed: $e');
    }
    return results;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static String _s(dynamic v, [String def = '']) =>
      (v is String && v.isNotEmpty) ? v : def;

  static String? _ns(dynamic v) => (v is String && v.isNotEmpty) ? v : null;

  static List<Map<String, dynamic>> _list(dynamic data, String key) {
    final raw = data[key];
    if (raw is List) return raw.cast<Map<String, dynamic>>();
    return [];
  }

  /// Format date: yyyy-MM-dd → yyMMdd (Skyscanner)
  static String _toSkyDate(String yyyyMmDd) {
    final d = yyyyMmDd.replaceAll(RegExp(r'[/.-]'), '-');
    final parts = d.split('-');
    if (parts.length == 3) {
      return '${parts[0].substring(2)}${parts[1]}${parts[2]}';
    }
    return d;
  }

  /// Format date: yyyy-MM-dd → DD/MM/YYYY (Expedia)
  static String _toExpediaDate(String yyyyMmDd) {
    final parts = yyyyMmDd.split('-');
    if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    return yyyyMmDd;
  }

  static double _parseNum(String price) {
    return double.tryParse(
        price.replaceAll(RegExp(r'[^\d.,]'), '').replaceAll(',', '.')) ??
        double.infinity;
  }

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

  static String _extractDomain(String url) {
    try {
      return Uri.parse(url).host.replaceAll('www.', '');
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

  // ── Products ────────────────────────────────────────────────────────────

  Future<List<ProductResult>> searchProducts(String query,
      {String hl = 'fr', String gl = 'fr'}) async {
    final results = <ProductResult>[];

    final key = _serpApiKey;
    if (key != null && key.isNotEmpty) {
      try {
        final resp = await _dio.get('https://serpapi.com/search',
            queryParameters: {
              'engine': 'google_shopping',
              'q': query,
              'api_key': key,
              'gl': gl,
              'hl': hl,
              'num': 10,
            });
        if (resp.statusCode == 200) {
          final shopping = _list(resp.data, 'shopping_results');
          results.addAll(shopping.take(10).map((r) => ProductResult(
                title: _s(r['title']),
                price: _s(r['price'], _s(r['extracted_price']?.toString())),
                oldPrice: _ns(r['old_price']),
                source: _s(r['source']),
                link: _s(r['link'], _s(r['product_link'])),
                imageUrl: _ns(r['thumbnail']),
              )));
        }
      } catch (_) {}
    }

    // ── Tier 1.5: Scrape Google for real product prices ──
    if (results.isEmpty || results.every((r) => r.price == 'Rechercher')) {
      try {
        final scraped = await _scrapeGoogleForPrices('$query prix', numResults: 8);
        for (final item in scraped) {
          final price = item['price'];
          if (price != null && price.isNotEmpty && price != '') {
            results.add(ProductResult(
              title: item['title'] ?? query,
              price: price,
              source: item['source'] ?? 'Recherche',
              link: '',
            ));
          }
        }
      } catch (_) {}
    }

    // Always add direct links to major shopping platforms
    final q = Uri.encodeComponent(query);
    if (!results.any((r) => r.source.contains('Google Shopping'))) {
      results.add(ProductResult(
        title: 'Rechercher sur Google Shopping',
        price: 'Rechercher',
        source: 'Google Shopping',
        link: 'https://www.google.com/search?tbm=shop&q=$q',
      ));
    }
    results.add(ProductResult(
        title: 'Rechercher sur Amazon',
        price: 'Rechercher',
        source: 'Amazon',
        link: 'https://www.amazon.fr/s?k=$q'));
    results.add(ProductResult(
        title: 'Rechercher sur Fnac',
        price: 'Rechercher',
        source: 'Fnac',
        link: 'https://www.fnac.com/SearchResult/ResultList.aspx?Search=$q'));
    results.add(ProductResult(
        title: 'Rechercher sur Darty',
        price: 'Rechercher',
        source: 'Darty',
        link: 'https://www.darty.com/nav/extra/list?s=$q'));

    return results;
  }

  Future<List<ProductResult>> searchGoogleShopping(String query,
      {String hl = 'fr', String gl = 'fr'}) async {
    return searchProducts(query, hl: hl, gl: gl);
  }

  // ── Flights ─────────────────────────────────────────────────────────────

  Future<List<FlightResult>> searchFlights({
    required String from,
    required String to,
    required String departDate,
    String? returnDate,
    String hl = 'fr',
    String gl = 'fr',
  }) async {
    final results = <FlightResult>[];

    final fromCode = resolveIataCode(from) ?? from;
    final toCode = resolveIataCode(to) ?? to;
    final fromIata = fromCode.toUpperCase();
    final toIata = toCode.toUpperCase();
    final depart = departDate; // yyyy-MM-dd
    final retour = returnDate; // yyyy-MM-dd or null

    // ── Tier 1: SerpAPI Google Flights ──
    final key = _serpApiKey;
    if (key != null && key.isNotEmpty) {
      try {
        final params = {
          'engine': 'google_flights',
          'departure_id': fromIata,
          'arrival_id': toIata,
          'outbound_date': depart,
          'api_key': key,
          'gl': gl,
          'hl': hl,
          'currency': 'EUR',
        };
        if (retour != null) params['return_date'] = retour;

        final resp = await _dio.get(
            'https://serpapi.com/search', queryParameters: params);
        if (resp.statusCode == 200) {
          final bestFlights = _list(resp.data, 'best_flights');
          final otherFlights = _list(resp.data, 'other_flights');
          for (final f in [...bestFlights, ...otherFlights].take(12)) {
            final flights = _list(f, 'flights');
            final firstLeg = flights.isNotEmpty ? flights.first : null;
            final lastLeg = flights.isNotEmpty ? flights.last : null;
            final airline = firstLeg != null
                ? _s(firstLeg['airline'])
                : _s(f['airline']);
            final depAirport = firstLeg != null
                ? _s(firstLeg['departure_airport']?['name'])
                : from;
            final arrAirport = lastLeg != null
                ? _s(lastLeg['arrival_airport']?['name'])
                : to;

            results.add(FlightResult(
              departure: depAirport,
              arrival: arrAirport,
              date: depart,
              price: '${_s(f['price'].toString())} €',
              airline: airline.isNotEmpty ? airline : 'Compagnie',
              stops: _list(f, 'layovers').isNotEmpty
                  ? _list(f, 'layovers').length
                  : 0,
              link: _s(f['link']),
              source: 'Google Flights',
            ));
          }
        }
      } catch (_) {}
    }

    // ── Tier 1.5: Scrape Google search results for real flight prices ──
    if (results.isEmpty || results.every((r) => r.price == 'Comparer')) {
      try {
        final searchQuery =
            'vol $from $to $depart${retour != null ? ' retour $retour' : ''} prix';
        final scraped = await _scrapeGoogleForPrices(searchQuery, numResults: 6);
        for (final item in scraped) {
          final price = item['price'];
          if (price != null && price.isNotEmpty && price != '') {
            results.add(FlightResult(
              departure: from,
              arrival: to,
              date: depart,
              price: price,
              airline: item['source'] ?? 'Compagnie',
              link: '',
              source: item['source'] ?? 'Recherche',
            ));
          }
        }
      } catch (_) {}
    }

    // ── Tier 2: Direct comparator links (ALWAYS added) ──

    // Google Flights
    final gfQuery = Uri.encodeComponent(
        'Vols $from $to le $depart${retour != null ? ' retour le $retour' : ''}');
    results.add(FlightResult(
      departure: from,
      arrival: to,
      date: depart,
      price: 'Comparer',
      airline: 'Google Flights',
      link: 'https://www.google.com/travel/flights?q=$gfQuery',
      source: 'Google Flights',
    ));

    // Skyscanner — uses IATA codes + yyMMdd dates
    final skyFrom = fromIata.toLowerCase();
    final skyTo = toIata.toLowerCase();
    final skyDepart = _toSkyDate(depart);
    final skyReturn = retour != null ? _toSkyDate(retour) : null;
    final skyUrl = skyReturn != null
        ? 'https://www.skyscanner.fr/transport/flights/$skyFrom/$skyTo/$skyDepart/$skyReturn/'
        : 'https://www.skyscanner.fr/transport/flights/$skyFrom/$skyTo/$skyDepart/';
    results.add(FlightResult(
      departure: from,
      arrival: to,
      date: depart,
      price: 'Comparer',
      airline: 'Skyscanner',
      link: skyUrl,
      source: 'Skyscanner',
    ));

    // Kayak — uses IATA city codes + yyyy-MM-dd
    final kayakUrl = retour != null
        ? 'https://www.kayak.fr/flights/$fromIata-$toIata/$depart/$retour'
        : 'https://www.kayak.fr/flights/$fromIata-$toIata/$depart';
    results.add(FlightResult(
      departure: from,
      arrival: to,
      date: depart,
      price: 'Comparer',
      airline: 'Kayak',
      link: kayakUrl,
      source: 'Kayak',
    ));

    // Kiwi — uses city names in URL
    final kiwiFrom = Uri.encodeComponent(from.toLowerCase());
    final kiwiTo = Uri.encodeComponent(to.toLowerCase());
    final kiwiUrl = retour != null
        ? 'https://www.kiwi.com/fr/search/results/$kiwiFrom/$kiwiTo/$depart/$retour'
        : 'https://www.kiwi.com/fr/search/results/$kiwiFrom/$kiwiTo/$depart';
    results.add(FlightResult(
      departure: from,
      arrival: to,
      date: depart,
      price: 'Comparer',
      airline: 'Kiwi.com',
      link: kiwiUrl,
      source: 'Kiwi.com',
    ));

    // Expedia
    final expFrom = fromIata;
    final expTo = toIata;
    final expDepart = _toExpediaDate(depart);
    final expReturn = retour != null ? _toExpediaDate(retour) : null;
    final expediaUrl = StringBuffer('https://www.expedia.fr/lp/flights/'
        '$expFrom/$expTo?leg1=from:$expFrom,to:$expTo,departure:'
        '$expDepart');
    if (expReturn != null) {
      expediaUrl.write(
          '&leg2=from:$expTo,to:$expFrom,departure:$expReturn');
    }
    results.add(FlightResult(
      departure: from,
      arrival: to,
      date: depart,
      price: 'Comparer',
      airline: 'Expedia',
      link: expediaUrl.toString(),
      source: 'Expedia',
    ));

    // Opodo
    final opodoUrl = StringBuffer(
        'https://www.opodo.fr/flights/search?origin=$fromIata'
        '&destination=$toIata&outboundDate=$depart&adults=1');
    if (retour != null) opodoUrl.write('&inboundDate=$retour');
    results.add(FlightResult(
      departure: from,
      arrival: to,
      date: depart,
      price: 'Comparer',
      airline: 'Opodo',
      link: opodoUrl.toString(),
      source: 'Opodo',
    ));

    // Momondo
    final momondoUrl = retour != null
        ? 'https://www.momondo.fr/flight-search/$fromIata-$toIata/$depart/$retour'
        : 'https://www.momondo.fr/flight-search/$fromIata-$toIata/$depart';
    results.add(FlightResult(
      departure: from,
      arrival: to,
      date: depart,
      price: 'Comparer',
      airline: 'Momondo',
      link: momondoUrl,
      source: 'Momondo',
    ));

    // Sort: real prices first, then "Comparer" links
    results.sort((a, b) {
      final paIsComparer = a.price == 'Comparer';
      final pbIsComparer = b.price == 'Comparer';
      if (paIsComparer && !pbIsComparer) return 1;
      if (!paIsComparer && pbIsComparer) return -1;
      return _parseNum(a.price).compareTo(_parseNum(b.price));
    });

    return results;
  }

  // ── Hotels ──────────────────────────────────────────────────────────────

  Future<List<HotelResult>> searchHotels(String query,
      {String hl = 'fr', String gl = 'fr',
       String? checkIn, String? checkOut, int? guests}) async {
    final results = <HotelResult>[];

    // Clean the query
    final cleanQuery = query
        .replaceAll('hotel', '')
        .replaceAll('hôtel', '')
        .replaceAll('logement', '')
        .replaceAll('hébergement', '')
        .replaceAll('hebergement', '')
        .trim();
    final city = cleanQuery.isNotEmpty ? cleanQuery : query.trim();
    final cityEncoded = Uri.encodeComponent(city);

    // ── Tier 1: SerpAPI Google Hotels ──
    final key = _serpApiKey;
    if (key != null && key.isNotEmpty) {
      try {
        final resp = await _dio.get('https://serpapi.com/search',
            queryParameters: {
              'engine': 'google_hotels',
              'q': '$city hotel',
              'api_key': key,
              'gl': gl,
              'hl': hl,
            });
        if (resp.statusCode == 200) {
          final properties = _list(resp.data, 'properties');
          for (final p in properties.take(12)) {
            final price = _s(p['total_rate']?.toString(),
                _s(p['rate_per_night']?['lowest']?.toString()));
            results.add(HotelResult(
              name: _s(p['name']),
              location: _s(p['address'], _s(p['neighborhood'])),
              pricePerNight: price.isNotEmpty ? '$price €' : 'Voir prix',
              rating: (p['overall_rating'] is num)
                  ? (p['overall_rating'] as num).toDouble()
                  : null,
              description: _s(p['description']),
              link: _s(p['link']),
              source: 'Google Hotels',
            ));
          }
        }
      } catch (_) {}
    }

    // ── Tier 2: Direct booking platform links (ALWAYS added) ──

    final ci = checkIn ?? '';
    final co = checkOut ?? '';
    final g = guests ?? 2;

    // ── Tier 1.5: Scrape Google for real hotel prices ──
    if (results.isEmpty || results.every((r) => r.pricePerNight == 'Rechercher')) {
      try {
        final searchQuery = 'hotel $city${ci.isNotEmpty ? ' du $ci' : ''}${co.isNotEmpty ? ' au $co' : ''} prix';
        final scraped = await _scrapeGoogleForPrices(searchQuery, numResults: 6);
        for (final item in scraped) {
          final price = item['price'];
          if (price != null && price.isNotEmpty && price != '') {
            results.add(HotelResult(
              name: item['title'] ?? 'Hébergement $city',
              location: city,
              pricePerNight: price,
              link: '',
              source: item['source'] ?? 'Recherche',
            ));
          }
        }
      } catch (_) {}
    }

    // Booking.com
    final bookingUrl = StringBuffer(
        'https://www.booking.com/searchresults.fr.html?ss=$cityEncoded');
    if (ci.isNotEmpty) bookingUrl.write('&checkin=$ci');
    if (co.isNotEmpty) bookingUrl.write('&checkout=$co');
    bookingUrl.write('&group_adults=$g');
    results.add(HotelResult(
      name: 'Rechercher sur Booking.com',
      location: city,
      pricePerNight: 'Rechercher',
      link: bookingUrl.toString(),
      source: 'Booking.com',
    ));

    // Expedia
    final expediaUrl = StringBuffer(
        'https://www.expedia.fr/Hotel-Search?destination=$cityEncoded');
    if (ci.isNotEmpty) expediaUrl.write('&startDate=$ci');
    if (co.isNotEmpty) expediaUrl.write('&endDate=$co');
    expediaUrl.write('&rooms=$g');
    results.add(HotelResult(
      name: 'Rechercher sur Expedia',
      location: city,
      pricePerNight: 'Rechercher',
      link: expediaUrl.toString(),
      source: 'Expedia',
    ));

    // Hotels.com
    results.add(HotelResult(
      name: 'Rechercher sur Hotels.com',
      location: city,
      pricePerNight: 'Rechercher',
      link: 'https://fr.hotels.com/Hotel-Search?destination=$cityEncoded',
      source: 'Hotels.com',
    ));

    // Agoda
    results.add(HotelResult(
      name: 'Rechercher sur Agoda',
      location: city,
      pricePerNight: 'Rechercher',
      link: 'https://www.agoda.com/search?city=$cityEncoded&checkIn=$ci'
          '&checkOut=$co&guests=$g',
      source: 'Agoda',
    ));

    // Trivago
    results.add(HotelResult(
      name: 'Rechercher sur Trivago',
      location: city,
      pricePerNight: 'Rechercher',
      link: 'https://www.trivago.fr/fr/odr/hotels-$cityEncoded?search='
          '${Uri.encodeComponent('{"sQuery":"$city"}')}',
      source: 'Trivago',
    ));

    // TripAdvisor
    results.add(HotelResult(
      name: 'Rechercher sur TripAdvisor',
      location: city,
      pricePerNight: 'Rechercher',
      link: 'https://www.tripadvisor.fr/Search?q=${Uri.encodeComponent(
          'hotels $city')}&searchSessionId=',
      source: 'TripAdvisor',
    ));

    // Airbnb
    results.add(HotelResult(
      name: 'Rechercher sur Airbnb',
      location: city,
      pricePerNight: 'Rechercher',
      link: 'https://www.airbnb.fr/s/$cityEncoded/homes'
          '${ci.isNotEmpty ? '?checkin=$ci&checkout=$co&adults=$g' : ''}',
      source: 'Airbnb',
    ));

    // Abritel
    results.add(HotelResult(
      name: 'Rechercher sur Abritel',
      location: city,
      pricePerNight: 'Rechercher',
      link: 'https://www.abritel.fr/s/$cityEncoded/homes',
      source: 'Abritel',
    ));

    // Trip.com
    results.add(HotelResult(
      name: 'Rechercher sur Trip.com',
      location: city,
      pricePerNight: 'Rechercher',
      link: 'https://fr.trip.com/hotels/list?city=$cityEncoded'
          '${ci.isNotEmpty ? '&checkIn=$ci&checkOut=$co' : ''}',
      source: 'Trip.com',
    ));

    // GoVoyages
    results.add(HotelResult(
      name: 'Rechercher sur GoVoyages',
      location: city,
      pricePerNight: 'Rechercher',
      link: 'https://www.govoyages.com/hotels/search?q=$cityEncoded',
      source: 'GoVoyages',
    ));

    return results;
  }

  // ── Events ──────────────────────────────────────────────────────────────

  Future<List<WebSearchResult>> searchEvents(String query,
      {String hl = 'fr', String gl = 'fr', String? domain}) async {
    final results = <WebSearchResult>[];
    final domainQuery = domain != null && domain != 'events' ? '$domain ' : '';
    final fullQuery = '$domainQuery$query billets reservation';

    // SerpAPI Google Events
    final key = _serpApiKey;
    if (key != null && key.isNotEmpty) {
      try {
        final resp = await _dio.get('https://serpapi.com/search',
            queryParameters: {
              'engine': 'google_events',
              'q': fullQuery,
              'api_key': key,
              'gl': gl,
              'hl': hl,
            });
        if (resp.statusCode == 200) {
          final events = _list(resp.data, 'events_results');
          results.addAll(events.take(10).map((r) => WebSearchResult(
                title: _s(r['title']),
                url: _s(r['link'], _s(r['ticket_link'])),
                snippet: '${_s(r['date'])} — '
                    '${_s(r['venue']?['name'] ?? '')}',
              )));
        }
      } catch (_) {}
    }

    // Direct links to ticket platforms
    final q = Uri.encodeComponent(query.trim());

    results.add(WebSearchResult(
        title: 'Rechercher sur Ticketmaster',
        url: 'https://www.ticketmaster.fr/fr/recherche?q=$q',
        snippet: ''));
    results.add(WebSearchResult(
        title: 'Rechercher sur FNAC Spectacles',
        url: 'https://www.fnacspectacles.com/recherche?q=$q',
        snippet: ''));
    results.add(WebSearchResult(
        title: 'Rechercher sur BilletReduc',
        url: 'https://www.billetreduc.com/recherche?q=$q',
        snippet: ''));

    return results;
  }

  // ── Restaurants ─────────────────────────────────────────────────────────

  Future<List<WebSearchResult>> searchRestaurants(
      String query, String location,
      {String hl = 'fr', String gl = 'fr'}) async {
    final results = <WebSearchResult>[];
    final fullQuery = 'restaurant $query $location';

    // SerpAPI Google Local
    final key = _serpApiKey;
    if (key != null && key.isNotEmpty) {
      try {
        final resp = await _dio.get('https://serpapi.com/search',
            queryParameters: {
              'engine': 'google_local',
              'q': fullQuery,
              'api_key': key,
              'gl': gl,
              'hl': hl,
            });
        if (resp.statusCode == 200) {
          final local = _list(resp.data, 'local_results');
          results.addAll(local.take(10).map((r) => WebSearchResult(
                title: _s(r['title']),
                url: _s(r['link'], _s(r['website'])),
                snippet: '${_s(r['rating']?.toString())}⭐ — '
                    '${_s(r['type'])} — ${_s(r['address'])}',
              )));
        }
      } catch (_) {}
    }

    // Direct links
    final q = Uri.encodeComponent('$query $location'.trim());
    results.add(WebSearchResult(
        title: 'Rechercher sur TripAdvisor',
        url: 'https://www.tripadvisor.fr/Search?q=$q',
        snippet: ''));
    results.add(WebSearchResult(
        title: 'Rechercher sur TheFork',
        url: 'https://www.thefork.fr/search/$q',
        snippet: ''));
    results.add(WebSearchResult(
        title: 'Rechercher sur Google Maps',
        url: 'https://www.google.com/maps/search/$q',
        snippet: ''));

    return results;
  }

  // ── Vacation Rentals ────────────────────────────────────────────────────

  Future<List<WebSearchResult>> searchRentals(String query,
      {String? checkIn, String? checkOut, int? guests,
       String hl = 'fr', String gl = 'fr'}) async {
    final results = <WebSearchResult>[];

    final ci = checkIn ?? '';
    final co = checkOut ?? '';
    final g = guests ?? 2;
    final q = Uri.encodeComponent(query.trim());

    // SerpAPI general search for rentals
    final key = _serpApiKey;
    if (key != null && key.isNotEmpty) {
      try {
        final dateInfo = [
          if (checkIn != null) checkIn,
          if (checkOut != null) 'au $checkOut',
        ].join(' ');
        final resp = await _dio.get('https://serpapi.com/search',
            queryParameters: {
              'engine': 'google',
              'q': 'location vacances $query $dateInfo',
              'api_key': key, 'gl': gl, 'hl': hl, 'num': 10,
            });
        if (resp.statusCode == 200) {
          final organic = _list(resp.data, 'organic_results');
          results.addAll(organic.take(10).map((r) => WebSearchResult(
                title: _s(r['title']),
                url: _s(r['link']),
                snippet: _s(r['snippet']),
              )));
        }
      } catch (_) {}
    }

    // Always add direct links
    results.add(WebSearchResult(
        title: 'Rechercher sur Airbnb',
        url: 'https://www.airbnb.fr/s/$q/homes'
            '${ci.isNotEmpty ? '?checkin=$ci&checkout=$co&adults=$g' : ''}',
        snippet: ''));
    results.add(WebSearchResult(
        title: 'Rechercher sur Abritel',
        url: 'https://www.abritel.fr/s/$q/homes',
        snippet: ''));
    results.add(WebSearchResult(
        title: 'Rechercher sur Booking.com',
        url: 'https://www.booking.com/searchresults.fr.html?ss=$q'
            '${ci.isNotEmpty ? '&checkin=$ci&checkout=$co' : ''}',
        snippet: ''));
    results.add(WebSearchResult(
        title: 'Rechercher sur Casamundo',
        url: 'https://www.casamundo.fr/search?q=$q'
            '${ci.isNotEmpty ? '&startDate=$ci&endDate=$co' : ''}',
        snippet: ''));
    results.add(WebSearchResult(
        title: 'Rechercher sur HomeToGo',
        url: 'https://www.hometogo.fr/search/$q'
            '${ci.isNotEmpty ? '?arrival=$ci&departure=$co' : ''}',
        snippet: ''));

    return results;
  }

  // ── Second-Hand ─────────────────────────────────────────────────────────

  Future<List<ProductResult>> searchSecondHand(String query,
      {String hl = 'fr', String gl = 'fr', String condition = 'used'}) async {
    final conditionStr = condition == 'refurbished'
        ? 'reconditionné renouvelé'
        : 'occasion seconde main';
    final fullQuery = '$query $conditionStr';
    final results = <ProductResult>[];

    // SerpAPI
    final key = _serpApiKey;
    if (key != null && key.isNotEmpty) {
      try {
        final resp = await _dio.get('https://serpapi.com/search',
            queryParameters: {
              'engine': 'google',
              'q': fullQuery,
              'api_key': key, 'gl': gl, 'hl': hl, 'num': 10,
            });
        if (resp.statusCode == 200) {
          final organic = _list(resp.data, 'organic_results');
          for (final r in organic) {
            results.add(ProductResult(
              title: _s(r['title']),
              price: _extractPrice(_s(r['snippet'])) ?? 'Voir prix',
              source: _extractDomain(_s(r['link'])),
              link: _s(r['link']),
            ));
          }
        }
      } catch (_) {}
    }

    // ── Tier 1.5: Scrape Google for real second-hand/refurbished prices ──
    if (results.isEmpty || results.every((r) => r.price == 'Rechercher')) {
      try {
        final scraped = await _scrapeGoogleForPrices(fullQuery, numResults: 8);
        for (final item in scraped) {
          final price = item['price'];
          if (price != null && price.isNotEmpty && price != '') {
            results.add(ProductResult(
              title: item['title'] ?? query,
              price: price,
              source: item['source'] ?? 'Recherche',
              link: '',
            ));
          }
        }
      } catch (_) {}
    }

    // Direct marketplace links
    final q = Uri.encodeComponent(fullQuery);
    results.add(ProductResult(
        title: 'Rechercher sur eBay', price: 'Rechercher',
        source: 'eBay', link: 'https://www.ebay.fr/sch/i.html?_nkw=$q'));
    results.add(ProductResult(
        title: 'Rechercher sur Rakuten', price: 'Rechercher',
        source: 'Rakuten', link: 'https://fr.shopping.rakuten.com/s/$q'));
    results.add(ProductResult(
        title: 'Rechercher sur Back Market', price: 'Rechercher',
        source: 'Back Market',
        link: 'https://www.backmarket.fr/search?q=$q'));
    results.add(ProductResult(
        title: 'Rechercher sur Vinted', price: 'Rechercher',
        source: 'Vinted',
        link: 'https://www.vinted.fr/catalog?search_text=$q'));
    results.add(ProductResult(
        title: 'Rechercher sur Leboncoin', price: 'Rechercher',
        source: 'Leboncoin',
        link: 'https://www.leboncoin.fr/recherche?text=$q'));

    return results;
  }

  // ── Best Deal ───────────────────────────────────────────────────────────

  Future<List<ProductResult>> searchBestDeal(String query,
      {String hl = 'fr', String gl = 'fr'}) async {
    final results = <ProductResult>[];

    // SerpAPI Google Shopping + general search in parallel
    final key = _serpApiKey;
    if (key != null && key.isNotEmpty) {
      try {
        final results2 = await Future.wait([
          _dio.get('https://serpapi.com/search', queryParameters: {
            'engine': 'google_shopping', 'q': query,
            'api_key': key, 'gl': gl, 'hl': hl, 'num': 10,
          }),
          _dio.get('https://serpapi.com/search', queryParameters: {
            'engine': 'google', 'q': '$query meilleur prix promo comparer',
            'api_key': key, 'gl': gl, 'hl': hl, 'num': 10,
          }),
        ]);

        // Shopping results
        if (results2[0].statusCode == 200) {
          final shopping = _list(results2[0].data, 'shopping_results');
          results.addAll(shopping.take(8).map((r) => ProductResult(
                title: _s(r['title']),
                price: _s(r['price']),
                source: _s(r['source']),
                link: _s(r['link']),
              )));
        }

        // General results
        if (results2[1].statusCode == 200) {
          final organic = _list(results2[1].data, 'organic_results');
          for (final r in organic) {
            final link = _s(r['link']);
            if (!results.any((x) => x.link == link)) {
              results.add(ProductResult(
                title: _s(r['title']),
                price: _extractPrice(_s(r['snippet'])) ?? 'Voir prix',
                source: _extractDomain(link),
                link: link,
              ));
            }
          }
        }
      } catch (_) {}
    }

    // Direct links
    final q = Uri.encodeComponent('$query meilleur prix');
    results.add(ProductResult(
        title: 'Rechercher sur Google Shopping', price: 'Rechercher',
        source: 'Google Shopping',
        link: 'https://www.google.com/search?tbm=shop&q=$q'));
    results.add(ProductResult(
        title: 'Rechercher sur Idealo', price: 'Rechercher',
        source: 'Idealo',
        link: 'https://www.idealo.fr/prix/$q'));
    results.add(ProductResult(
        title: 'Rechercher sur LeGuide', price: 'Rechercher',
        source: 'LeGuide',
        link: 'https://www.leguide.com/s/$q'));

    // Sort by price
    results.sort((a, b) => _parseNum(a.price).compareTo(_parseNum(b.price)));

    return results;
  }

  // ── General enhanced search ─────────────────────────────────────────────

  Future<List<WebSearchResult>> enhancedSearch(String query,
      {String hl = 'fr', String gl = 'fr'}) async {
    final key = _serpApiKey;
    if (key == null || key.isEmpty) return [];

    try {
      final resp = await _dio.get('https://serpapi.com/search',
          queryParameters: {
            'engine': 'google',
            'q': query,
            'api_key': key,
            'gl': gl,
            'hl': hl,
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

  // ── Ranking System ─────────────────────────────────────────────────────

  static List<Map<String, dynamic>> rankTop3(List<ProductResult> products) {
    if (products.isEmpty) return [];
    final real = products
        .where((p) => p.price != 'Rechercher' && p.price != 'Voir prix')
        .toList();

    final scored = <Map<String, dynamic>>[];
    for (final p in real) {
      double score = 5.0;
      final priceVal = double.tryParse(
          p.price.replaceAll(RegExp(r'[^\d.,]'), '').replaceAll(',', '.'));
      if (priceVal != null && priceVal > 0) {
        score += (5000.0 / (priceVal + 100)).clamp(0.0, 5.0);
      }
      if (p.source.contains('amazon') || p.source.contains('fnac') ||
          p.source.contains('darty') || p.source.contains('boulanger')) {
        score += 1.0;
      }
      scored.add({'product': p, 'score': score});
    }
    scored.sort(
        (a, b) => (b['score'] as double).compareTo(a['score'] as double));

    final top = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final s in scored) {
      final p = s['product'] as ProductResult;
      if (seen.add(p.link)) top.add(s);
      if (top.length >= 3) break;
    }
    if (top.isNotEmpty) top[0]['rank'] = 'best';
    if (top.length >= 2) top[1]['rank'] = 'alternative1';
    if (top.length >= 3) top[2]['rank'] = 'alternative2';

    for (final p in products.where((p) => p.price == 'Rechercher').take(2)) {
      top.add({'product': p, 'score': -1.0, 'rank': 'search'});
    }
    return top;
  }

  static List<Map<String, dynamic>> rankTopHotels(List<HotelResult> hotels) {
    if (hotels.isEmpty) return [];
    final real = hotels
        .where((h) =>
            h.pricePerNight != 'Rechercher' && h.pricePerNight != 'Voir prix')
        .toList();
    final scored = <Map<String, dynamic>>[];
    for (final h in real) {
      double score = 5.0;
      final priceVal = double.tryParse(h.pricePerNight
          .replaceAll(RegExp(r'[^\d.,]'), '')
          .replaceAll(',', '.'));
      if (priceVal != null && priceVal > 0) {
        score += (500.0 / (priceVal + 10)).clamp(0.0, 3.0);
      }
      if (h.rating != null) score += h.rating! * 0.5;
      scored.add({'hotel': h, 'score': score});
    }
    scored.sort(
        (a, b) => (b['score'] as double).compareTo(a['score'] as double));
    final top = <Map<String, dynamic>>[];
    for (int i = 0; i < scored.length && i < 3; i++) {
      top.add({
        'hotel': scored[i]['hotel'],
        'score': scored[i]['score'],
        'rank': i == 0
            ? 'best'
            : (i == 1 ? 'alternative1' : 'alternative2'),
      });
    }
    return top;
  }

  // ── Formatting ──────────────────────────────────────────────────────────

  static String formatProducts(List<ProductResult> products, String query) {
    if (products.isEmpty) {
      return '_Aucun résultat produit trouvé pour "$query"._';
    }
    final buf = StringBuffer();
    buf.writeln('## 🛍️ Résultats — $query');
    buf.writeln();
    buf.writeln('| Produit | Prix | Marchand |');
    buf.writeln('|---------|------|----------|');
    for (final p in products.take(8)) {
      final oldPrice = p.oldPrice != null ? ' ~~${p.oldPrice}~~' : '';
      buf.writeln('| [${_escapeMd(p.title)}](${p.link}) | '
          '**${_escapeMd(p.price)}**$oldPrice | ${_escapeMd(p.source)} |');
    }
    return buf.toString();
  }

  static String formatFlights(List<FlightResult> flights) {
    if (flights.isEmpty) return '_Aucun vol trouvé._';

    final withPrices = flights
        .where((f) => f.price != 'Comparer' && f.price != 'Rechercher')
        .toList();
    final comparators = flights
        .where((f) => f.price == 'Comparer')
        .toList();

    final buf = StringBuffer();
    buf.writeln('## ✈️ Vols trouvés');
    buf.writeln();

    if (withPrices.isNotEmpty) {
      buf.writeln('### 💰 Meilleures offres');
      for (final f in withPrices.take(6)) {
        final stopsStr = f.stops != null && f.stops! > 0
            ? ' (${f.stops} escale(s))'
            : ' (direct)';
        buf.writeln('- **${f.price}** — ${f.airline}$stopsStr');
        buf.writeln('  ${f.departure} → ${f.arrival}, ${f.date}');
        if (f.link.isNotEmpty) {
          buf.writeln('  [Voir l\'offre](${f.link}) — _${f.source}_');
        }
        buf.writeln();
      }
    }

    if (comparators.isNotEmpty) {
      buf.writeln('### 🔎 Comparer sur');
      final seen = <String>{};
      for (final c in comparators) {
        if (seen.add(c.source)) {
          buf.writeln('- [${c.source}](${c.link})');
        }
      }
    }

    return buf.toString();
  }

  static String formatHotels(List<HotelResult> hotels, String query) {
    if (hotels.isEmpty) return '_Aucun logement trouvé pour "$query"._';

    final withPrices = hotels
        .where((h) => h.pricePerNight != 'Rechercher')
        .toList();
    final platforms = hotels
        .where((h) => h.pricePerNight == 'Rechercher')
        .toList();

    final buf = StringBuffer();
    buf.writeln('## 🏨 Hébergements — $query');
    buf.writeln();

    if (withPrices.isNotEmpty) {
      buf.writeln('| Établissement | Prix/nuit | Note |');
      buf.writeln('|--------------|-----------|------|');
      for (final h in withPrices.take(8)) {
        final rating =
            h.rating != null ? '⭐${h.rating!.toStringAsFixed(1)}' : '-';
        buf.writeln('| [${_escapeMd(h.name)}](${h.link}) | '
            '${_escapeMd(h.pricePerNight)} | $rating |');
      }
    }

    if (platforms.isNotEmpty) {
      buf.writeln();
      buf.writeln('### 🔎 Réserver sur');
      for (final p in platforms) {
        buf.writeln('- [${p.name}](${p.link})');
      }
    }

    return buf.toString();
  }

  static String formatSecondHand(List<ProductResult> results, String query) {
    if (results.isEmpty) {
      return '_Aucun résultat occasion trouvé pour "$query"._';
    }
    final ranked = rankTop3(results);
    if (ranked.isEmpty) {
      return '_Aucun résultat avec prix trouvé pour "$query"._';
    }

    final buf = StringBuffer();
    buf.writeln('## 🔄 Occasion/Reconditionné — $query');
    buf.writeln();
    buf.writeln('| 🏆 | Produit | Prix | Marchand |');
    buf.writeln('|-----|---------|------|----------|');

    final labels = {
      'best': '🥇 Meilleur',
      'alternative1': '🥈 Alternative',
      'alternative2': '🥉 Alternative',
      'search': '🔍',
    };
    for (final r in ranked) {
      final p = r['product'] as ProductResult;
      final rank = r['rank'] as String;
      final label = labels[rank] ?? '⭐';
      buf.writeln('| $label | [${_escapeMd(p.title)}](${p.link}) | '
          '**${_escapeMd(p.price)}** | ${_escapeMd(p.source)} |');
    }
    return buf.toString();
  }

  static String formatBestDeal(List<ProductResult> results, String query) {
    if (results.isEmpty) return '_Aucun deal trouvé pour "$query"._';
    final ranked = rankTop3(results);
    if (ranked.isEmpty) {
      return '_Aucun résultat avec prix trouvé pour "$query"._';
    }

    final buf = StringBuffer();
    buf.writeln('## 💰 Meilleurs Deals — $query');
    buf.writeln();
    buf.writeln('| 🏆 | Produit | Prix | Marchand |');
    buf.writeln('|-----|---------|------|----------|');

    final labels = {
      'best': '🥇 Meilleur deal',
      'alternative1': '🥈 Deal 2',
      'alternative2': '🥉 Deal 3',
    };
    for (final r in ranked) {
      if (r['rank'] == 'search') continue;
      final p = r['product'] as ProductResult;
      final rank = r['rank'] as String;
      final label = labels[rank] ?? '⭐';
      buf.writeln('| $label | [${_escapeMd(p.title)}](${p.link}) | '
          '**${_escapeMd(p.price)}** | ${_escapeMd(p.source)} |');
    }
    buf.writeln();
    buf.writeln('*Prix comparés sur plusieurs sources.*');
    return buf.toString();
  }

  static String formatEvents(List<WebSearchResult> events, String query,
      {String? domain}) {
    if (events.isEmpty) return '_Aucun événement trouvé pour "$query"._';

    final icons = {
      'concerts': '🎵 Concerts',
      'museums': '🏛️ Musées',
      'festivals': '🎪 Festivals',
      'theater': '🎭 Théâtre',
      'sports': '⚽ Sports',
      'exhibitions': '🖼️ Expositions',
      'events': '📅 Événements',
    };
    final icon = icons[domain] ?? '📅 Événements';
    final buf = StringBuffer();
    buf.writeln('## $icon — $query');
    buf.writeln();

    int count = 0;
    for (final e in events) {
      if (e.title.contains('Rechercher sur')) continue;
      count++;
      buf.writeln('- **[${_escapeMd(e.title)}](${e.url})**');
      if (e.snippet.isNotEmpty) buf.writeln('  ${_escapeMd(e.snippet)}');
      buf.writeln();
      if (count >= 8) break;
    }

    final searchLinks =
        events.where((e) => e.title.contains('Rechercher sur'));
    if (searchLinks.isNotEmpty) {
      buf.writeln('### 🔎 Billetterie');
      for (final link in searchLinks) {
        buf.writeln('- [${link.title}](${link.url})');
      }
    }
    return buf.toString();
  }

  static String formatRestaurants(
      List<WebSearchResult> restaurants, String query) {
    if (restaurants.isEmpty) {
      return '_Aucun restaurant trouvé pour "$query"._';
    }
    final buf = StringBuffer();
    buf.writeln('## 🍽️ Restaurants — $query');
    buf.writeln();

    int count = 0;
    for (final r in restaurants) {
      if (r.title.contains('Rechercher sur')) continue;
      count++;
      buf.writeln('- **[${_escapeMd(r.title)}](${r.url})**');
      if (r.snippet.isNotEmpty) buf.writeln('  ${_escapeMd(r.snippet)}');
      buf.writeln();
      if (count >= 8) break;
    }

    final searchLinks =
        restaurants.where((r) => r.title.contains('Rechercher sur'));
    if (searchLinks.isNotEmpty) {
      buf.writeln('### 🔎 Voir aussi');
      for (final link in searchLinks) {
        buf.writeln('- [${link.title}](${link.url})');
      }
    }
    return buf.toString();
  }

  static String formatRentals(List<WebSearchResult> rentals, String query) {
    if (rentals.isEmpty) {
      return '_Aucune location trouvée pour "$query"._';
    }
    final buf = StringBuffer();
    buf.writeln('## 🏠 Locations Vacances — $query');
    buf.writeln();

    int count = 0;
    for (final r in rentals) {
      if (r.title.contains('Rechercher sur')) continue;
      count++;
      buf.writeln('- **[${_escapeMd(r.title)}](${r.url})**');
      if (r.snippet.isNotEmpty) {
        final maxLen = r.snippet.length > 200 ? 200 : r.snippet.length;
        buf.writeln('  ${_escapeMd(r.snippet.substring(0, maxLen))}');
      }
      buf.writeln();
      if (count >= 8) break;
    }

    final searchLinks =
        rentals.where((r) => r.title.contains('Rechercher sur'));
    if (searchLinks.isNotEmpty) {
      buf.writeln('### 🔎 Plateformes');
      for (final link in searchLinks) {
        buf.writeln('- [${link.title}](${link.url})');
      }
    }
    return buf.toString();
  }
}
