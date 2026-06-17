// Tests pour les helpers texte purs extraits de ChatNotifier (ADR-029, Bloc 3
// cluster 4). Voir lib/features/chat/data/chat_text_helpers.dart.
//
// Ces fonctions étaient privées au god-object `chat_notifier.dart` (donc non
// testables isolément) ; l'extraction les rend unit-testables et verrouille leur
// comportement pour empêcher toute régression silencieuse lors d'une refactor
// future du notifier.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:corel_ia/features/chat/data/ai_client.dart' show AiException;
import 'package:corel_ia/features/chat/data/chat_text_helpers.dart';
import 'package:corel_ia/features/chat/data/search_intent_extractor.dart'
    show SearchParams;

void main() {
  // ── normalizeDocFormat ──────────────────────────────────────────────────────
  group('normalizeDocFormat', () {
    test('variantes courantes → forme canonique', () {
      expect(normalizeDocFormat('txt'), 'text');
      expect(normalizeDocFormat('text'), 'text');
      expect(normalizeDocFormat('md'), 'markdown');
      expect(normalizeDocFormat('markdown'), 'markdown');
      expect(normalizeDocFormat('doc'), 'word');
      expect(normalizeDocFormat('docx'), 'word');
      expect(normalizeDocFormat('word'), 'word');
      expect(normalizeDocFormat('ppt'), 'powerpoint');
      expect(normalizeDocFormat('pptx'), 'powerpoint');
      expect(normalizeDocFormat('powerpoint'), 'powerpoint');
      expect(normalizeDocFormat('xls'), 'excel');
      expect(normalizeDocFormat('xlsx'), 'excel');
      expect(normalizeDocFormat('excel'), 'excel');
      expect(normalizeDocFormat('jpg'), 'jpg');
      expect(normalizeDocFormat('jpeg'), 'jpg');
      expect(normalizeDocFormat('png'), 'png');
      expect(normalizeDocFormat('pdf'), 'pdf');
    });

    test('insensible à la casse', () {
      expect(normalizeDocFormat('MD'), 'markdown');
      expect(normalizeDocFormat('Pdf'), 'pdf');
      expect(normalizeDocFormat('DOCX'), 'word');
    });

    test('format inconnu → minuscules tels quels', () {
      expect(normalizeDocFormat('csv'), 'csv');
      expect(normalizeDocFormat('RTF'), 'rtf');
      expect(normalizeDocFormat(''), '');
    });
  });

  // ── extractDocumentTitle ────────────────────────────────────────────────────
  group('extractDocumentTitle', () {
    test('H1 prioritaire', () {
      const draft = '# Mon Titre\n\nLorem ipsum dolor sit amet.\n\nSuite.';
      expect(extractDocumentTitle(draft, fallbackTopic: 'fallback'), 'Mon Titre');
    });

    test('H1 avec espaces autour est trimé', () {
      const draft = '#   Titre espacé   \nCorps';
      expect(extractDocumentTitle(draft, fallbackTopic: 'fb'), 'Titre espacé');
    });

    test('sans H1 → première ligne non-vide nettoyée des préfixes', () {
      const draft = '\n\n- Introduction au sujet\nDétails';
      expect(
        extractDocumentTitle(draft, fallbackTopic: 'fb'),
        'Introduction au sujet',
      );
    });

    test('préfixe numérique de liste retiré', () {
      const draft = '1. Chapitre un\nSuite';
      expect(extractDocumentTitle(draft, fallbackTopic: 'fb'), 'Chapitre un');
    });

    test('draft vide → fallbackTopic', () {
      expect(extractDocumentTitle('', fallbackTopic: 'sujet'), 'sujet');
      expect(
        extractDocumentTitle('   \n  \n ', fallbackTopic: 'sujet'),
        'sujet',
      );
    });

    test('tronqué à 80 caractères (chemin firstLine, sans H1)', () {
      // La troncature à 80 ne s'applique qu'au chemin firstLine (pas au chemin
      // H1 — voir le test ci-dessous). Une longue première ligne sans H1 est
      // donc tronquée.
      final long = 'a' * 200;
      final result = extractDocumentTitle(long, fallbackTopic: 'fb');
      expect(result.length, 80);
      expect(result, 'a' * 80);
    });

    test('H1 très long retourné en entier (pas de troncature sur le chemin H1)', () {
      // Asymétrie documentée : le chemin H1 retourne h1.trim() sans troncature,
      // contrairement au chemin firstLine. On verrouille ce comportement pour
      // qu'une refactor future ne le change pas silencieusement.
      final long = '# ${'a' * 200}';
      final result = extractDocumentTitle(long, fallbackTopic: 'fb');
      expect(result.length, 200);
      expect(result, 'a' * 200);
    });
  });

  // ── escapeForJson ────────────────────────────────────────────────────────────
  group('escapeForJson', () {
    test('entoure de guillemets doubles', () {
      expect(escapeForJson('hello'), '"hello"');
    });

    test('échappe les backslashes', () {
      expect(escapeForJson(r'a\b'), r'"a\\b"');
    });

    test('échappe les guillemets doubles', () {
      expect(escapeForJson('a"b'), r'"a\"b"');
    });

    test('échappe les sauts de ligne', () {
      expect(escapeForJson('a\nb'), r'"a\nb"');
    });

    test('combinaison complète', () {
      // "ligne1\nligne2 \"avec guillemets\" et \\backslash"
      final input = 'ligne1\nligne2 "avec guillemets" et \\backslash';
      final out = escapeForJson(input);
      // Décodage JSON round-trip → on retrouve le contenu d'origine.
      expect(out.startsWith('"'), isTrue);
      expect(out.endsWith('"'), isTrue);
      // Le résultat doit être une valeur JSON valide (round-trip via decode).
      final decoded = _decode(out);
      expect(decoded, input);
    });

    test('chaîne vide', () {
      expect(escapeForJson(''), '""');
    });
  });

  // ── stripActionCommands ────────────────────────────────────────────────────
  group('stripActionCommands', () {
    test('retire un bloc action isolé (laisse les newlines autour)', () {
      // Le regex retire les tokens [CORELY_ACTION]…[/CORELY_ACTION] mais ne
      // consomme pas les newlines autour ; le bloc sur sa propre ligne laisse
      // donc une ligne vide. trim() ne touche que les extrémités du texte.
      const text = 'Voici une réponse.\n'
          '[CORELY_ACTION]{"action": "OPEN_URL", "params": {"url": "https://x"}}[/CORELY_ACTION]\n'
          'Fin.';
      expect(stripActionCommands(text), 'Voici une réponse.\n\nFin.');
    });

    test('retire plusieurs blocs', () {
      const text = '[CORELY_ACTION]{"action": "A"}[/CORELY_ACTION] milieu '
          '[CORELY_ACTION]{"action": "B"}[/CORELY_ACTION] fin';
      expect(stripActionCommands(text), 'milieu  fin');
    });

    test('sans bloc → texte inchangé (trimé)', () {
      expect(stripActionCommands('  texte simple  '), 'texte simple');
    });

    test('bloc sur plusieurs lignes (multiLine)', () {
      // Le bloc contient des newlines internes (attrapés par [\s\S]*?) ; les
      // newlines avant/après le bloc ne sont pas consommées → double newline.
      const text = 'Avant\n'
          '[CORELY_ACTION]\n{"action": "SCROLL", "params": {"direction": "down"}}\n[/CORELY_ACTION]\n'
          'Après';
      expect(stripActionCommands(text), 'Avant\n\nAprès');
    });
  });

  // ── parseJsonLoose ──────────────────────────────────────────────────────────
  group('parseJsonLoose', () {
    test('objet JSON valide → Map', () {
      final r = parseJsonLoose('{"action": "open", "count": 3}');
      expect(r, isA<Map<String, dynamic>>());
      expect(r!['action'], 'open');
      expect(r['count'], 3);
    });

    test('JSON valide avec sauts de ligne entre les tokens', () {
      final r = parseJsonLoose('{\n  "action": "open",\n  "params": {}\n}');
      expect(r, isNotNull);
      expect(r!['action'], 'open');
    });

    test('JSON invalide → null (pas d\'exception)', () {
      expect(parseJsonLoose('pas du tout du json'), isNull);
      expect(parseJsonLoose('{broken:'), isNull);
      expect(parseJsonLoose(''), isNull);
    });

    test('un tableau JSON n\'est pas un Map → null (cast échoue, attrapé)', () {
      // jsonDecode renvoie une List, le cast `as Map<String, dynamic>` lève →
      // attrapé → null. C'est le contrat : on ne veut que des objets.
      expect(parseJsonLoose('[1, 2, 3]'), isNull);
    });
  });

  // ── buildProductSearchQuery ─────────────────────────────────────────────────
  group('buildProductSearchQuery', () {
    test('requête seule (params null) → trimée', () {
      expect(buildProductSearchQuery('  iphone 15  ', null), 'iphone 15');
    });

    test('ajoute la catégorie', () {
      final params = SearchParams(intent: 'products', category: 'reconditionné');
      expect(
        buildProductSearchQuery('iphone', params),
        'iphone reconditionné',
      );
    });

    test('ajoute la couleur', () {
      final params = SearchParams(intent: 'products', color: 'noir');
      expect(buildProductSearchQuery('chaussures', params), 'chaussures noir');
    });

    test('condition refurbished → token "reconditionné"', () {
      final params = SearchParams(intent: 'products', condition: 'refurbished');
      expect(
        buildProductSearchQuery('macbook', params),
        'macbook reconditionné',
      );
    });

    test('condition used → token "occasion"', () {
      final params = SearchParams(intent: 'secondhand', condition: 'used');
      expect(buildProductSearchQuery('vélo', params), 'vélo occasion');
    });

    test('priceRange cheapest → token "meilleur prix"', () {
      final params = SearchParams(intent: 'bestdeal', priceRange: 'cheapest');
      expect(
        buildProductSearchQuery('aspirateur', params),
        'aspirateur meilleur prix',
      );
    });

    test('dédoublonne (catégorie déjà contenue dans la requête)', () {
      // 'reconditionné' est déjà dans la requête → pas re-ajouté.
      final params = SearchParams(intent: 'products', category: 'reconditionné');
      expect(
        buildProductSearchQuery('iphone reconditionné', params),
        'iphone reconditionné',
      );
    });

    test('combinaison complète (catégorie + couleur + condition + prix)', () {
      final params = SearchParams(
        intent: 'products',
        category: 'téléphone',
        color: 'bleu',
        condition: 'refurbished',
        priceRange: 'cheapest',
      );
      final q = buildProductSearchQuery('samsung', params);
      expect(q, 'samsung téléphone bleu reconditionné meilleur prix');
    });

    test('condition "new" n\'ajoute rien', () {
      final params = SearchParams(intent: 'products', condition: 'new');
      expect(buildProductSearchQuery('ps5', params), 'ps5');
    });
  });

  // ── formatAiError ────────────────────────────────────────────────────────────
  group('formatAiError', () {
    test('erreur image → message analyse d\'image indisponible', () {
      final e = AiException('image not supported by provider');
      final msg = formatAiError(e);
      expect(msg, contains('image'));
      expect(msg, contains('indisponible'));
    });

    test('erreur image_url → même message image', () {
      final e = AiException('image_url format invalid');
      expect(formatAiError(e), contains('indisponible'));
    });

    test('erreur "Clé API" → message conservé tel quel', () {
      const original = 'Clé API invalide ou manquante';
      final e = AiException(original);
      expect(formatAiError(e), original);
    });

    test('erreur 429 → message de rate-limit', () {
      final e = AiException('HTTP 429 Too Many Requests');
      final msg = formatAiError(e);
      expect(msg, contains('Limite de requetes'));
    });

    test('erreur "Trop de requêtes" → message de rate-limit', () {
      final e = AiException('Trop de requêtes envoyées');
      expect(formatAiError(e), contains('Limite de requetes'));
    });

    test('erreur générique → message par défaut', () {
      final e = AiException('something unexpected happened');
      expect(formatAiError(e), 'Erreur IA. Reessayez.');
    });
  });
}

/// Décode une chaîne JSON (utilisée pour le round-trip d'escapeForJson).
/// En cas d'échec, lève → le test échoue explicitement.
String _decode(String quoted) {
  // quoted est une valeur JSON complète ("...") → on l'enveloppe dans un objet
  // pour la décoder via jsonDecode, puis on extrait le champ.
  // ignore: avoid_dynamic_calls
  return (jsonDecode('{"v": $quoted}')['v'] as String).toString();
}