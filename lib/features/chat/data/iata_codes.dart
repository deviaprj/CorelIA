/// IATA airport/city codes for flight search optimization.
/// Comparators (Skyscanner, Kayak, Google Flights) resolve IATA codes
/// more reliably than city names.
///
/// Data: ~300 major airports worldwide + fuzzy matching for city names.

const _iataByCity = <String, String>{
  // Europe — France
  'paris': 'PAR', 'paris cdg': 'CDG', 'paris orly': 'ORY', 'paris beauvais': 'BVA',
  'marseille': 'MRS', 'lyon': 'LYS', 'nice': 'NCE', 'toulouse': 'TLS',
  'bordeaux': 'BOD', 'nantes': 'NTE', 'lille': 'LIL', 'strasbourg': 'SXB',
  'montpellier': 'MPL', 'bastia': 'BIA', 'ajaccio': 'AJA', 'biarritz': 'BIQ',
  'brest': 'BES', 'grenoble': 'GNB', 'perpignan': 'PGF', 'rennes': 'RNS',
  'toulon': 'TLN', 'pau': 'PUF', 'carcassonne': 'CCF', 'beauvais': 'BVA',
  'chambery': 'CMF', 'deauville': 'DOL', 'la rochelle': 'LRH', 'limoges': 'LIG',
  'metz': 'ETZ', 'nimes': 'FNI', 'poitiers': 'PIS', 'rodez': 'RDZ',
  'saint etienne': 'EBU', 'tarbes': 'LDE', 'tours': 'TUF', 'calvi': 'CLY',
  'figari': 'FSC', 'lourdes': 'LDE', 'clermont ferrand': 'CFE', 'clermont': 'CFE',

  // Europe — UK
  'london': 'LON', 'londres': 'LON', 'london heathrow': 'LHR', 'heathrow': 'LHR',
  'london gatwick': 'LGW', 'gatwick': 'LGW', 'london stansted': 'STN',
  'london luton': 'LTN', 'london city': 'LCY', 'manchester': 'MAN',
  'edinburgh': 'EDI', 'edimbourg': 'EDI', 'birmingham': 'BHX', 'glasgow': 'GLA',
  'bristol': 'BRS', 'liverpool': 'LPL', 'newcastle': 'NCL', 'leeds': 'LBA',
  'nottingham': 'EMA', 'belfast': 'BFS', 'cardiff': 'CWL', 'southampton': 'SOU',

  // Europe — Germany
  'berlin': 'BER', 'frankfurt': 'FRA', 'munich': 'MUC', 'munchen': 'MUC',
  'hamburg': 'HAM', 'hambourg': 'HAM', 'cologne': 'CGN', 'koln': 'CGN',
  'dusseldorf': 'DUS', 'stuttgart': 'STR', 'hannover': 'HAJ', 'hanovre': 'HAJ',
  'nuremberg': 'NUE', 'nurnberg': 'NUE', 'leipzig': 'LEJ', 'bremen': 'BRE',
  'dresden': 'DRS', 'dresde': 'DRS', 'dortmund': 'DTM', 'baden baden': 'FKB',

  // Europe — Italy
  'rome': 'ROM', 'roma': 'ROM', 'rome fiumicino': 'FCO', 'rome ciampino': 'CIA',
  'milan': 'MIL', 'milano': 'MIL', 'milan malpensa': 'MXP', 'milan bergamo': 'BGY',
  'milan linate': 'LIN', 'venice': 'VCE', 'venezia': 'VCE', 'venise': 'VCE',
  'naples': 'NAP', 'napoli': 'NAP', 'florence': 'FLR', 'firenze': 'FLR',
  'bologna': 'BLQ', 'bologne': 'BLQ', 'turin': 'TRN', 'torino': 'TRN',
  'palermo': 'PMO', 'palerme': 'PMO', 'catania': 'CTA', 'catane': 'CTA',
  'bari': 'BRI', 'cagliari': 'CAG', 'genoa': 'GOA', 'genes': 'GOA', 'genova': 'GOA',
  'pisa': 'PSA', 'verona': 'VRN', 'verone': 'VRN', 'olbia': 'OLB', 'brindisi': 'BDS',
  'lamezia': 'SUF', 'ancona': 'AOI', 'trieste': 'TRS', 'alghero': 'AHO',

  // Europe — Spain
  'madrid': 'MAD', 'barcelona': 'BCN', 'barcelone': 'BCN', 'palma': 'PMI',
  'palma de mallorca': 'PMI', 'malaga': 'AGP', 'alicante': 'ALC',
  'valencia': 'VLC', 'valence': 'VLC', 'sevilla': 'SVQ', 'seville': 'SVQ',
  'bilbao': 'BIO', 'ibiza': 'IBZ', 'menorca': 'MAH', 'granada': 'GRX',
  'gran canaria': 'LPA', 'las palmas': 'LPA', 'tenerife': 'TFS',
  'tenerife north': 'TFN', 'fuerteventura': 'FUE', 'lanzarote': 'ACE',
  'santiago compostela': 'SCQ', 'saint jacques compostelle': 'SCQ',
  'girona': 'GRO', 'gerone': 'GRO', 'reus': 'REU', 'murcia': 'RMU',
  'santander': 'SDR', 'vigo': 'VGO', 'zaragoza': 'ZAZ', 'saragosse': 'ZAZ',
  'asturias': 'OVD', 'oviedo': 'OVD', 'jerez': 'XRY', 'almeria': 'LEI',

  // Europe — Portugal
  'lisbon': 'LIS', 'lisboa': 'LIS', 'lisbonne': 'LIS', 'porto': 'OPO',
  'faro': 'FAO', 'funchal': 'FNC', 'madeira': 'FNC', 'madere': 'FNC',
  'ponta delgada': 'PDL', 'porto santo': 'PXO', 'terceira': 'TER',

  // Europe — Netherlands
  'amsterdam': 'AMS', 'eindhoven': 'EIN', 'rotterdam': 'RTM',
  'la haye': 'RTM', 'den haag': 'RTM', 'groningen': 'GRQ', 'maastricht': 'MST',

  // Europe — Belgium
  'brussels': 'BRU', 'bruxelles': 'BRU', 'brussel': 'BRU',
  'charleroi': 'CRL', 'antwerp': 'ANR', 'anvers': 'ANR', 'liege': 'LGG',
  'ostend': 'OST', 'ostende': 'OST',

  // Europe — Switzerland
  'zurich': 'ZRH', 'geneva': 'GVA', 'geneve': 'GVA', 'genève': 'GVA',
  'basel': 'BSL', 'bale': 'BSL', 'bâle': 'BSL', 'bern': 'BRN', 'berne': 'BRN',

  // Europe — Austria
  'vienna': 'VIE', 'vienne': 'VIE', 'salzburg': 'SZG', 'salzbourg': 'SZG',
  'innsbruck': 'INN', 'graz': 'GRZ', 'linz': 'LNZ',

  // Europe — Poland
  'warsaw': 'WAW', 'warszawa': 'WAW', 'varsovie': 'WAW', 'krakow': 'KRK',
  'krakowia': 'KRK', 'cracovie': 'KRK', 'gdansk': 'GDN',
  'wroclaw': 'WRO', 'poznan': 'POZ', 'katowice': 'KTW',

  // Europe — Czech Republic
  'prague': 'PRG', 'praha': 'PRG', 'brno': 'BRQ',

  // Europe — Hungary
  'budapest': 'BUD', 'debrecen': 'DEB',

  // Europe — Romania
  'bucharest': 'OTP', 'bucuresti': 'OTP', 'bucarest': 'OTP',
  'cluj': 'CLJ', 'timisoara': 'TSR', 'iasi': 'IAS',

  // Europe — Bulgaria
  'sofia': 'SOF', 'varna': 'VAR', 'burgas': 'BOJ',

  // Europe — Croatia
  'zagreb': 'ZAG', 'split': 'SPU', 'dubrovnik': 'DBV', 'zadar': 'ZAD',
  'pula': 'PUY', 'rijeka': 'RJK',

  // Europe — Serbia
  'belgrade': 'BEG', 'beograd': 'BEG', 'nis': 'INI',

  // Europe — Greece
  'athens': 'ATH', 'athenes': 'ATH', 'athina': 'ATH', 'thessaloniki': 'SKG',
  'salonique': 'SKG', 'heraklion': 'HER', 'crete': 'HER', 'crete heraklion': 'HER',
  'rhodes': 'RHO', 'rhodos': 'RHO', 'kos': 'KGS', 'corfu': 'CFU', 'corfou': 'CFU',
  'mykonos': 'JMK', 'santorini': 'JTR', 'santorin': 'JTR', 'zakynthos': 'ZTH',
  'chania': 'CHQ', 'kefalonia': 'EFL', 'preveza': 'PVK', 'skiathos': 'JSI',

  // Europe — Ireland
  'dublin': 'DUB', 'cork': 'ORK', 'shannon': 'SNN', 'knock': 'NOC',

  // Europe — Nordic
  'stockholm': 'STO', 'copenhagen': 'CPH', 'copenhague': 'CPH',
  'oslo': 'OSL', 'helsinki': 'HEL', 'reykjavik': 'KEF',
  'gothenburg': 'GOT', 'goteborg': 'GOT', 'malmo': 'MMX',
  'bergen': 'BGO', 'stavanger': 'SVG', 'trondheim': 'TRD',
  'aarhus': 'AAR', 'billund': 'BLL', 'tampere': 'TMP', 'turku': 'TKU',

  // Europe — Baltic
  'tallinn': 'TLL', 'riga': 'RIX', 'vilnius': 'VNO', 'kaunas': 'KUN',

  // Europe — Ukraine / Moldova
  'kyiv': 'IEV', 'kiev': 'IEV', 'lviv': 'LWO', 'chisinau': 'RMO',

  // Europe — Other
  'luxembourg': 'LUX', 'malta': 'MLA', 'la valette': 'MLA', 'valletta': 'MLA',
  'ljubljana': 'LJU', 'bratislava': 'BTS', 'sarajevo': 'SJJ',
  'skopje': 'SKP', 'tirana': 'TIA', 'podgorica': 'TGD', 'pristina': 'PRN',

  // Europe — Turkey
  'istanbul': 'IST', 'istanbul sabiha': 'SAW', 'antalya': 'AYT', 'ankara': 'ESB',
  'izmir': 'ADB', 'bodrum': 'BJV', 'dalaman': 'DLM',

  // Russia
  'moscow': 'MOW', 'moscou': 'MOW', 'moscow sheremetyevo': 'SVO',
  'moscow domodedovo': 'DME', 'moscow vnukovo': 'VKO',
  'saint petersburg': 'LED', 'saint petersbourg': 'LED', 'pulkovo': 'LED',
  'sochi': 'AER', 'kazan': 'KZN', 'novosibirsk': 'OVB', 'ekaterinburg': 'SVX',

  // North Africa
  'marrakech': 'RAK', 'marrakesh': 'RAK', 'casablanca': 'CMN', 'agadir': 'AGA',
  'fes': 'FEZ', 'fès': 'FEZ', 'tanger': 'TNG', 'tangier': 'TNG', 'rabat': 'RBA',
  'tunis': 'TUN', 'carthage': 'TUN', 'djerba': 'DJE', 'monastir': 'MIR',
  'alger': 'ALG', 'algiers': 'ALG', 'oran': 'ORN', 'constantine': 'CZL',
  'cairo': 'CAI', 'le caire': 'CAI', 'hurghada': 'HRG', 'sharm el sheikh': 'SSH',
  'alexandria': 'HBE', 'alexandrie': 'HBE', 'luxor': 'LXR', 'louxor': 'LXR',

  // Middle East
  'dubai': 'DXB', 'dubai al maktoum': 'DWC', 'abu dhabi': 'AUH',
  'doha': 'DOH', 'riyad': 'RUH', 'riyadh': 'RUH', 'jeddah': 'JED',
  'tel aviv': 'TLV', 'amman': 'AMM', 'beirut': 'BEY', 'beyrouth': 'BEY',
  'kuwait': 'KWI', 'muscat': 'MCT', 'mascate': 'MCT', 'bahrain': 'BAH',
  'baghdad': 'BGW', 'bagdad': 'BGW', 'tehran': 'IKA', 'teheran': 'IKA',

  // Asia
  'bangkok': 'BKK', 'singapore': 'SIN', 'singapour': 'SIN',
  'kuala lumpur': 'KUL', 'jAKARTA': 'JKT', 'manila': 'MNL', 'manille': 'MNL',
  'hanoi': 'HAN', 'ho chi minh': 'SGN', 'saigon': 'SGN',
  'phnom penh': 'PNH', 'yangon': 'RGN', 'rangoon': 'RGN',

  // East Asia
  'tokyo': 'TYO', 'tokyo narita': 'NRT', 'tokyo haneda': 'HND',
  'osaka': 'OSA', 'osaka kansai': 'KIX', 'osaka itami': 'ITM',
  'seoul': 'SEL', 'seoul incheon': 'ICN', 'seoul gimpo': 'GMP',
  'beijing': 'BJS', 'pekin': 'BJS', 'beijing capital': 'PEK',
  'beijing daxing': 'PKX', 'shanghai': 'SHA', 'shanghai pudong': 'PVG',
  'shanghai hongqiao': 'SHA', 'guangzhou': 'CAN', 'canton': 'CAN',
  'shenzhen': 'SZX', 'chengdu': 'CTU', 'hangzhou': 'HGH', 'nanjing': 'NKG',
  'xi an': 'XIY', 'xian': 'XIY', 'chongqing': 'CKG', 'kunming': 'KMG',
  'hong kong': 'HKG', 'taipei': 'TPE', 'taibei': 'TPE', 'taiwan': 'TPE',

  // South Asia
  'delhi': 'DEL', 'new delhi': 'DEL', 'mumbai': 'BOM', 'bombay': 'BOM',
  'bengaluru': 'BLR', 'bangalore': 'BLR', 'chennai': 'MAA', 'madras': 'MAA',
  'kolkata': 'CCU', 'calcutta': 'CCU', 'hyderabad': 'HYD', 'goa': 'GOI',
  'kochi': 'COK', 'cochin': 'COK', 'ahmedabad': 'AMD', 'pune': 'PNQ',
  'jaipur': 'JAI', 'lucknow': 'LKO', 'amritsar': 'ATQ', 'guwahati': 'GAU',
  'colombo': 'CMB', 'male': 'MLE', 'dhaka': 'DAC', 'kathmandu': 'KTM',

  // North America — USA
  'new york': 'NYC', 'new york jfk': 'JFK', 'new york newark': 'EWR',
  'new york laguardia': 'LGA', 'los angeles': 'LAX', 'chicago': 'CHI',
  'chicago ohare': 'ORD', 'chicago midway': 'MDW', 'san francisco': 'SFO',
  'miami': 'MIA', 'las vegas': 'LAS', 'orlando': 'MCO', 'boston': 'BOS',
  'washington': 'WAS', 'washington dc': 'WAS', 'washington dulles': 'IAD',
  'washington reagan': 'DCA', 'seattle': 'SEA', 'dallas': 'DFW',
  'houston': 'HOU', 'houston intercontinental': 'IAH', 'atlanta': 'ATL',
  'philadelphia': 'PHL', 'phoenix': 'PHX', 'denver': 'DEN', 'san diego': 'SAN',
  'minneapolis': 'MSP', 'detroit': 'DTW', 'portland': 'PDX', 'tampa': 'TPA',
  'honolulu': 'HNL', 'austin': 'AUS', 'charlotte': 'CLT', 'nashville': 'BNA',
  'salt lake city': 'SLC', 'raleigh': 'RDU', 'pittsburgh': 'PIT', 'sacramento': 'SMF',
  'fort lauderdale': 'FLL', 'new orleans': 'MSY', 'san jose': 'SJC', 'kansas city': 'MCI',
  'san antonio': 'SAT', 'columbus': 'CMH', 'indianapolis': 'IND', 'cleveland': 'CLE',
  'cincinnati': 'CVG', 'milwaukee': 'MKE', 'anchorage': 'ANC',

  // North America — Canada
  'toronto': 'YTO', 'toronto pearson': 'YYZ', 'toronto billy bishop': 'YTZ',
  'montreal': 'YMQ', 'montréal': 'YMQ', 'montreal trudeau': 'YUL',
  'vancouver': 'YVR', 'calgary': 'YYC', 'ottawa': 'YOW', 'edmonton': 'YEA',
  'quebec': 'YQB', 'québec': 'YQB', 'halifax': 'YHZ', 'winnipeg': 'YWG',

  // Latin America — Mexico
  'mexico city': 'MEX', 'mexico': 'MEX', 'cancun': 'CUN', 'guadalajara': 'GDL',
  'monterrey': 'MTY', 'tijuana': 'TIJ', 'puerto vallarta': 'PVR',
  'los cabos': 'SJD', 'san jose del cabo': 'SJD', 'cabo san lucas': 'SJD',

  // Latin America — Brazil
  'rio de janeiro': 'RIO', 'rio': 'RIO', 'sao paulo': 'SAO', 'são paulo': 'SAO',
  'sao paulo guarulhos': 'GRU', 'sao paulo congonhas': 'CGH',
  'brasilia': 'BSB', 'salvador': 'SSA', 'fortaleza': 'FOR', 'recife': 'REC',
  'belo horizonte': 'CNF', 'curitiba': 'CWB', 'manaus': 'MAO', 'porto alegre': 'POA',
  'florianopolis': 'FLN', 'natal': 'NAT', 'vitoria': 'VIX', 'belem': 'BEL',

  // Latin America — Argentina
  'buenos aires': 'BUE', 'buenos aires ezeiza': 'EZE',
  'buenos aires aeroparque': 'AEP', 'cordoba': 'COR', 'mendoza': 'MDZ',

  // Latin America — Other
  'bogota': 'BOG', 'medellin': 'MDE', 'cali': 'CLO', 'cartagena': 'CTG',
  'santiago': 'SCL', 'lima': 'LIM', 'quito': 'UIO', 'guayaquil': 'GYE',
  'caracas': 'CCS', 'montevideo': 'MVD', 'asuncion': 'ASU',
  'la paz': 'LPB', 'panama city': 'PTY', 'san jose costa rica': 'SJO', 'san josé': 'SJO',
  'santo domingo': 'SDQ', 'havana': 'HAV', 'la havane': 'HAV', 'santa cruz': 'VVI',

  // Africa
  'lagos': 'LOS', 'nairobi': 'NBO', 'addis ababa': 'ADD', 'addis abeba': 'ADD',
  'abidjan': 'ABJ', 'dakar': 'DSS', 'accra': 'ACC', 'lome': 'LFW',
  'cotonou': 'COO', 'bamako': 'BKO', 'niamey': 'NIM', 'ouagadougou': 'OUA',
  'n djamena': 'NDJ', 'yaounde': 'NSI', 'douala': 'DLA', 'libreville': 'LBV',
  'kinshasa': 'FIH', 'brazzaville': 'BZV', 'luanda': 'LAD', 'maputo': 'MPM',

  // Oceania
  'sydney': 'SYD', 'melbourne': 'MEL', 'brisbane': 'BNE', 'perth': 'PER',
  'adelaide': 'ADL', 'gold coast': 'OOL', 'auckland': 'AKL', 'christchurch': 'CHC',
  'wellington': 'WLG', 'queenstown': 'ZQN', 'fiji': 'NAN', 'nadi': 'NAN',
  'papeete': 'PPT', 'tahiti': 'PPT', 'noumea': 'NOU', 'nouméa': 'NOU',
};

/// Resolve a city name to its IATA code.
/// Returns null if no mapping found.
String? resolveIataCode(String cityName) {
  // Direct lookup (lowercased and trimmed)
  final key = cityName.toLowerCase().trim();
  // Entrée vide / whitespace → pas de résolution. Sans cette garde, le fuzzy
  // `contains("")` matche TOUTES les villes (toute chaîne contient "") et
  // retourne la première entrée de la map ('paris' → 'PAR').
  if (key.isEmpty) return null;
  final direct = _iataByCity[key];
  if (direct != null) return direct;

  // Try without accents
  final unaccented = key
      .replaceAll('é', 'e').replaceAll('è', 'e').replaceAll('ê', 'e')
      .replaceAll('à', 'a').replaceAll('â', 'a')
      .replaceAll('ô', 'o').replaceAll('ö', 'o')
      .replaceAll('î', 'i').replaceAll('ï', 'i')
      .replaceAll('û', 'u').replaceAll('ü', 'u')
      .replaceAll('ç', 'c').replaceAll('ñ', 'n');
  if (unaccented != key) {
    final unaccentedResult = _iataByCity[unaccented];
    if (unaccentedResult != null) return unaccentedResult;
  }

  // Fuzzy: check partial match (city name contains the lookup key or vice versa).
  // Garde anti-bruit : on ne fuzzy-match qu'à partir de 3 chars. Une clé trop
  // courte (ex. 'ab') matche la première ville contenant ce substring (ex.
  // 'istanbul sabiha' contient 'ab' → 'SAW'), ce qui est du bruit, pas une
  // résolution légitime. Les codes IATA (3 lettres) et saisies partielles
  // (>= 3 chars) restent couverts.
  if (key.length >= 3) {
    for (final entry in _iataByCity.entries) {
      if (entry.key.contains(key) || key.contains(entry.key)) {
        return entry.value;
      }
    }
  }

  // Multi-word input: try each word individually against known cities
  final words = key.split(' ').where((w) => w.length > 2);
  for (final word in words) {
    // Direct lookup per word
    final wordResult = _iataByCity[word];
    if (wordResult != null) return wordResult;

    // Fuzzy per word
    for (final entry in _iataByCity.entries) {
      if (entry.key.contains(word) || word.contains(entry.key)) {
        return entry.value;
      }
    }

    // Prefix matching: if input word shares 5+ leading chars with a known city
    if (word.length >= 5) {
      for (final entry in _iataByCity.entries) {
        if (entry.key.length >= 5) {
          final prefix = word.length < entry.key.length
              ? word.substring(0, 5)
              : entry.key.substring(0, 5);
          if (word.startsWith(prefix) && entry.key.startsWith(prefix)) {
            return entry.value;
          }
        }
      }
    }
  }

  return null;
}

/// Returns true if we have an IATA code for this city.
bool hasIataCode(String cityName) => resolveIataCode(cityName) != null;

/// Get the best searchable city/IATA tuple for comparators.
/// Returns the IATA code if available, otherwise the original name.
String toSearchableAirport(String cityName) {
  return resolveIataCode(cityName) ?? cityName;
}
