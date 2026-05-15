import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported languages.
enum AppLanguage {
  fr('Français', 'fr', 'fr', 'fr', 'fr-FR'),
  en('English', 'en', 'en', 'us', 'en-US'),
  es('Español', 'es', 'es', 'es', 'es-ES'),
  de('Deutsch', 'de', 'de', 'de', 'de-DE'),
  it('Italiano', 'it', 'it', 'it', 'it-IT'),
  pt('Português', 'pt', 'pt', 'pt', 'pt-PT');

  const AppLanguage(
    this.displayName,
    this.owmLang,
    this.serpApiHl,
    this.serpApiGl,
    this.voiceCode,
  );

  final String displayName;
  final String owmLang;    // OpenWeatherMap lang param
  final String serpApiHl;  // SerpAPI hl (host language)
  final String serpApiGl;  // SerpAPI gl (country)
  final String voiceCode;  // BCP-47 code for STT/TTS
}

// ── Provider ───────────────────────────────────────────────────────────────

final languageProvider =
    StateNotifierProvider<LanguageNotifier, AppLanguage>(
  (ref) => LanguageNotifier(),
);

class LanguageNotifier extends StateNotifier<AppLanguage> {
  LanguageNotifier() : super(AppLanguage.fr) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('corely_language');
    if (stored != null) {
      final lang = AppLanguage.values.where((l) => l.name == stored);
      if (lang.isNotEmpty) state = lang.first;
    } else {
      // Auto-detect from platform locale
      final platformLocale = PlatformDispatcher.instance.locale;
      final code = platformLocale.languageCode;
      final lang = AppLanguage.values.where((l) => l.name == code);
      if (lang.isNotEmpty) state = lang.first;
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('corely_language', language.name);
  }
}

// ── Multilingual intent classification ────────────────────────────────────

/// Returns true if the message (in any supported language) is asking about
/// weather/rain/temperature.
bool isWeatherIntent(String message, AppLanguage lang) {
  final lower = message.toLowerCase();
  final patterns = _weatherPatterns[lang] ?? _weatherPatterns[AppLanguage.en]!;
  return patterns.any((p) => lower.contains(p));
}

/// Returns true if the message is asking about flights/travel.
bool isFlightIntent(String message, AppLanguage lang) {
  final lower = message.toLowerCase();
  final patterns =
      _flightPatterns[lang] ?? _flightPatterns[AppLanguage.en]!;
  return patterns.any((p) => lower.contains(p));
}

/// Returns true if the message is asking about hotels/accommodation.
bool isHotelIntent(String message, AppLanguage lang) {
  final lower = message.toLowerCase();
  final patterns = _hotelPatterns[lang] ?? _hotelPatterns[AppLanguage.en]!;
  return patterns.any((p) => lower.contains(p));
}

/// Returns true if the message is asking about product prices/shopping.
bool isProductIntent(String message, AppLanguage lang) {
  final lower = message.toLowerCase();
  final patterns =
      _productPatterns[lang] ?? _productPatterns[AppLanguage.en]!;
  return patterns.any((p) => lower.contains(p));
}

/// Classify search intent: 'weather', 'flights', 'hotels', 'products', 'general'.
String classifySearchIntent(String message, AppLanguage lang) {
  final lower = message.toLowerCase();

  // Weather (check first — most specific)
  final wp = _weatherPatterns[lang] ?? _weatherPatterns[AppLanguage.en]!;
  if (wp.any((p) => lower.contains(p))) return 'weather';

  // Flights
  final fp = _flightPatterns[lang] ?? _flightPatterns[AppLanguage.en]!;
  if (fp.any((p) => lower.contains(p))) return 'flights';

  // Hotels
  final hp = _hotelPatterns[lang] ?? _hotelPatterns[AppLanguage.en]!;
  if (hp.any((p) => lower.contains(p))) return 'hotels';

  // Products
  final pp = _productPatterns[lang] ?? _productPatterns[AppLanguage.en]!;
  if (pp.any((p) => lower.contains(p))) return 'products';

  return 'general';
}

// ── Pattern maps ─────────────────────────────────────────────────────────

const _weatherPatterns = <AppLanguage, List<String>>{
  AppLanguage.fr: [
    'météo', 'meteo', 'pleuvoir', 'température', 'temperature',
    'quel temps', 'pluie', 'temps fait', 'prévisions', 'previsions',
  ],
  AppLanguage.en: [
    'weather', 'rain', 'temperature', 'forecast', 'will it rain',
    'is it raining', "what's the weather", 'how hot', 'how cold',
    'do i need an umbrella', 'gonna rain',
  ],
  AppLanguage.es: [
    'clima', 'tiempo', 'lluvia', 'llover', 'temperatura',
    'pronóstico', 'va a llover', 'qué tiempo',
  ],
  AppLanguage.de: [
    'wetter', 'regen', 'temperatur', 'vorhersage', 'wird es regnen',
    'wie ist das wetter',
  ],
  AppLanguage.it: [
    'meteo', 'tempo', 'pioggia', 'piovere', 'temperatura',
    'previsioni', 'che tempo fa', 'pioverà',
  ],
  AppLanguage.pt: [
    'clima', 'tempo', 'chuva', 'chover', 'temperatura',
    'previsão', 'vai chover', 'que tempo faz',
  ],
};

const _flightPatterns = <AppLanguage, List<String>>{
  AppLanguage.fr: [
    'billet', 'vol ', 'vols ', 'avion', 'aller-retour', 'aller retour',
  ],
  AppLanguage.en: [
    'flight', 'flights', 'plane', 'ticket', 'round trip',
    'one way', 'direct flight', 'fly to', 'flying to', 'airfare',
  ],
  AppLanguage.es: [
    'vuelo', 'vuelos', 'billete', 'boleto', 'avión',
    'ida y vuelta', 'viaje', 'volar a',
  ],
  AppLanguage.de: [
    'flug', 'flüge', 'fluege', 'ticket', 'hin und rückflug',
    'fliegen', 'direktflug',
  ],
  AppLanguage.it: [
    'volo', 'voli', 'biglietto', 'aereo', 'andata e ritorno',
    'volare', 'volo diretto',
  ],
  AppLanguage.pt: [
    'voo', 'voos', 'passagem', 'bilhete', 'avião',
    'ida e volta', 'voar', 'voo direto',
  ],
};

const _hotelPatterns = <AppLanguage, List<String>>{
  AppLanguage.fr: [
    'hotel', 'hôtel', 'airbnb', 'logement', 'booking', 'nuit ',
    'nuits ', 'séjour', 'sejour', 'réservation', 'reservation',
    'hebergement', 'hébergement',
  ],
  AppLanguage.en: [
    'hotel', 'motel', 'airbnb', 'accommodation', 'booking',
    'stay', 'night stay', 'nights', 'room', 'lodging',
    'place to stay', 'reservation',
  ],
  AppLanguage.es: [
    'hotel', 'alojamiento', 'airbnb', 'habitación',
    'noche', 'noches', 'estancia', 'reserva', 'booking',
  ],
  AppLanguage.de: [
    'hotel', 'unterkunft', 'airbnb', 'übernachtung',
    'zimmer', 'nacht', 'nächte', 'aufenthalt', 'buchung',
  ],
  AppLanguage.it: [
    'hotel', 'alloggio', 'airbnb', 'pernottamento',
    'notte', 'notti', 'soggiorno', 'prenotazione', 'camera',
  ],
  AppLanguage.pt: [
    'hotel', 'hotéis', 'alojamento', 'airbnb', 'quarto',
    'noite', 'noites', 'estadia', 'reserva', 'booking',
  ],
};

const _productPatterns = <AppLanguage, List<String>>{
  AppLanguage.fr: [
    'moins cher', 'meilleur prix', 'acheter', 'trouve le',
    'trouve moi', 'cherche le', 'cherche moi', 'prix le plus bas',
    'comparer', 'le moins cher',
  ],
  AppLanguage.en: [
    'cheapest', 'best price', 'buy', 'purchase', 'find the',
    'find me', 'search for', 'lowest price', 'compare prices',
    'where to buy', 'on sale', 'deal on',
  ],
  AppLanguage.es: [
    'más barato', 'mejor precio', 'comprar', 'encuentra',
    'búscame', 'precio más bajo', 'comparar', 'dónde comprar',
  ],
  AppLanguage.de: [
    'günstigste', 'billigste', 'bester preis', 'kaufen',
    'finde', 'suche', 'niedrigster preis', 'vergleichen',
    'wo kaufen',
  ],
  AppLanguage.it: [
    'più economico', 'miglior prezzo', 'comprare', 'acquistare',
    'trova il', 'cercami', 'prezzo più basso', 'confrontare',
  ],
  AppLanguage.pt: [
    'mais barato', 'melhor preço', 'comprar', 'encontra',
    'procura', 'preço mais baixo', 'comparar', 'onde comprar',
  ],
};

// ── Multilingual month name -> number ──────────────────────────────────────

int parseMonth(String name) {
  const months = {
    // French
    'janvier': 1, 'février': 2, 'fevrier': 2, 'mars': 3, 'avril': 4,
    'mai': 5, 'juin': 6, 'juillet': 7, 'août': 8, 'aout': 8,
    'septembre': 9, 'octobre': 10, 'novembre': 11, 'décembre': 12,
    'decembre': 12,
    // English
    'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5,
    'june': 6, 'july': 7, 'august': 8, 'september': 9, 'october': 10,
    'november': 11, 'december': 12,
    // Spanish
    'enero': 1, 'febrero': 2, 'marzo': 3, 'abril': 4, 'mayo': 5,
    'junio': 6, 'julio': 7, 'agosto': 8, 'septiembre': 9,
    'octubre': 10, 'noviembre': 11, 'diciembre': 12,
    // German
    'januar': 1, 'februar': 2, 'märz': 3, 'marz': 3,
    'juni': 6, 'juli': 7, 'oktober': 10, 'dezember': 12,
    // Italian
    'gennaio': 1, 'febbraio': 2, 'aprile': 4,
    'maggio': 5, 'giugno': 6, 'luglio': 7,
    'settembre': 9, 'ottobre': 10, 'dicembre': 12,
    // Portuguese
    'janeiro': 1, 'fevereiro': 2, 'março': 3, 'marco': 3,
    'maio': 5, 'junho': 6, 'julho': 7,
    'outubro': 10, 'novembro': 11, 'dezembro': 12,
  };
  return months[name.toLowerCase()] ?? 1;
}

// ── Slash command natural language translations ───────────────────────────

/// Translate a slash command to natural language in the user's language.
String toNaturalLanguage(String command, List<String> args,
    AppLanguage lang) {
  final a = args;
  switch (lang) {
    case AppLanguage.en:
      return _toNaturalEn(command, a);
    case AppLanguage.es:
      return _toNaturalEs(command, a);
    case AppLanguage.de:
      return _toNaturalDe(command, a);
    case AppLanguage.it:
      return _toNaturalIt(command, a);
    case AppLanguage.pt:
      return _toNaturalPt(command, a);
    case AppLanguage.fr:
    default:
      return _toNaturalFr(command, a);
  }
}

/// Returns the human-readable name for a language code in the given display language.
String _languageName(String code, AppLanguage lang) {
  const names = {
    AppLanguage.fr: {
      'fr': 'français', 'en': 'anglais', 'es': 'espagnol',
      'de': 'allemand', 'it': 'italien', 'pt': 'portugais',
      'ja': 'japonais', 'zh': 'chinois', 'ar': 'arabe',
      'ru': 'russe', 'ko': 'coréen', 'nl': 'néerlandais',
    },
    AppLanguage.en: {
      'fr': 'french', 'en': 'english', 'es': 'spanish',
      'de': 'german', 'it': 'italian', 'pt': 'portuguese',
      'ja': 'japanese', 'zh': 'chinese', 'ar': 'arabic',
      'ru': 'russian', 'ko': 'korean', 'nl': 'dutch',
    },
    AppLanguage.es: {
      'fr': 'francés', 'en': 'inglés', 'es': 'español',
      'de': 'alemán', 'it': 'italiano', 'pt': 'portugués',
      'ja': 'japonés', 'zh': 'chino', 'ar': 'árabe',
    },
    AppLanguage.de: {
      'fr': 'französisch', 'en': 'englisch', 'es': 'spanisch',
      'de': 'deutsch', 'it': 'italienisch', 'pt': 'portugiesisch',
      'ja': 'japanisch', 'zh': 'chinesisch', 'ar': 'arabisch',
    },
    AppLanguage.it: {
      'fr': 'francese', 'en': 'inglese', 'es': 'spagnolo',
      'de': 'tedesco', 'it': 'italiano', 'pt': 'portoghese',
      'ja': 'giapponese', 'zh': 'cinese', 'ar': 'arabo',
    },
    AppLanguage.pt: {
      'fr': 'francês', 'en': 'inglês', 'es': 'espanhol',
      'de': 'alemão', 'it': 'italiano', 'pt': 'português',
      'ja': 'japonês', 'zh': 'chinês', 'ar': 'árabe',
    },
  };
  return names[lang]?[code] ?? code;
}

// French ---------------------------------------------------------------
String _toNaturalFr(String cmd, List<String> a) {
  switch (cmd) {
    case 'links':
      final labels = {'all': '', 'video': ' vidéos', 'image': ' images',
          'audio': ' audios', 'document': ' documents'};
      final filter = a.isNotEmpty ? a[0] : 'all';
      final label = labels[filter];
      if (label != null) return 'Extrais tous les liens$label de la page courante';
      return 'Extrais tous les liens $filter de la page courante';
    case 'download': return 'Télécharge ${a.isNotEmpty ? a.join(' ') : 'un fichier'}';
    case 'pdf': return 'Convertir la page en PDF';
    case 'summarize': return 'Résume la page courante';
    case 'extract': return 'Extrais le contenu de ${a.isNotEmpty ? a[0] : 'la page'}';
    case 'scroll': return 'Fais défiler la page ${a.isNotEmpty ? 'de ${a[0]}px' : 'vers le bas'}';
    case 'open': return 'Ouvre ${a.isNotEmpty ? a[0] : 'une URL'}';
    case 'click': return 'Clique sur ${a.isNotEmpty ? a[0] : "l'élément"}';
    case 'fill': return a.length >= 2
        ? 'Remplis ${a[0]} avec "${a.sublist(1).join(' ')}"'
        : 'Remplis le formulaire';
    case 'screenshot': return "Capture d'écran de la page courante";
    case 'back': return 'Retour à la page précédente';
    case 'forward': return 'Va à la page suivante';
    case 'forms': return 'Extrais les formulaires de la page';
    case 'tables': return 'Extrais les tableaux de la page';
    case 'media': return 'Extrais les médias${a.isNotEmpty ? ' (${a[0]})' : ''} de la page';
    case 'metadata': return 'Affiche les métadonnées de la page';
    case 'autofill': return 'Remplis automatiquement le formulaire';
    case 'inspect': return 'Inspecte ${a.isNotEmpty ? a[0] : "l'élément"}';
    case 'highlight': return 'Surligne ${a.isNotEmpty ? a[0] : "l'élément"}';
    case 'waitfor': return 'Attends lapparition de ${a.isNotEmpty ? a[0] : "l'élément"}';
    case 'export': return 'Exporte la page en ${a.isNotEmpty ? a[0].toUpperCase() : 'JSON'}';
    case 'monitor': return 'Surveille ${a.isNotEmpty ? a[0] : "l'élément"}';
    case 'translate': return 'Traduis la page en ${a.isNotEmpty ? _languageName(a[0], AppLanguage.fr) : 'français'}';
    case 'searchpage': return 'Cherche "${a.isNotEmpty ? a.join(' ') : ''}" dans la page';
    default: return cmd;
  }
}

// English --------------------------------------------------------------
String _toNaturalEn(String cmd, List<String> a) {
  switch (cmd) {
    case 'links':
      final filter = a.isNotEmpty ? a[0] : 'all';
      final labels = {'all': '', 'video': ' videos', 'image': ' images',
          'audio': ' audios', 'document': ' documents'};
      final label = labels[filter];
      if (label != null) return 'Extract all$label links from the current page';
      return 'Extract all $filter links from the current page';
    case 'download': return 'Download ${a.isNotEmpty ? a.join(' ') : 'a file'}';
    case 'pdf': return 'Convert the page to PDF';
    case 'summarize': return 'Summarize the current page';
    case 'extract': return 'Extract content from ${a.isNotEmpty ? a[0] : 'the page'}';
    case 'scroll': return 'Scroll ${a.isNotEmpty ? a[0] : 'down'}';
    case 'open': return 'Open ${a.isNotEmpty ? a[0] : 'a URL'}';
    case 'click': return 'Click on ${a.isNotEmpty ? a[0] : 'the element'}';
    case 'fill': return a.length >= 2
        ? 'Fill ${a[0]} with "${a.sublist(1).join(' ')}"'
        : 'Fill the form';
    case 'screenshot': return 'Take a screenshot of the current page';
    case 'back': return 'Go back to the previous page';
    case 'forward': return 'Go to the next page';
    case 'forms': return 'Extract forms from the page';
    case 'tables': return 'Extract tables from the page';
    case 'media': return 'Extract media${a.isNotEmpty ? ' (${a[0]})' : ''} from the page';
    case 'metadata': return 'Show page metadata';
    case 'autofill': return 'Auto-fill the form';
    case 'inspect': return 'Inspect ${a.isNotEmpty ? a[0] : 'the element'}';
    case 'highlight': return 'Highlight ${a.isNotEmpty ? a[0] : 'the element'}';
    case 'waitfor': return 'Wait for ${a.isNotEmpty ? a[0] : 'the element'} to appear';
    case 'export': return 'Export page as ${a.isNotEmpty ? a[0].toUpperCase() : 'JSON'}';
    case 'monitor': return 'Monitor ${a.isNotEmpty ? a[0] : 'the element'}';
    case 'translate': return 'Translate the page to ${a.isNotEmpty ? _languageName(a[0], AppLanguage.en) : 'english'}';
    case 'searchpage': return 'Search for "${a.isNotEmpty ? a.join(' ') : ''}" on the page';
    default: return cmd;
  }
}

// Spanish --------------------------------------------------------------
String _toNaturalEs(String cmd, List<String> a) {
  switch (cmd) {
    case 'links':
      final filter = a.isNotEmpty ? a[0] : 'all';
      final labels = {'all': '', 'video': ' videos', 'image': ' imágenes',
          'audio': ' audios', 'document': ' documentos'};
      final label = labels[filter];
      if (label != null) return 'Extrae todos los enlaces$label de la página actual';
      return 'Extrae todos los enlaces $filter de la página actual';
    case 'download': return 'Descarga ${a.isNotEmpty ? a.join(' ') : 'un archivo'}';
    case 'pdf': return 'Convertir la página a PDF';
    case 'summarize': return 'Resume la página actual';
    case 'extract': return 'Extrae el contenido de ${a.isNotEmpty ? a[0] : 'la página'}';
    case 'scroll': return 'Desplaza ${a.isNotEmpty ? a[0] : 'hacia abajo'}';
    case 'open': return 'Abre ${a.isNotEmpty ? a[0] : 'una URL'}';
    case 'click': return 'Haz clic en ${a.isNotEmpty ? a[0] : 'el elemento'}';
    case 'fill': return a.length >= 2
        ? 'Rellena ${a[0]} con "${a.sublist(1).join(' ')}"'
        : 'Rellena el formulario';
    case 'screenshot': return 'Captura de pantalla de la página actual';
    case 'back': return 'Volver a la página anterior';
    case 'forward': return 'Ir a la página siguiente';
    case 'forms': return 'Extrae los formularios de la página';
    case 'tables': return 'Extrae las tablas de la página';
    case 'media': return 'Extrae los medios${a.isNotEmpty ? ' (${a[0]})' : ''} de la página';
    case 'metadata': return 'Muestra los metadatos de la página';
    case 'autofill': return 'Rellena automáticamente el formulario';
    case 'inspect': return 'Inspecciona ${a.isNotEmpty ? a[0] : 'el elemento'}';
    case 'highlight': return 'Resalta ${a.isNotEmpty ? a[0] : 'el elemento'}';
    case 'waitfor': return 'Espera a que aparezca ${a.isNotEmpty ? a[0] : 'el elemento'}';
    case 'export': return 'Exporta la página como ${a.isNotEmpty ? a[0].toUpperCase() : 'JSON'}';
    case 'monitor': return 'Monitoriza ${a.isNotEmpty ? a[0] : 'el elemento'}';
    case 'translate': return 'Traduce la página al ${a.isNotEmpty ? _languageName(a[0], AppLanguage.es) : 'español'}';
    case 'searchpage': return 'Busca "${a.isNotEmpty ? a.join(' ') : ''}" en la página';
    default: return cmd;
  }
}

// German --------------------------------------------------------------
String _toNaturalDe(String cmd, List<String> a) {
  switch (cmd) {
    case 'links':
      final filter = a.isNotEmpty ? a[0] : 'all';
      final labels = {'all': '', 'video': ' videos', 'image': ' bilder',
          'audio': ' audios', 'document': ' dokumente'};
      final label = labels[filter];
      if (label != null) return 'Extrahiere alle$label Links der aktuellen Seite';
      return 'Extrahiere alle $filter Links der aktuellen Seite';
    case 'download': return 'Lade ${a.isNotEmpty ? a.join(' ') : 'eine Datei'} herunter';
    case 'pdf': return 'Seite als PDF speichern';
    case 'summarize': return 'Fasse die aktuelle Seite zusammen';
    case 'extract': return 'Extrahiere Inhalt von ${a.isNotEmpty ? a[0] : 'der Seite'}';
    case 'scroll': return 'Scrolle ${a.isNotEmpty ? a[0] : 'nach unten'}';
    case 'open': return 'Öffne ${a.isNotEmpty ? a[0] : 'eine URL'}';
    case 'click': return 'Klicke auf ${a.isNotEmpty ? a[0] : 'das Element'}';
    case 'fill': return a.length >= 2
        ? 'Fülle ${a[0]} mit "${a.sublist(1).join(' ')}"'
        : 'Fülle das Formular aus';
    case 'screenshot': return 'Screenshot der aktuellen Seite';
    case 'back': return 'Zurück zur vorherigen Seite';
    case 'forward': return 'Zur nächsten Seite';
    case 'forms': return 'Extrahiere Formulare der Seite';
    case 'tables': return 'Extrahiere Tabellen der Seite';
    case 'media': return 'Extrahiere Medien${a.isNotEmpty ? ' (${a[0]})' : ''} der Seite';
    case 'metadata': return 'Zeige Seitenmetadaten';
    case 'autofill': return 'Formular automatisch ausfüllen';
    case 'inspect': return 'Inspiziere ${a.isNotEmpty ? a[0] : 'das Element'}';
    case 'highlight': return 'Hebe ${a.isNotEmpty ? a[0] : 'das Element'} hervor';
    case 'waitfor': return 'Warte auf ${a.isNotEmpty ? a[0] : 'das Element'}';
    case 'export': return 'Exportiere Seite als ${a.isNotEmpty ? a[0].toUpperCase() : 'JSON'}';
    case 'monitor': return 'Überwache ${a.isNotEmpty ? a[0] : 'das Element'}';
    case 'translate': return 'Übersetze die Seite ins ${a.isNotEmpty ? _languageName(a[0], AppLanguage.de) : 'Deutsche'}';
    case 'searchpage': return 'Suche "${a.isNotEmpty ? a.join(' ') : ''}" auf der Seite';
    default: return cmd;
  }
}

// Italian -------------------------------------------------------------
String _toNaturalIt(String cmd, List<String> a) {
  switch (cmd) {
    case 'links':
      final filter = a.isNotEmpty ? a[0] : 'all';
      final labels = {'all': '', 'video': ' video', 'image': ' immagini',
          'audio': ' audio', 'document': ' documenti'};
      final label = labels[filter];
      if (label != null) return 'Estrai tutti i link$label dalla pagina corrente';
      return 'Estrai tutti i link $filter dalla pagina corrente';
    case 'download': return 'Scarica ${a.isNotEmpty ? a.join(' ') : 'un file'}';
    case 'pdf': return 'Converti la pagina in PDF';
    case 'summarize': return 'Riassumi la pagina corrente';
    case 'extract': return 'Estrai contenuto da ${a.isNotEmpty ? a[0] : 'la pagina'}';
    case 'scroll': return 'Scorri ${a.isNotEmpty ? a[0] : 'in basso'}';
    case 'open': return 'Apri ${a.isNotEmpty ? a[0] : 'un URL'}';
    case 'click': return 'Clicca su ${a.isNotEmpty ? a[0] : "l'elemento"}';
    case 'fill': return a.length >= 2
        ? 'Riempi ${a[0]} con "${a.sublist(1).join(' ')}"'
        : 'Riempi il modulo';
    case 'screenshot': return 'Cattura schermo della pagina corrente';
    case 'back': return 'Torna alla pagina precedente';
    case 'forward': return 'Vai alla pagina successiva';
    case 'forms': return 'Estrai i moduli della pagina';
    case 'tables': return 'Estrai le tabelle della pagina';
    case 'media': return 'Estrai i media${a.isNotEmpty ? ' (${a[0]})' : ''} della pagina';
    case 'metadata': return 'Mostra i metadati della pagina';
    case 'autofill': return 'Riempi automaticamente il modulo';
    case 'inspect': return 'Ispeziona ${a.isNotEmpty ? a[0] : "l'elemento"}';
    case 'highlight': return 'Evidenzia ${a.isNotEmpty ? a[0] : "l'elemento"}';
    case 'waitfor': return 'Aspetta la comparsa di ${a.isNotEmpty ? a[0] : "l'elemento"}';
    case 'export': return 'Esporta pagina come ${a.isNotEmpty ? a[0].toUpperCase() : 'JSON'}';
    case 'monitor': return 'Monitora ${a.isNotEmpty ? a[0] : "l'elemento"}';
    case 'translate': return 'Traduci la pagina in ${a.isNotEmpty ? _languageName(a[0], AppLanguage.it) : 'italiano'}';
    case 'searchpage': return 'Cerca "${a.isNotEmpty ? a.join(' ') : ''}" nella pagina';
    default: return cmd;
  }
}

// Portuguese ----------------------------------------------------------
String _toNaturalPt(String cmd, List<String> a) {
  switch (cmd) {
    case 'links':
      final filter = a.isNotEmpty ? a[0] : 'all';
      final labels = {'all': '', 'video': ' vídeos', 'image': ' imagens',
          'audio': ' áudios', 'document': ' documentos'};
      final label = labels[filter];
      if (label != null) return 'Extrai todos os links$label da página atual';
      return 'Extrai todos os links $filter da página atual';
    case 'download': return 'Baixa ${a.isNotEmpty ? a.join(' ') : 'um ficheiro'}';
    case 'pdf': return 'Converter a página para PDF';
    case 'summarize': return 'Resume a página atual';
    case 'extract': return 'Extrai conteúdo de ${a.isNotEmpty ? a[0] : 'a página'}';
    case 'scroll': return 'Rola ${a.isNotEmpty ? a[0] : 'para baixo'}';
    case 'open': return 'Abre ${a.isNotEmpty ? a[0] : 'uma URL'}';
    case 'click': return 'Clica em ${a.isNotEmpty ? a[0] : 'o elemento'}';
    case 'fill': return a.length >= 2
        ? 'Preenche ${a[0]} com "${a.sublist(1).join(' ')}"'
        : 'Preenche o formulário';
    case 'screenshot': return 'Captura de ecrã da página atual';
    case 'back': return 'Voltar à página anterior';
    case 'forward': return 'Ir para a página seguinte';
    case 'forms': return 'Extrai os formulários da página';
    case 'tables': return 'Extrai as tabelas da página';
    case 'media': return 'Extrai os media${a.isNotEmpty ? ' (${a[0]})' : ''} da página';
    case 'metadata': return 'Mostra os metadados da página';
    case 'autofill': return 'Preenche automaticamente o formulário';
    case 'inspect': return 'Inspeciona ${a.isNotEmpty ? a[0] : 'o elemento'}';
    case 'highlight': return 'Destaca ${a.isNotEmpty ? a[0] : 'o elemento'}';
    case 'waitfor': return 'Aguarda o aparecimento de ${a.isNotEmpty ? a[0] : 'o elemento'}';
    case 'export': return 'Exporta página como ${a.isNotEmpty ? a[0].toUpperCase() : 'JSON'}';
    case 'monitor': return 'Monitoriza ${a.isNotEmpty ? a[0] : 'o elemento'}';
    case 'translate': return 'Traduz a página para ${a.isNotEmpty ? _languageName(a[0], AppLanguage.pt) : 'português'}';
    case 'searchpage': return 'Procura "${a.isNotEmpty ? a.join(' ') : ''}" na página';
    default: return cmd;
  }
}
