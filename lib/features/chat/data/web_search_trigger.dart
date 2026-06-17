/// Décide si une requête utilisateur doit déclencher une recherche web, et
/// nettoie la requête envoyée au moteur de recherche.
///
/// Source unique (ADR-029, Bloc 3 cluster 2) extraite de `ChatNotifier` — ces
/// deux fonctions pures (sans état, sans `ref`, sans IO) vivaient en méthodes
/// privées statiques dans le god object `chat_notifier.dart`. Extraction vers
/// une classe utilitaire dédiée pour :
///
/// - **Testabilité isolée** : testable sans `ProviderContainer` ni `ChatNotifier`.
/// - **Cohésion** : toute la logique « faut-il chercher sur le web ? » au même
///   endroit, multilingue (FR/EN/ES/DE/IT/PT).
/// - **Décomposition** : amorce la réduction du god object (cf. ADR-029).
///
/// Méthodes 100% statiques et pures.
class WebSearchTrigger {
  WebSearchTrigger._(); // classe utilitaire — pas d'instances

  /// Décide si le message utilisateur doit déclencher une recherche web.
  ///
  /// Heuristique multilingue (FR/EN/ES/DE/IT/PT) :
  /// - **Déclencheurs** : informations factuelles/temporelles (actualité, prix,
  ///   météo, vols, hôtels, scores, « quelle est la », « what is », etc.).
  /// - **Exclusions** : créativité, code, opinion, conversation (écris, code,
  ///   poème, « write a », « what do you think », etc.) → pas de recherche.
  /// - **Question explicite avec `?`** : recherche si la question est courte
  ///   (≤ 100 chars), sinon considérée comme conversationnelle.
  /// - **Défaut** : pas de recherche (conversation normale).
  static bool needsWebSearch(String message) {
    final lower = message.toLowerCase();
    // Mots-clés déclencheurs : informations factuelles/temporelles (multilingue)
    const triggerWords = [
      'actualité', 'actualites', 'news', 'aujourd\'hui', 'en ce moment',
      'quelle est la', 'quel est le', 'combien de', 'combien coûte',
      'où est', 'ou est', 'où trouver', 'ou trouver',
      'qui est', 'qui a', 'quand est', 'quelle année', 'quel année',
      'dernier', 'dernière', 'latest', 'newest', 'current',
      'prix de', 'cours de', 'taux de', 'météo', 'meteo',
      'score de', 'résultat de', 'classement de',
      'est-ce que', 'est-il vrai', 'vrai ou faux',
      'comment aller', 'itinéraire', 'distance entre',
      'le moins cher', 'meilleur prix', 'pas cher', 'acheter', 'comparer',
      'billet d\'avion', 'vol direct', 'vols pas', 'vol pour',
      'hotel', 'hôtel', 'logement', 'airbnb', 'réservation',
      'pleuvoir', 'température', 'quel temps', 'pluie',
      'site pour', 'où acheter', 'trouve le', 'trouve moi',
      'cherche le', 'cherche moi', 'recherche le',
      'xiaomi', 'iphone', 'samsung', 'téléphone', 'smartphone',
      // EN
      'what is', 'who is', 'where is', 'when is', 'why is', 'how is',
      'how much', 'how many', 'price of', 'cost of',
      'weather', 'forecast', 'rain', 'stock', 'score of',
      'cheapest', 'best price', 'buy', 'where to buy',
      'flight', 'flights', 'plane ticket',
      // ES
      'qué es', 'quién es', 'dónde está', 'cuándo es', 'cuánto',
      'clima', 'lluvia', 'pronóstico', 'precio de',
      'más barato', 'comprar', 'vuelo', 'vuelos',
      // DE
      'was ist', 'wer ist', 'wo ist', 'wann ist', 'wie viel',
      'wetter', 'regen', 'vorhersage', 'preis von',
      'günstigste', 'kaufen', 'flug', 'flüge',
      // IT
      'cosa è', 'chi è', 'dov\'è', 'quando è', 'quanto',
      'meteo', 'pioggia', 'previsioni', 'prezzo di',
      'più economico', 'comprare', 'volo', 'voli',
      // PT
      'o que é', 'quem é', 'onde está', 'quando é', 'quanto',
      'clima', 'chuva', 'previsão', 'preço de',
      'mais barato', 'comprar', 'voo', 'voos',
    ];
    // Mots-clés exclus : créativité, code, opinion, conversation (multilingue)
    const excludeWords = [
      'écris', 'ecris', 'rédige', 'redige', 'raconte', 'invente',
      'imagine', 'crée', 'cree', 'dessine', 'compose',
      'code', 'programme', 'fonction', 'script', 'algorithme',
      'explique-moi', 'explique comment', 'pourquoi le',
      'qu\'en penses-tu', 'ton avis', 'selon toi',
      'story', 'poème', 'poeme', 'chanson', 'blague',
      // EN
      'write a', 'compose a', 'imagine', 'create a', 'draw',
      'code a', 'program', 'function', 'what do you think',
      'your opinion', 'story', 'poem', 'song', 'joke',
      // ES
      'escribe', 'redacta', 'imagina', 'crea', 'dibuja',
      'programa', 'función', 'qué opinas', 'poema', 'canción',
      // DE
      'schreibe', 'erfinde', 'erstelle', 'zeichne',
      'programmiere', 'funktion', 'was denkst du', 'gedicht',
      // IT
      'scrivi', 'inventa', 'immagina', 'crea', 'disegna',
      'programma', 'funzione', 'cosa pensi', 'poesia',
      // PT
      'escreve', 'inventa', 'imagina', 'cria', 'desenha',
      'programa', 'função', 'o que achas', 'poema',
    ];
    // Si le message contient un mot-clé exclusif, pas de recherche
    if (excludeWords.any((w) => lower.contains(w))) return false;
    // Si le message contient un mot-clé déclencheur, recherche
    if (triggerWords.any((w) => lower.contains(w))) return true;
    // Questions explicites avec "?" — heuristique
    if (lower.contains('?')) {
      // Les questions longues et détaillées sont souvent conversationnelles
      if (lower.length > 100) return false;
      return true;
    }
    // Par défaut, pas de recherche (conversation normale)
    return false;
  }

  /// Extrait une requête de recherche optimisée à partir du message
  /// utilisateur. Supprime les salutations et le contexte conversationnel
  /// superflu, et limite la longueur (max 200 chars).
  static String extractSearchQuery(String message) {
    var query = message.trim();
    // Retirer les salutations courantes
    const salutations = ['bonjour', 'salut', 'hello', 'hi', 'hey', 'coucou'];
    for (final s in salutations) {
      if (query.toLowerCase().startsWith(s)) {
        query = query.substring(s.length).trim();
        break;
      }
    }
    // Limiter la longueur de la requête
    if (query.length > 200) {
      query = '${query.substring(0, 200)}...';
    }
    return query;
  }
}