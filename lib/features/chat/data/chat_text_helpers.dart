/// Helpers texte purs extraits de `ChatNotifier` (ADR-029, Bloc 3 cluster 4).
///
/// Ces 7 fonctions ne dépendent d'aucun état Riverpod (`ref`/`state`) ni d'aucun
/// service injecté — uniquement de leurs arguments. Extraites du god-object
/// `chat_notifier.dart` (3943 lignes) pour :
///   • réduire la taille du notifier (logique métier vs logique d'état) ;
///   • les rendre unit-testables isolément (elles étaient privées au notifier) ;
///   • rassembler les helpers résiduels qui n'appartenaient à aucun cluster
///     thématique existant (`WebSearchTrigger`, `TravelParamsParser`,
///     `SearchIntentExtractor`).
///
/// Ce sont toutes des fonctions pures de formatage/parsing de texte, sans
/// dépendance partagée. Les sections ci-dessous reflètent les 4 sous-préoccupations
/// d'origine (document/export, browser-action, recherche produit, erreur IA).

import 'dart:convert';

import 'ai_client.dart' show AiException;
import 'search_intent_extractor.dart' show SearchParams;

// ── Document / export ─────────────────────────────────────────────────────────

/// Normalise un format de document brut vers la forme canonique attendue par le
/// générateur de documents.
///
/// Accepte les variantes courantes (txt/text, md/markdown, doc/docx/word,
/// ppt/pptx/powerpoint, xls/xlsx/excel, jpg/jpeg, png, pdf) et renvoie la forme
/// canonique en minuscules (`text`, `markdown`, `word`, `powerpoint`, `excel`,
/// `jpg`, `png`, `pdf`). Toute autre valeur est renvoyée en minuscules telle quelle.
String normalizeDocFormat(String raw) {
  final lower = raw.toLowerCase();
  if (lower == 'txt' || lower == 'text') return 'text';
  if (lower == 'md' || lower == 'markdown') return 'markdown';
  if (lower == 'doc' || lower == 'docx' || lower == 'word') return 'word';
  if (lower == 'ppt' || lower == 'pptx' || lower == 'powerpoint') return 'powerpoint';
  if (lower == 'xls' || lower == 'xlsx' || lower == 'excel') return 'excel';
  if (lower == 'jpg' || lower == 'jpeg') return 'jpg';
  if (lower == 'png') return 'png';
  if (lower == 'pdf') return 'pdf';
  return lower;
}

/// Extrait un titre de document depuis un brouillon markdown.
///
/// Priorité : (1) premier en-tête H1 (`# Titre`) ; (2) première ligne non-vide,
/// débarrassée des préfixes de liste/numérotation ; (3) `fallbackTopic`.
/// Le résultat est tronqué à 80 caractères.
String extractDocumentTitle(String draft, {required String fallbackTopic}) {
  final h1 = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(draft)?.group(1);
  if (h1 != null && h1.trim().isNotEmpty) {
    return h1.trim();
  }

  final firstLine = draft
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => fallbackTopic)
      .replaceAll(RegExp(r'^[\-\d.\s]+'), '');

  final safe = firstLine.isEmpty ? fallbackTopic : firstLine;
  return safe.length > 80 ? safe.substring(0, 80) : safe;
}

/// Échappe une chaîne pour l'insérer comme valeur JSON entre guillemets.
///
/// Utilisé pour construire manuellement du JSON de métadonnées d'export
/// (échappe les backslashes, guillemets doubles et sauts de ligne).
String escapeForJson(String s) =>
    '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')}"';

// ── Browser actions (extension Chrome) ────────────────────────────────────────

/// Supprime les balises `[CORELY_ACTION]...[/CORELY_ACTION]` du texte affiché.
String stripActionCommands(String text) {
  return text
      .replaceAll(
        RegExp(r'\[CORELY_ACTION\][\s\S]*?\[/CORELY_ACTION\]', multiLine: true),
        '',
      )
      .trim();
}

/// Parse JSON de manière tolérante (accepte les sauts de ligne dans les strings).
///
/// Retourne `null` si le JSON est invalide (au lieu de lever) — utilisé pour le
/// parsing des payloads d'action navigateur où une erreur de format ne doit pas
/// casser le traitement du reste de la réponse IA.
Map<String, dynamic>? parseJsonLoose(String jsonStr) {
  try {
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

// ── Recherche produits (enhanced search) ─────────────────────────────────────

/// Construit la requête de recherche produit en concaténant la requête de base
/// et les filtres [`SearchParams`] (catégorie, couleur, condition, gamme de prix),
/// en évitant les doublons de tokens (insensible à la casse).
String buildProductSearchQuery(String searchQuery, SearchParams? params) {
  final tokens = <String>[searchQuery.trim()];
  void add(String? value) {
    if (value == null || value.trim().isEmpty) return;
    final v = value.trim();
    if (!tokens.any((t) => t.toLowerCase().contains(v.toLowerCase()))) {
      tokens.add(v);
    }
  }

  add(params?.category);
  add(params?.color);
  if (params?.condition == 'refurbished') add('reconditionné');
  if (params?.condition == 'used') add('occasion');
  if (params?.priceRange == 'cheapest') add('meilleur prix');

  return tokens.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ── Erreur IA ─────────────────────────────────────────────────────────────────

/// Formate une [`AiException`] en message utilisateur lisible.
///
/// Catégorise le message brut en : analyse d'image indisponible (fournisseur
/// courant), clé API (message conservé), rate-limit (429), ou erreur générique.
String formatAiError(AiException e) {
  final msg = e.message;
  if (msg.contains('image') || msg.contains('image_url')) {
    return 'Analyse d\'image indisponible avec le fournisseur actuel. '
        'Verifiez d\'abord la cle DeepSeek, puis OpenRouter si besoin.';
  }
  if (msg.contains('Clé API')) return msg;
  if (msg.contains('429') || msg.contains('Trop de requêtes')) {
    return 'Limite de requetes atteinte. Reessayez dans un moment.';
  }
  return 'Erreur IA. Reessayez.';
}