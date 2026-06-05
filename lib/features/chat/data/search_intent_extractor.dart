import '../../../../core/language/language_service.dart';

/// Structured parameters extracted from a user search query.
class SearchParams {
  final String intent; // 'flights', 'hotels', 'products', 'weather', 'events', 'restaurants', 'rentals', 'secondhand', 'bestdeal', 'general'
  final String? query; // Cleaned search query
  final String? category; // Sub-category (concert, museum, refurbished, etc.)
  final String? location; // City/place
  final String? fromLocation;
  final String? toLocation;
  final String? departDate;
  final String? returnDate;
  final String? checkIn;
  final String? checkOut;
  final int? guests;
  final String? priceRange; // 'cheapest', 'budget', 'mid', 'luxury'
  final String? color; // 'noir', 'bleu', etc.
  final String? condition; // 'new', 'used', 'refurbished', 'any'
  final String? sortBy; // 'price_asc', 'price_desc', 'rating', 'distance'
  final String? domain; // Specific domain hint (e.g., 'concerts', 'musées')

  const SearchParams({
    required this.intent,
    this.query,
    this.category,
    this.location,
    this.fromLocation,
    this.toLocation,
    this.departDate,
    this.returnDate,
    this.checkIn,
    this.checkOut,
    this.guests,
    this.priceRange,
    this.color,
    this.condition,
    this.sortBy,
    this.domain,
  });

  Map<String, String> toMap() {
    final m = <String, String>{'intent': intent};
    if (query != null) m['query'] = query!;
    if (category != null) m['category'] = category!;
    if (location != null) m['location'] = location!;
    if (fromLocation != null) m['from'] = fromLocation!;
    if (toLocation != null) m['to'] = toLocation!;
    if (departDate != null) m['departDate'] = departDate!;
    if (returnDate != null) m['returnDate'] = returnDate!;
    if (checkIn != null) m['checkIn'] = checkIn!;
    if (checkOut != null) m['checkOut'] = checkOut!;
    if (guests != null) m['guests'] = guests.toString();
    if (priceRange != null) m['priceRange'] = priceRange!;
    if (color != null) m['color'] = color!;
    if (condition != null) m['condition'] = condition!;
    if (sortBy != null) m['sortBy'] = sortBy!;
    if (domain != null) m['domain'] = domain!;
    return m;
  }

  @override
  String toString() => 'SearchParams(${toMap()})';
}

/// Result from a search, with a quality/price score for ranking.
class SearchResult {
  final String title;
  final String description;
  final String link;
  final String source;
  final String? price;
  final double? rating;
  final double? qualityPriceScore; // 0.0-10.0, higher = better value
  final String? imageUrl;
  final String? category;
  final Map<String, String>? metadata;

  const SearchResult({
    required this.title,
    required this.description,
    required this.link,
    required this.source,
    this.price,
    this.rating,
    this.qualityPriceScore,
    this.imageUrl,
    this.category,
    this.metadata,
  });
}

/// Learns and improves search extraction over time.
/// Remembers successful search patterns and parameter combinations.
class SearchMemory {
  final Map<String, List<String>> _successfulPatterns = {};
  final Map<String, List<SearchParams>> _successfulSearches = {};
  final Map<String, int> _domainSuccessCount = {};
  final Map<String, List<String>> _effectiveKeywords = {};
  static const int _maxMemorySize = 100;

  void recordSuccess(String intent, String originalQuery, SearchParams params) {
    _successfulSearches.putIfAbsent(intent, () => []);
    final searches = _successfulSearches[intent]!;
    searches.add(params);
    if (searches.length > _maxMemorySize) searches.removeAt(0);

    _domainSuccessCount[intent] = (_domainSuccessCount[intent] ?? 0) + 1;
  }

  void recordPattern(String intent, String pattern) {
    _successfulPatterns.putIfAbsent(intent, () => []);
    final patterns = _successfulPatterns[intent]!;
    if (!patterns.contains(pattern)) patterns.add(pattern);
    if (patterns.length > 50) patterns.removeAt(0);
  }

  void recordKeywords(String intent, List<String> keywords) {
    _effectiveKeywords.putIfAbsent(intent, () => []);
    final kw = _effectiveKeywords[intent]!;
    for (final k in keywords) {
      if (!kw.contains(k)) kw.add(k);
    }
    if (kw.length > 100) kw.removeRange(0, kw.length - 100);
  }

  List<String>? getPatterns(String intent) =>
      _successfulPatterns[intent]?.toList();

  List<SearchParams>? getPastSearches(String intent) =>
      _successfulSearches[intent]?.toList();

  List<String>? getKeywords(String intent) =>
      _effectiveKeywords[intent]?.toList();

  int successCount(String intent) => _domainSuccessCount[intent] ?? 0;

  /// Suggest additional keywords for a given intent based on past successes.
  List<String> suggestKeywords(String intent, String query) {
    final keywords = _effectiveKeywords[intent];
    if (keywords == null || keywords.isEmpty) return [];
    return keywords.where((k) => query.contains(k)).toList();
  }
}

/// Generalized search intent extractor.
/// Extracts structured parameters from natural language queries
/// for any search domain: flights, hotels, products, events, restaurants, etc.
class SearchIntentExtractor {
  final SearchMemory _memory = SearchMemory();

  SearchMemory get memory => _memory;

  /// Main entry point: extract search parameters from a user message.
  SearchParams extract(String message, AppLanguage lang) {
    final lower = message.toLowerCase().trim();

    // Detect purchase intent modifiers
    final condition = _detectCondition(lower);
    final priceRange = _detectPriceRange(lower, lang);
    final sortBy = _detectSortPreference(lower);

    // Classify the primary intent
    final intent = _classifyIntent(message, lang);

    switch (intent) {
      case 'flights':
        return _extractFlightParams(message, lang, priceRange, sortBy);

      case 'hotels':
        return _extractHotelParams(message, lang, priceRange, sortBy);

      case 'weather':
        return _extractWeatherParams(message, lang);

      case 'products':
        return _extractProductParams(message, lang, condition, priceRange, sortBy);

      case 'secondhand':
        return _extractSecondHandParams(message, lang, priceRange, sortBy);

      case 'bestdeal':
        return _extractBestDealParams(message, lang, condition, priceRange, sortBy);

      case 'events':
        return _extractEventParams(message, lang, priceRange);

      case 'restaurants':
        return _extractRestaurantParams(message, lang, priceRange, sortBy);

      case 'rentals':
        return _extractRentalParams(message, lang, priceRange, sortBy);

      default:
        return SearchParams(
          intent: 'general',
          query: _cleanQuery(message),
          priceRange: priceRange,
          sortBy: sortBy,
        );
    }
  }

  // ── Intent Classification ──────────────────────────────────────────────────

  String _classifyIntent(String message, AppLanguage lang) {
    final lower = message.toLowerCase();

    // Flights (most specific patterns first)
    if (_isFlightIntent(lower, lang)) return 'flights';

    // Hotels
    if (_isHotelIntent(lower, lang)) return 'hotels';

    // Weather
    if (_isWeatherIntent(lower, lang)) return 'weather';

    // Events (concerts, museums, spectacles, festivals, etc.)
    if (_isEventIntent(lower, lang)) return 'events';

    // Restaurants
    if (_isRestaurantIntent(lower, lang)) return 'restaurants';

    // Vacation rentals
    if (_isRentalIntent(lower, lang)) return 'rentals';

    // Second-hand / refurbished products
    if (_isSecondHandIntent(lower, lang)) return 'secondhand';

    // Best deal / cheapest across sources
    if (_isBestDealIntent(lower, lang)) return 'bestdeal';

    // Products (check last — broad patterns)
    if (_isProductIntent(lower, lang)) return 'products';

    return 'general';
  }

  // ── Intent detectors ───────────────────────────────────────────────────────

  bool _isFlightIntent(String lower, AppLanguage lang) {
    return _matchAny(lower, lang, _flightKeywords);
  }

  bool _isHotelIntent(String lower, AppLanguage lang) {
    return _matchAny(lower, lang, _hotelKeywords);
  }

  bool _isWeatherIntent(String lower, AppLanguage lang) {
    return _matchAny(lower, lang, _weatherKeywords);
  }

  bool _isProductIntent(String lower, AppLanguage lang) {
    return _matchAny(lower, lang, _productKeywords);
  }

  bool _isEventIntent(String lower, AppLanguage lang) {
    return _matchAny(lower, lang, _eventKeywords);
  }

  bool _isRestaurantIntent(String lower, AppLanguage lang) {
    return _matchAny(lower, lang, _restaurantKeywords);
  }

  bool _isRentalIntent(String lower, AppLanguage lang) {
    return _matchAny(lower, lang, _rentalKeywords);
  }

  bool _isSecondHandIntent(String lower, AppLanguage lang) {
    return _matchAny(lower, lang, _secondHandKeywords);
  }

  bool _isBestDealIntent(String lower, AppLanguage lang) {
    return _matchAny(lower, lang, _bestDealKeywords);
  }

  // ── Parameter Extractors ───────────────────────────────────────────────────

  SearchParams _extractFlightParams(String message, AppLanguage lang, String? priceRange, String? sortBy) {
    final lower = message.toLowerCase();

    // Try known patterns from ChatNotifier's parseFlightParams logic
    var parsed = _tryParseFlightParamsGeneric(message, lang);

    // If lowercase input didn't match, try sanitized + capitalized
    if (parsed == null) {
      final cleaned = _sanitizeFlightQuery(message);
      final capitalized = cleaned.replaceAllMapped(
        RegExp(r'\b([a-zà-ÿ])'),
        (m) => m.group(1)!.toUpperCase(),
      );
      parsed = _tryParseFlightParamsGeneric(capitalized, lang);
    }

    if (parsed != null) {
      return SearchParams(
        intent: 'flights',
        fromLocation: parsed['from'],
        toLocation: parsed['to'],
        departDate: parsed['departDate'],
        returnDate: parsed['returnDate'],
        query: _cleanQuery(message),
        priceRange: priceRange ?? 'cheapest',
        sortBy: sortBy ?? 'price_asc',
      );
    }

    // Fuzzy extraction: find two city names and dates
    final cities = _extractCities(message, lang);
    final dates = _extractDates(message, lang);

    if (cities.length >= 2) {
      return SearchParams(
        intent: 'flights',
        fromLocation: cities[0],
        toLocation: cities[1],
        departDate: dates.isNotEmpty ? dates[0] : null,
        returnDate: dates.length >= 2 ? dates[1] : null,
        query: _cleanQuery(message),
        priceRange: priceRange ?? 'cheapest',
        sortBy: sortBy ?? 'price_asc',
      );
    }

    return SearchParams(intent: 'flights', query: _cleanQuery(message));
  }

  SearchParams _extractHotelParams(String message, AppLanguage lang, String? priceRange, String? sortBy) {
    final location = _extractLocation(message, lang);
    final dates = _extractDates(message, lang);
    final guests = _extractGuests(message);

    return SearchParams(
      intent: 'hotels',
      location: location,
      checkIn: dates.isNotEmpty ? dates[0] : null,
      checkOut: dates.length >= 2 ? dates[1] : null,
      guests: guests,
      query: _cleanQuery(message),
      priceRange: priceRange,
      sortBy: sortBy ?? 'rating',
    );
  }

  SearchParams _extractWeatherParams(String message, AppLanguage lang) {
    final location = _extractLocation(message, lang);
    return SearchParams(
      intent: 'weather',
      location: location,
      query: _cleanQuery(message),
    );
  }

  SearchParams _extractProductParams(String message, AppLanguage lang, String? condition, String? priceRange, String? sortBy) {
    final category = _detectProductCategory(message, lang);
    return SearchParams(
      intent: 'products',
      query: _cleanQuery(message),
      category: category,
      condition: condition,
      priceRange: priceRange ?? 'cheapest',
      sortBy: sortBy ?? 'price_asc',
    );
  }

  SearchParams _extractSecondHandParams(String message, AppLanguage lang, String? priceRange, String? sortBy) {
    final category = _detectProductCategory(message, lang);
    return SearchParams(
      intent: 'secondhand',
      query: _cleanQuery(message),
      category: category,
      condition: 'used',
      priceRange: priceRange ?? 'cheapest',
      sortBy: sortBy ?? 'price_asc',
    );
  }

  SearchParams _extractBestDealParams(String message, AppLanguage lang, String? condition, String? priceRange, String? sortBy) {
    final category = _detectProductCategory(message, lang);
    return SearchParams(
      intent: 'bestdeal',
      query: _cleanQuery(message),
      category: category,
      condition: condition,
      priceRange: priceRange ?? 'cheapest',
      sortBy: sortBy ?? 'price_asc',
    );
  }

  SearchParams _extractEventParams(String message, AppLanguage lang, String? priceRange) {
    final location = _extractLocation(message, lang);
    final domain = _detectEventDomain(message, lang);
    final dates = _extractDates(message, lang);

    return SearchParams(
      intent: 'events',
      domain: domain,
      location: location,
      departDate: dates.isNotEmpty ? dates[0] : null,
      query: _cleanQuery(message),
      priceRange: priceRange,
      sortBy: 'date',
    );
  }

  SearchParams _extractRestaurantParams(String message, AppLanguage lang, String? priceRange, String? sortBy) {
    final location = _extractLocation(message, lang);
    final cuisine = _detectCuisine(message, lang);

    return SearchParams(
      intent: 'restaurants',
      location: location,
      category: cuisine,
      query: _cleanQuery(message),
      priceRange: priceRange,
      sortBy: sortBy ?? 'rating',
    );
  }

  SearchParams _extractRentalParams(String message, AppLanguage lang, String? priceRange, String? sortBy) {
    final location = _extractLocation(message, lang);
    final dates = _extractDates(message, lang);
    final guests = _extractGuests(message);

    return SearchParams(
      intent: 'rentals',
      location: location,
      checkIn: dates.isNotEmpty ? dates[0] : null,
      checkOut: dates.length >= 2 ? dates[1] : null,
      guests: guests,
      query: _cleanQuery(message),
      priceRange: priceRange ?? 'mid',
      sortBy: sortBy ?? 'price_asc',
    );
  }

  // ── Helper: Keyword Matching ───────────────────────────────────────────────

  bool _matchAny(String lower, AppLanguage lang, Map<AppLanguage, List<String>> keywordMap) {
    final patterns = keywordMap[lang] ?? keywordMap[AppLanguage.fr]!;
    return patterns.any((p) => lower.contains(p));
  }

  // ── Helper: City / Location Extraction ─────────────────────────────────────

  String? _extractLocation(String message, AppLanguage lang) {
    final lower = message.toLowerCase();

    // Multi-word location patterns for each language
    final locationPrefixes = {
      AppLanguage.fr: ['à ', 'a ', 'au ', 'en ', 'pour ', 'sur '],
      AppLanguage.en: ['in ', 'to ', 'at ', 'for ', 'near '],
      AppLanguage.es: ['en ', 'a ', 'para ', 'cerca de '],
      AppLanguage.de: ['in ', 'nach ', 'bei ', 'in der nähe von '],
      AppLanguage.it: ['a ', 'in ', 'per ', 'vicino a '],
      AppLanguage.pt: ['em ', 'para ', 'a ', 'perto de '],
    };

    final prefixes = locationPrefixes[lang] ?? locationPrefixes[AppLanguage.fr]!;
    for (final prefix in prefixes) {
      final idx = lower.indexOf(prefix);
      if (idx != -1) {
        final after = lower.substring(idx + prefix.length).trim();
        if (after.length < 50) return after;
        // Take first 2-3 words
        final words = after.split(' ');
        return words.take(words.length > 3 ? 3 : words.length).join(' ');
      }
    }

    // Try to extract city-like words (capitalized after lowercase input)
    final capitalized = message.replaceAllMapped(
      RegExp(r'\b([a-zà-ÿ])'),
      (m) => m.group(1)!.toUpperCase(),
    );
    final cityPattern = RegExp(r'\b([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)*)\b');
    final matches = cityPattern.allMatches(capitalized);
    for (final m in matches) {
      final word = m.group(1)!.toLowerCase();
      // Exclude stop words and known non-location words
      if (!_isStopWord(word) && word.length > 2) {
        return m.group(1);
      }
    }

    return null;
  }

  List<String> _extractCities(String message, AppLanguage lang) {
    final lower = message.toLowerCase();
    final cities = <String>[];

    // Common city name patterns in travel context
    final travelPatterns = [
      RegExp(r'(?:de|depuis|from|da|von|desde|di)\s+([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?)', caseSensitive: false),
      RegExp(r'(?:vers|à|to|pour|a|nach|para|per|direction)\s+([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?)', caseSensitive: false),
      RegExp(r'([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?)\s*-\s*([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?)', caseSensitive: false),
    ];

    for (final pattern in travelPatterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        for (int i = 1; i <= match.groupCount; i++) {
          final city = match.group(i);
          if (city != null && !_isStopWord(city.toLowerCase()) && !cities.contains(city)) {
            cities.add(city);
          }
        }
        if (cities.isNotEmpty) break;
      }
    }

    // Fallback: extract all consecutive capitalized word pairs
    if (cities.isEmpty) {
      final capitalized = message.replaceAllMapped(
        RegExp(r'\b([a-zà-ÿ])'),
        (m) => m.group(1)!.toUpperCase(),
      );
      final allCities = RegExp(r'\b([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s+[A-ZÀ-Ÿ][a-zà-ÿ]+)*)\b').allMatches(capitalized);
      for (final m in allCities) {
        final word = m.group(1)!;
        if (!_isStopWord(word.toLowerCase()) && word.length > 2) {
          cities.add(word);
        }
      }
    }

    return cities;
  }

  // ── Helper: Date Extraction ───────────────────────────────────────────────

  List<String> _extractDates(String message, AppLanguage lang) {
    final dates = <String>[];
    final now = DateTime.now();
    final year = now.year;

    // Numeric dates: dd/mm/yyyy, dd-mm-yyyy, dd.mm.yyyy
    final numDatePattern = RegExp(r'(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{2,4}))?');
    for (final match in numDatePattern.allMatches(message)) {
      final d = int.parse(match.group(1)!);
      final m = int.parse(match.group(2)!);
      final y = match.group(3) != null
          ? (match.group(3)!.length == 2 ? 2000 + int.parse(match.group(3)!) : int.parse(match.group(3)!))
          : year;
      if (d >= 1 && d <= 31 && m >= 1 && m <= 12) {
        dates.add('$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}');
      }
    }

    // Text dates: "29 mai 2026", "May 15th 2026", etc.
    final months = _getMonthPattern(lang);
    final textDatePattern = RegExp(
      '\\b(\\d{1,2})(?:er|eme|ème|st|nd|rd|th)?\\s+($months)(?:\\s+(\\d{2,4}))?\\b',
      caseSensitive: false,
    );
    for (final match in textDatePattern.allMatches(message)) {
      final d = int.parse(match.group(1)!);
      final monthName = match.group(2)!.toLowerCase();
      final m = parseMonth(monthName);
      final y = match.group(3) != null
          ? (match.group(3)!.length == 2 ? 2000 + int.parse(match.group(3)!) : int.parse(match.group(3)!))
          : year;
      if (d >= 1 && d <= 31 && m >= 1 && m <= 12) {
        dates.add('$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}');
      }
    }

    // Relative dates: "demain", "après-demain", "ce weekend", "semaine prochaine"
    if (dates.isEmpty) {
      final relativeDate = _parseRelativeDate(message, lang, now);
      if (relativeDate != null) dates.add(relativeDate);
    }

    return dates;
  }

  String? _parseRelativeDate(String message, AppLanguage lang, DateTime now) {
    final lower = message.toLowerCase();
    final tomorrow = now.add(const Duration(days: 1));
    final nextWeek = now.add(const Duration(days: 7));
    final nextMonth = now.add(const Duration(days: 30));

    final tomorrowPatterns = {
      AppLanguage.fr: ['demain'],
      AppLanguage.en: ['tomorrow'],
      AppLanguage.es: ['mañana', 'manana'],
      AppLanguage.de: ['morgen'],
      AppLanguage.it: ['domani'],
      AppLanguage.pt: ['amanhã', 'amanha'],
    };

    final nextWeekPatterns = {
      AppLanguage.fr: ['semaine prochaine', 'weekend prochain', 'week-end prochain'],
      AppLanguage.en: ['next week', 'next weekend'],
      AppLanguage.es: ['semana que viene', 'próxima semana', 'proxima semana'],
      AppLanguage.de: ['nächste woche', 'nachste woche'],
      AppLanguage.it: ['settimana prossima', 'prossima settimana'],
      AppLanguage.pt: ['semana que vem', 'próxima semana', 'proxima semana'],
    };

    final nextMonthPatterns = {
      AppLanguage.fr: ['mois prochain'],
      AppLanguage.en: ['next month'],
      AppLanguage.es: ['mes que viene', 'próximo mes', 'proximo mes'],
      AppLanguage.de: ['nächsten monat', 'nachsten monat'],
      AppLanguage.it: ['mese prossimo', 'prossimo mese'],
      AppLanguage.pt: ['mês que vem', 'próximo mês', 'proximo mes'],
    };

    final patterns = tomorrowPatterns[lang] ?? tomorrowPatterns[AppLanguage.fr]!;
    if (patterns.any((p) => lower.contains(p))) {
      return '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    }

    final nwPatterns = nextWeekPatterns[lang] ?? nextWeekPatterns[AppLanguage.fr]!;
    if (nwPatterns.any((p) => lower.contains(p))) {
      return '${nextWeek.year}-${nextWeek.month.toString().padLeft(2, '0')}-${nextWeek.day.toString().padLeft(2, '0')}';
    }

    final nmPatterns = nextMonthPatterns[lang] ?? nextMonthPatterns[AppLanguage.fr]!;
    if (nmPatterns.any((p) => lower.contains(p))) {
      return '${nextMonth.year}-${nextMonth.month.toString().padLeft(2, '0')}-${nextMonth.day.toString().padLeft(2, '0')}';
    }

    return null;
  }

  // ── Helper: Condition Detection ────────────────────────────────────────────

  String? _detectCondition(String lower) {
    if (_containsAny(lower, ['occasion', 'seconde main', 'deuxième main', '2ème main', '2eme main',
        'used', 'second hand', 'pre-owned', 'd\'occasion', 'usagé', 'usage', 'se gunda mano',
        'gebraucht', 'usato', 'usado'])) return 'used';
    if (_containsAny(lower, ['reconditionné', 'reconditionne', 'refurbished', 'reacondicionado',
        'generalüberholt', 'ricondizionato', 'recondicionado'])) return 'refurbished';
    if (_containsAny(lower, ['neuf', 'nouveau', 'new', 'nuevo', 'neu', 'nuovo', 'novo'])) return 'new';
    return null;
  }

  // ── Helper: Price Range Detection ──────────────────────────────────────────

  String _detectPriceRange(String lower, AppLanguage lang) {
    if (_matchAny(lower, lang, _cheapestKeywords)) return 'cheapest';
    if (_matchAny(lower, lang, _luxuryKeywords)) return 'luxury';
    if (_matchAny(lower, lang, _budgetKeywords)) return 'budget';
    return 'mid';
  }

  // ── Helper: Sort Preference ────────────────────────────────────────────────

  String? _detectSortPreference(String lower) {
    if (_containsAny(lower, ['moins cher', 'pas cher', 'cheapest', 'prix bas', 'lowest price',
        'más barato', 'billigste', 'più economico', 'mais barato', 'prix croissant',
        'ordre de prix'])) return 'price_asc';
    if (_containsAny(lower, ['mieux noté', 'note', 'rating', 'étoiles', 'stars', 'best rated',
        'top rated', 'meilleur avis', 'review', 'mejor valorado', 'beste bewertung'])) return 'rating';
    if (_containsAny(lower, ['plus proche', 'proximité', 'proche', 'near me', 'distance',
        'cerca', 'près', 'más cercano'])) return 'distance';
    if (_containsAny(lower, ['qualité prix', 'quality price', 'rapport qualité',
        'best value', 'mejor valor', 'meilleur rapport'])) return 'quality_price';
    return null;
  }

  // ── Helper: Product Category Detection ─────────────────────────────────────

  String? _detectProductCategory(String message, AppLanguage lang) {
    final categories = {
      'electronics': ['téléphone', 'telephone', 'phone', 'laptop', 'pc', 'ordinateur', 'computer', 'tablette', 'tablet',
          'écran', 'ecran', 'monitor', 'tv', 'télé', 'tele', 'console', 'casque', 'headphones', 'enceinte', 'speaker'],
      'appliances': ['réfrigérateur', 'refrigerateur', 'frigo', 'fridge', 'lave-linge', 'lave linge', 'washing machine',
          'lave-vaisselle', 'lave vaisselle', 'dishwasher', 'four', 'oven', 'micro-ondes', 'microwave', 'aspirateur', 'vacuum'],
      'furniture': ['canapé', 'canape', 'sofa', 'table', 'chaise', 'chair', 'lit', 'bed', 'bureau', 'desk',
          'armoire', 'wardrobe', 'étagère', 'etagere', 'shelf', 'meuble', 'furniture'],
      'fashion': ['chaussures', 'shoes', 'baskets', 'sneakers', 'vêtement', 'vetement', 'clothes', 'robe', 'dress',
          'manteau', 'coat', 'sac', 'bag', 'montre', 'watch', 'bijou', 'jewelry'],
      'sports': ['vélo', 'velo', 'bike', 'bicycle', 'tapis', 'fitness', 'sport', 'raquette', 'ballon'],
      'books': ['livre', 'book', 'roman', 'bd', 'manga', 'comics'],
    };

    final lower = message.toLowerCase();
    for (final entry in categories.entries) {
      if (entry.value.any((k) => lower.contains(k))) return entry.key;
    }
    return null;
  }

  // ── Helper: Event Domain Detection ─────────────────────────────────────────

  String? _detectEventDomain(String message, AppLanguage lang) {
    final lower = message.toLowerCase();

    if (_matchAny(lower, lang, _concertKeywords)) return 'concerts';
    if (_matchAny(lower, lang, _museumKeywords)) return 'museums';
    if (_matchAny(lower, lang, _festivalKeywords)) return 'festivals';
    if (_matchAny(lower, lang, _theaterKeywords)) return 'theater';
    if (_matchAny(lower, lang, _sportEventKeywords)) return 'sports';
    if (_matchAny(lower, lang, _exhibitionKeywords)) return 'exhibitions';

    return 'events'; // generic
  }

  // ── Helper: Cuisine Detection ──────────────────────────────────────────────

  String? _detectCuisine(String message, AppLanguage lang) {
    final cuisines = {
      'italian': ['italien', 'italienne', 'italian', 'pizza', 'pâtes', 'pates', 'pasta'],
      'french': ['français', 'francaise', 'française', 'french', 'gastronomique', 'bistrot', 'brasserie'],
      'japanese': ['japonais', 'japonaise', 'japanese', 'sushi', 'ramen', 'yakitori'],
      'chinese': ['chinois', 'chinoise', 'chinese', 'cantonnais', 'sichuan'],
      'indian': ['indien', 'indienne', 'indian', 'curry', 'tandoori'],
      'mexican': ['mexicain', 'mexican', 'tacos', 'burrito'],
      'mediterranean': ['méditerranéen', 'mediterraneen', 'mediterranean', 'libanais', 'grec', 'greek', 'turc', 'turkish'],
      'seafood': ['poisson', 'fish', 'fruits de mer', 'seafood', 'crustacés'],
      'vegetarian': ['végétarien', 'vegetarien', 'vegan', 'végan', 'végé', 'vege', 'vegetarian'],
      'streetfood': ['street food', 'streetfood', 'rapide', 'burger', 'kebab', 'fast food'],
    };

    final lower = message.toLowerCase();
    for (final entry in cuisines.entries) {
      if (entry.value.any((k) => lower.contains(k))) return entry.key;
    }
    return null;
  }

  // ── Helper: Guests ─────────────────────────────────────────────────────────

  int? _extractGuests(String message) {
    final patterns = [
      RegExp(r'(\d+)\s*(?:personnes?|people|persone|personas?|pessoas?|gente)', caseSensitive: false),
      RegExp(r'(?:pour|for|per|für|para|por)\s+(\d+)\s*(?:personnes?|people|persone|personas?|pessoas?)?', caseSensitive: false),
    ];

    for (final p in patterns) {
      final match = p.firstMatch(message);
      if (match != null) {
        final n = int.tryParse(match.group(1)!);
        if (n != null && n > 0 && n <= 20) return n;
      }
    }
    return null;
  }

  // ── Helper: Flight Param Parsing (delegates to ChatNotifier logic) ─────────
  // This is a simplified version that works in pure Dart

  static Map<String, String>? _tryParseFlightParamsGeneric(String message, AppLanguage lang) {
    const cityName = r'[A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?';
    const numericDate = r'\d{1,2}[/.-]\d{1,2}(?:[/.-]\d{2,4})?';
    const months =
        r'[Jj]anvier|[Ff]évrier|[Ff]evrier|[Mm]ars|[Aa]vril|[Mm]ai|'
        r'[Jj]uillet|[Jj]uin|[Aa]oût|[Aa]out|[Ss]eptembre|[Oo]ctobre|'
        r'[Nn]ovembre|[Dd]écembre|[Dd]ecembre|'
        r'[Jj]anuary|[Ff]ebruary|[Mm]arch|[Aa]pril|[Mm]ay|'
        r'[Jj]uly|[Jj]une|[Aa]ugust|[Ss]eptember|[Oo]ctober|'
        r'[Nn]ovember|[Dd]ecember|'
        r'[Ee]nero|[Ff]ebrero|[Mm]arzo|[Aa]bril|[Mm]ayo|[Jj]unio|[Jj]ulio|'
        r'[Ss]eptiembre|[Oo]ctubre|[Nn]oviembre|[Dd]iciembre|'
        r'[Jj]anuar|[Ff]ebruar|[Mm]arz|[Jj]uni|[Jj]uli|[Oo]ktober|[Dd]ezember|'
        r'[Gg]ennaio|[Ff]ebbraio|[Mm]aggio|[Gg]iugno|[Ll]uglio|'
        r'[Ss]ettembre|[Oo]ttobre|[Dd]icembre|'
        r'[Jj]aneiro|[Ff]evereiro|[Mm]arco|[Mm]aio|[Jj]unho|[Jj]ulho|'
        r'[Oo]utubro|[Nn]ovembro|[Dd]ezembro';

    // Pattern A: "City1-City2 du DD mois au DD mois"
    final hyphenTextDates = RegExp(
      '($cityName)\\s*-\\s*($cityName)\\b'
      r'.{0,30}?'
      r'(?:d[ue]|le|départ\s+le)\s+(\d{1,2})\s+'
      '($months)'
      r'(?:\s*(?:au|retour(?:\s+le)?)\s+(\d{1,2})\s+(' + months + r'))?',
    );
    final matchA = hyphenTextDates.firstMatch(message);
    if (matchA != null) {
      final d1 = int.parse(matchA.group(3)!);
      final m1 = parseMonth(matchA.group(4)!);
      final y = DateTime.now().year;
      final departDate = '$y-${m1.toString().padLeft(2, '0')}-${d1.toString().padLeft(2, '0')}';
      String? returnDate;
      if (matchA.group(5) != null) {
        final d2 = int.parse(matchA.group(5)!);
        final m2 = parseMonth(matchA.group(6)!);
        returnDate = '$y-${m2.toString().padLeft(2, '0')}-${d2.toString().padLeft(2, '0')}';
      }
      return {'from': matchA.group(1)!.trim(), 'to': matchA.group(2)!.trim(), 'departDate': departDate, if (returnDate != null) 'returnDate': returnDate};
    }

    // Pattern B: "City1-City2 du date1 au date2" (numeric dates)
    final hyphenNumDates = RegExp(
      '($cityName)\\s*-\\s*($cityName)\\b'
      r'.{0,20}?'
      '(?:d[ue]|le)\\s+(' + numericDate + r')'
      r'(?:\s+(?:au|retour)\s+(' + numericDate + r'))?',
    );
    final matchB = hyphenNumDates.firstMatch(message);
    if (matchB != null) {
      return {
        'from': matchB.group(1)!.trim(),
        'to': matchB.group(2)!.trim(),
        'departDate': _normalizeDate(matchB.group(3)!),
        if (matchB.group(4) != null) 'returnDate': _normalizeDate(matchB.group(4)!),
      };
    }

    // Pattern C: "City1 City2 du DD mois au DD mois"
    final spaceTextDates = RegExp(
      '($cityName)\\s+'
      r'(?:à|vers|pour|-)?\s*'
      '($cityName)\\b'
      r'.{0,30}?'
      r'(?:d[ue]|le\s+)?(\d{1,2})\s+'
      '($months)'
      r'(?:\s*(?:au|retour)\s+(\d{1,2})\s+(' + months + r'))?',
    );
    final matchC = spaceTextDates.firstMatch(message);
    if (matchC != null) {
      final d1 = int.parse(matchC.group(3)!);
      final m1 = parseMonth(matchC.group(4)!);
      final y = DateTime.now().year;
      final departDate = '$y-${m1.toString().padLeft(2, '0')}-${d1.toString().padLeft(2, '0')}';
      String? returnDate;
      if (matchC.group(5) != null) {
        final d2 = int.parse(matchC.group(5)!);
        final m2 = parseMonth(matchC.group(6)!);
        returnDate = '$y-${m2.toString().padLeft(2, '0')}-${d2.toString().padLeft(2, '0')}';
      }
      return {'from': matchC.group(1)!.trim(), 'to': matchC.group(2)!.trim(), 'departDate': departDate, if (returnDate != null) 'returnDate': returnDate};
    }

    // Pattern D: "City1-City2 date" or "City1 City2 date" — compact, no du/le required
    final compactNumDates = RegExp(
      '(?:de\\s+)?($cityName)\\s+'
      r'(?:à|vers|pour|-)?\s*'
      '($cityName)\\b'
      r'.{0,20}?'
      '(?:d[ue]|le)?\\s*(' + numericDate + r')',
    );
    final matchD = compactNumDates.firstMatch(message);
    if (matchD != null) {
      return {
        'from': matchD.group(1)!.trim(),
        'to': matchD.group(2)!.trim(),
        'departDate': _normalizeDate(matchD.group(3)!),
      };
    }

    return null;
  }

  static String _normalizeDate(String raw) {
    final parts = raw.replaceAll('-', '/').replaceAll('.', '/').split('/');
    if (parts.length >= 2) {
      var day = parts[0].padLeft(2, '0');
      var month = parts[1].padLeft(2, '0');
      String year;
      if (parts.length >= 3) {
        var y = parts[2];
        if (y.length == 2) y = '20$y';
        year = y;
      } else {
        year = DateTime.now().year.toString();
      }
      return '$year-$month-$day';
    }
    return raw;
  }

  // ── Misc Helpers ───────────────────────────────────────────────────────────

  String _cleanQuery(String message) {
    return message.replaceAll(RegExp(r'[^\w\sà-üÀ-Ü-]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Remove flight-related stop words that interfere with city extraction.
  static String _sanitizeFlightQuery(String msg) {
    const stopWords = [
      'vol', 'vols', 'billet', 'billets', 'avion', 'avions',
      'aller', 'retour', 'direct', 'directs', 'cher', 'chers',
      'moins', 'trouver', 'trouve', 'cherche', 'chercher',
      'recherche', 'rechercher', 'depart', 'arrivee', 'reservation',
      'reserver', 'partir', 'pour', 'via', 'avec', 'sur',
      'flight', 'flights', 'ticket', 'tickets', 'cheap', 'find',
      'search', 'one', 'way', 'round', 'trip', 'from', 'and',
      'pas', 'les', 'des', 'un', 'une', 'mon', 'mes', 'ton', 'tes',
      'son', 'ses', 'notre', 'nos', 'votre', 'vos', 'leur', 'leurs',
      'quel', 'quels', 'quelle', 'quelles', 'est', 'sont',
      'me', 'le', 'la', 'du', 'de', 'au', 'aux',
    ];
    var cleaned = msg;
    for (final w in stopWords) {
      cleaned = cleaned.replaceAll(RegExp('\\b$w\\b', caseSensitive: false), ' ');
    }
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _isStopWord(String word) {
    const stops = {
      // French
      'vol', 'vols', 'billet', 'avion', 'aller', 'retour', 'pas', 'cher', 'chers',
      'moins', 'trouver', 'trouve', 'cherche', 'chercher', 'recherche',
      'direct', 'directs', 'pour', 'dans', 'avec', 'sur', 'sous', 'entre', 'par', 'vers', 'via',
      'le', 'la', 'les', 'des', 'un', 'une', 'du', 'de', 'au', 'aux',
      'mon', 'mes', 'ton', 'tes', 'son', 'ses', 'notre', 'nos', 'ce', 'cette',
      'quel', 'quelle', 'quels', 'quelles', 'est', 'sont', 'être', 'etre',
      'demain', 'après', 'semaine', 'prochaine', 'weekend', 'mois', 'prochain',
      'aujourd', 'hui',
      // English
      'flight', 'flights', 'ticket', 'tickets', 'cheap', 'find', 'search',
      'the', 'an', 'on', 'at', 'to', 'for', 'of', 'from',
      'hôtel', 'hotel',
      // Spanish
      'el', 'las', 'los', 'del', 'en', 'con', 'por',
      // German
      'der', 'die', 'das', 'im', 'am', 'zum', 'bei', 'mit',
      // Italian
      'il', 'lo', 'i', 'gli', 'di', 'su',
      // Portuguese
      'o', 'os', 'as', 'do', 'em', 'no', 'na',
      // Shared — these appear in multiple languages, list only once
      'a', 'in', 'da', 'para',
    };
    return stops.contains(word);
  }

  bool _containsAny(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  String _getMonthPattern(AppLanguage lang) {
    const all = r'[Jj]anvier|[Ff]évrier|[Ff]evrier|[Mm]ars|[Aa]vril|[Mm]ai|[Jj]uin|'
        r'[Jj]uillet|[Aa]oût|[Aa]out|[Ss]eptembre|[Oo]ctobre|[Nn]ovembre|'
        r'[Dd]écembre|[Dd]ecembre|'
        r'[Jj]anuary|[Ff]ebruary|[Mm]arch|[Aa]pril|[Mm]ay|[Jj]une|[Jj]uly|'
        r'[Aa]ugust|[Ss]eptember|[Oo]ctober|[Nn]ovember|[Dd]ecember|'
        r'[Ee]nero|[Ff]ebrero|[Mm]arzo|[Aa]bril|[Mm]ayo|[Jj]unio|[Jj]ulio|'
        r'[Aa]gosto|[Ss]eptiembre|[Oo]ctubre|[Nn]oviembre|[Dd]iciembre|'
        r'[Jj]anuar|[Ff]ebruar|[Mm]arz|[Aa]pril|[Mm]ai|[Jj]uni|[Jj]uli|'
        r'[Aa]ugust|[Ss]eptember|[Oo]ktober|[Nn]ovember|[Dd]ezember|'
        r'[Gg]ennaio|[Ff]ebbraio|[Mm]arzo|[Aa]prile|[Mm]aggio|[Gg]iugno|'
        r'[Ll]uglio|[Aa]gosto|[Ss]ettembre|[Oo]ttobre|[Nn]ovembre|[Dd]icembre|'
        r'[Jj]aneiro|[Ff]evereiro|[Mm]arço|[Mm]arco|[Aa]bril|[Mm]aio|'
        r'[Jj]unho|[Jj]ulho|[Aa]gosto|[Ss]etembro|[Oo]utubro|[Nn]ovembro|[Dd]ezembro';
    return all;
  }

  // ── Multilingual Keyword Maps ──────────────────────────────────────────────

  static const _flightKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['billet', 'vol ', 'vols ', 'avion', 'aller-retour', 'aller retour'],
    AppLanguage.en: ['flight', 'flights', 'plane ticket', 'round trip', 'fly to', 'flying to', 'airfare'],
    AppLanguage.es: ['vuelo', 'vuelos', 'billete', 'boleto', 'avión', 'ida y vuelta', 'volar a'],
    AppLanguage.de: ['flug', 'flüge', 'fluege', 'flugticket', 'hin und rückflug', 'fliegen'],
    AppLanguage.it: ['volo', 'voli', 'biglietto', 'aereo', 'andata e ritorno', 'volare'],
    AppLanguage.pt: ['voo', 'voos', 'passagem', 'bilhete', 'avião', 'ida e volta', 'voar'],
  };

  static const _hotelKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['hotel', 'hôtel', 'airbnb', 'logement', 'booking', 'nuit ', 'séjour', 'sejour', 'hébergement'],
    AppLanguage.en: ['hotel', 'motel', 'airbnb', 'accommodation', 'booking', 'night stay', 'lodging'],
    AppLanguage.es: ['hotel', 'alojamiento', 'airbnb', 'habitación', 'noche', 'estancia'],
    AppLanguage.de: ['hotel', 'unterkunft', 'airbnb', 'übernachtung', 'zimmer', 'aufenthalt'],
    AppLanguage.it: ['hotel', 'alloggio', 'airbnb', 'pernottamento', 'notte', 'soggiorno'],
    AppLanguage.pt: ['hotel', 'hotéis', 'alojamento', 'airbnb', 'quarto', 'noite', 'estadia'],
  };

  static const _weatherKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['météo', 'meteo', 'pleuvoir', 'température', 'temperature', 'quel temps', 'prévisions'],
    AppLanguage.en: ['weather', 'rain', 'temperature', 'forecast', 'will it rain', "what's the weather"],
    AppLanguage.es: ['clima', 'tiempo', 'lluvia', 'temperatura', 'pronóstico', 'va a llover'],
    AppLanguage.de: ['wetter', 'regen', 'temperatur', 'vorhersage', 'wird es regnen'],
    AppLanguage.it: ['meteo', 'tempo', 'pioggia', 'temperatura', 'previsioni', 'che tempo fa'],
    AppLanguage.pt: ['clima', 'tempo', 'chuva', 'temperatura', 'previsão', 'vai chover'],
  };

  static const _productKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['moins cher', 'meilleur prix', 'acheter', 'trouve le', 'trouve moi',
        'cherche le', 'cherche moi', 'prix', 'comparer', 'le moins cher'],
    AppLanguage.en: ['cheapest', 'best price', 'buy', 'purchase', 'find me', 'lowest price',
        'compare prices', 'where to buy', 'on sale', 'deal on'],
    AppLanguage.es: ['más barato', 'mejor precio', 'comprar', 'encuentra', 'precio más bajo'],
    AppLanguage.de: ['günstigste', 'billigste', 'bester preis', 'kaufen', 'finde', 'suche'],
    AppLanguage.it: ['più economico', 'miglior prezzo', 'comprare', 'acquistare', 'trova'],
    AppLanguage.pt: ['mais barato', 'melhor preço', 'comprar', 'encontra', 'procura'],
  };

  static const _eventKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['concert', 'concerts', 'spectacle', 'spectacles', 'festival',
        'exposition', 'expo', 'musée', 'musee', 'théâtre', 'theatre', 'pièce',
        'opéra', 'opera', 'ballet', 'comédie', 'comedie', 'show', 'shows',
        'visite', 'visiter', 'sortir', 'ticket', 'billet concert', 'festival musique',
        'match ', 'match de', 'compétition', 'evenement', 'événement', 'évènement', 'evenement'],
    AppLanguage.en: ['concert', 'concerts', 'show', 'shows', 'festival', 'exhibition',
        'museum', 'theatre', 'theater', 'musical', 'broadway', 'opera', 'ballet',
        'gig', 'live music', 'stand up', 'comedy show', 'sports event', 'match ',
        'game tickets', 'tour', 'event', 'events'],
    AppLanguage.es: ['concierto', 'conciertos', 'espectáculo', 'festival', 'exposición',
        'museo', 'teatro', 'ópera', 'ballet', 'show', 'evento', 'eventos'],
    AppLanguage.de: ['konzert', 'konzerte', 'aufführung', 'festival', 'ausstellung',
        'museum', 'theater', 'oper', 'ballett', 'show', 'veranstaltung'],
    AppLanguage.it: ['concerto', 'concerti', 'spettacolo', 'festival', 'mostra',
        'museo', 'teatro', 'opera', 'balletto', 'spettacoli', 'evento', 'eventi'],
    AppLanguage.pt: ['concerto', 'concertos', 'espetáculo', 'festival', 'exposição',
        'museu', 'teatro', 'ópera', 'espetáculos', 'evento', 'eventos'],
  };

  static const _restaurantKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['restaurant', 'resto', 'restau', 'manger', 'dîner', 'diner',
        'déjeuner', 'dejeuner', 'brasserie', 'bistrot', 'gastronomique', 'buffet',
        'pizzeria', 'sushis', 'kebab', 'cuisine', 'chef', 'étoilé', 'etoile',
        'terrasse', 'brunch', 'déguster'],
    AppLanguage.en: ['restaurant', 'restaurants', 'dining', 'eat', 'dinner', 'lunch',
        'brunch', 'steakhouse', 'sushi', 'pizza', 'food near', 'place to eat',
        'fine dining', 'michelin', 'best food', 'where to eat'],
    AppLanguage.es: ['restaurante', 'comer', 'cena', 'almuerzo', 'comida', 'donde comer'],
    AppLanguage.de: ['restaurant', 'restaurants', 'essen', 'gaststätte', 'imbiss',
        'wo essen', 'speiselokal'],
    AppLanguage.it: ['ristorante', 'ristoranti', 'mangiare', 'cena', 'pranzo', 'dove mangiare'],
    AppLanguage.pt: ['restaurante', 'restaurantes', 'comer', 'jantar', 'almoço', 'onde comer'],
  };

  static const _rentalKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['location vacances', 'location saisonnière', 'maison vacances',
        'appartement vacances', 'villa', 'louer', 'location airbnb', 'gîte', 'gite',
        'chalet', 'camping', 'résidence vacances', 'residence vacances',
        'location appartement', 'séjour vacances'],
    AppLanguage.en: ['vacation rental', 'holiday rental', 'vacation home', 'rent a house',
        'rent an apartment', 'villa rental', 'cabin', 'cottage', 'vacation home',
        'airbnb', 'stay rental', 'holiday home'],
    AppLanguage.es: ['alquiler vacacional', 'casa vacacional', 'alquiler apartamento',
        'villa', 'casa rural'],
    AppLanguage.de: ['ferienwohnung', 'ferienhaus', 'ferienunterkunft', 'mietwohnung'],
    AppLanguage.it: ['affitto vacanze', 'casa vacanze', 'affitto appartamento', 'villa vacanze'],
    AppLanguage.pt: ['aluguer férias', 'casa férias', 'aluguer apartamento', 'villa férias'],
  };

  static const _secondHandKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['occasion', 'seconde main', 'deuxième main', '2eme main',
        'reconditionné', 'reconditionne', 'usagé', 'usage', 'recyclé', 'recycle',
        'ancien modele', 'ancienne version', 'pas neuf', 'bon coin', 'leboncoin',
        'vinted', 'ebay', 'rachat', 'rachète'],
    AppLanguage.en: ['used', 'second hand', 'pre-owned', 'pre owned', 'refurbished',
        'renewed', 'recycled', 'thrift', 'vintage', 'preloved', 'pre loved',
        'old model', 'used item', 'secondhand'],
    AppLanguage.es: ['segunda mano', 'usado', 'reacondicionado', 'ocasión'],
    AppLanguage.de: ['gebraucht', 'second hand', 'generalüberholt', 'gebrauchte'],
    AppLanguage.it: ['usato', 'seconda mano', 'ricondizionato', 'usata'],
    AppLanguage.pt: ['usado', 'segunda mão', 'recondicionado', 'em segunda mão'],
  };

  static const _bestDealKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['meilleur deal', 'meilleure offre', 'bon plan', 'bons plans',
        'promo', 'promotion', 'réduction', 'reduction', 'soldes', 'code promo',
        'le deal du', 'rapport qualité', 'quel est le meilleur', 'meilleur achat',
        'ça vaut le coup', 'vaut il le coup', 'quel est le prix le plus bas',
        'où trouver le moins'],
    AppLanguage.en: ['best deal', 'best offer', 'best value', 'best bang for',
        'promo code', 'discount', 'worth it', 'best buy', 'where to get the best',
        'good deal', 'steal', 'bargain'],
    AppLanguage.es: ['mejor oferta', 'chollo', 'oferta', 'descuento', 'vale la pena'],
    AppLanguage.de: ['bestes angebot', 'schnäppchen', 'angebot', 'rabatt', 'lohnt sich'],
    AppLanguage.it: ['migliore offerta', 'affare', 'offerta', 'sconto', 'conviene'],
    AppLanguage.pt: ['melhor oferta', 'pechincha', 'oferta', 'desconto', 'vale a pena'],
  };

  static const _cheapestKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['moins cher', 'pas cher', 'le moins cher', 'low cost', 'économique',
        'petit prix', 'prix bas', 'bas prix', 'abordable', 'cherche pas cher',
        'bon marché', 'bon marche', 'pas trop cher', 'dans mon budget'],
    AppLanguage.en: ['cheapest', 'cheap', 'low cost', 'budget', 'affordable', 'inexpensive',
        'low price', 'best price', 'lowest price'],
    AppLanguage.es: ['más barato', 'barato', 'económico', 'bajo costo', 'asequible'],
    AppLanguage.de: ['günstigste', 'billigste', 'preiswert', 'erschwinglich'],
    AppLanguage.it: ['più economico', 'economico', 'conveniente', 'a buon mercato'],
    AppLanguage.pt: ['mais barato', 'barato', 'económico', 'acessível', 'preço baixo'],
  };

  static const _luxuryKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['luxe', 'haut de gamme', 'premium', 'prestige', 'grand luxe',
        '5 étoiles', '5 etoiles', 'vip', 'exclusif'],
    AppLanguage.en: ['luxury', 'high end', 'premium', 'prestige', '5 star', 'vip', 'exclusive'],
    AppLanguage.es: ['lujo', 'alta gama', 'premium', 'exclusivo'],
    AppLanguage.de: ['luxus', 'gehoben', 'premium', 'exklusiv'],
    AppLanguage.it: ['lusso', 'alta gamma', 'premium', 'esclusivo'],
    AppLanguage.pt: ['luxo', 'alta gama', 'premium', 'exclusivo'],
  };

  static const _budgetKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['petit budget', 'budget serré', 'économique', 'economique',
        'pas cher', 'abordable'],
    AppLanguage.en: ['budget', 'affordable', 'cheap', 'value', 'economy'],
    AppLanguage.es: ['presupuesto', 'económico'],
    AppLanguage.de: ['budget', 'preiswert', 'günstig'],
    AppLanguage.it: ['budget', 'economico'],
    AppLanguage.pt: ['orçamento', 'econômico'],
  };

  static const _concertKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['concert', 'concert', 'festival musique', 'festival de musique',
        'groupe', 'chanteur', 'chanteuse', 'tournée', 'tournee', 'live', 'zenith',
        'aréna', 'arena', 'stade concert', 'salle de concert', 'billetterie concert'],
    AppLanguage.en: ['concert', 'live music', 'band', 'singer', 'tour', 'arena', 'venue'],
    AppLanguage.es: ['concierto', 'música en vivo', 'gira', 'banda', 'cantante'],
    AppLanguage.de: ['konzert', 'live musik', 'band', 'sänger', 'tournee'],
    AppLanguage.it: ['concerto', 'musica dal vivo', 'tour', 'band'],
    AppLanguage.pt: ['concerto', 'música ao vivo', 'tour', 'banda'],
  };

  static const _museumKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['musée', 'musee', 'exposition', 'expo', 'galerie', 'art contemporain',
        'beaux arts', 'collection', 'rétrospective', 'retrospective', 'vernissage'],
    AppLanguage.en: ['museum', 'exhibition', 'gallery', 'art show', 'retrospective', 'collection'],
    AppLanguage.es: ['museo', 'exposición', 'galería', 'arte'],
    AppLanguage.de: ['museum', 'ausstellung', 'galerie', 'kunst'],
    AppLanguage.it: ['museo', 'mostra', 'galleria', 'arte'],
    AppLanguage.pt: ['museu', 'exposição', 'galeria', 'arte'],
  };

  static const _festivalKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['festival', 'festival de', 'salon', 'foire', 'carnaval',
        'fête de', 'fete de', 'kermesse', 'fest-noz', 'fest noz'],
    AppLanguage.en: ['festival', 'fair', 'carnival', 'fest', 'fete'],
    AppLanguage.es: ['festival', 'feria', 'carnaval', 'fiesta'],
    AppLanguage.de: ['festival', 'fest', 'messe', 'karneval'],
    AppLanguage.it: ['festival', 'fiera', 'carnevale', 'sagra'],
    AppLanguage.pt: ['festival', 'feira', 'carnaval', 'festa'],
  };

  static const _theaterKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['théâtre', 'theatre', 'pièce', 'piece', 'comédie musicale',
        'comedie musicale', 'ballet', 'opéra', 'opera', 'spectacle vivant',
        'marionnettes', 'one man show', 'humoriste', 'humour'],
    AppLanguage.en: ['theatre', 'theater', 'play', 'musical', 'ballet', 'opera',
        'comedy show', 'stand up'],
    AppLanguage.es: ['teatro', 'obra', 'musical', 'ballet', 'ópera'],
    AppLanguage.de: ['theater', 'stück', 'musical', 'ballett', 'oper'],
    AppLanguage.it: ['teatro', 'commedia', 'musical', 'balletto', 'opera'],
    AppLanguage.pt: ['teatro', 'peça', 'musical', 'espetáculo', 'ópera'],
  };

  static const _sportEventKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['match ', 'match de', 'compétition', 'competition', 'tournoi',
        'championnat', 'finale', 'grand prix', 'formule 1', 'f1', 'coupe du monde',
        'euro ', 'jo ', 'jeux olympiques', 'olympique', 'stade'],
    AppLanguage.en: ['match ', 'game ', 'tournament', 'championship', 'final',
        'grand prix', 'formula 1', 'world cup', 'olympics', 'stadium'],
    AppLanguage.es: ['partido', 'torneo', 'campeonato', 'final', 'gran premio'],
    AppLanguage.de: ['spiel', 'turnier', 'meisterschaft', 'finale'],
    AppLanguage.it: ['partita', 'torneo', 'campionato', 'finale', 'gran premio'],
    AppLanguage.pt: ['jogo', 'torneio', 'campeonato', 'final', 'grande prémio'],
  };

  static const _exhibitionKeywords = <AppLanguage, List<String>>{
    AppLanguage.fr: ['exposition', 'expo', 'foire', 'salon', 'biennale', 'triennale',
        'installation', 'vernissage', 'art contemporain'],
    AppLanguage.en: ['exhibition', 'expo', 'art fair', 'biennale', 'installation'],
    AppLanguage.es: ['exposición', 'feria de arte', 'bienal'],
    AppLanguage.de: ['ausstellung', 'kunstmesse', 'biennale'],
    AppLanguage.it: ['mostra', 'esposizione', 'biennale'],
    AppLanguage.pt: ['exposição', 'feira de arte', 'bienal'],
  };
}
