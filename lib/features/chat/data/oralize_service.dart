import 'dart:convert';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants.dart';

/// Service d'oralisation — convertit le markdown IA en texte oral naturel.
///
/// Problème : les réponses IA contiennent du markdown (sources, citations [n],
/// tableaux, blocs de code, astérisques, tirets) qui sonnent robotiques au TTS.
/// Les regex de nettoyage ([cleanMarkdown]) sont fragiles — chaque nouvelle
/// forme de markdown nécessite un patch.
///
/// Solution : un appel LLM léger (DeepSeek Flash, ~100 tokens out, ~0.5-1s)
/// qui convertit le markdown en texte oral naturel. Le LLM comprend le contexte
/// et sait exactement ce qui doit être dit à l'oral vs ce qui est structurel.
///
/// Coût : ~$0.00003 par appel (négligeable).
///
/// Utilisation :
/// ```dart
/// final spokenText = await OralizeService.oralize(markdownText);
/// ```
class OralizeService {
  OralizeService._();

  static const _endpoint = AppConstants.deepSeekBaseUrl;
  static const _model = AppConstants.deepSeekModel; // deepseek-v4-flash

  /// Cache LRU simple — évite de ré-oraliser des textes identiques.
  static final Map<String, _CacheEntry> _cache = {};
  static const int _maxCacheSize = 32;

  // ── API publique ──────────────────────────────────────────────────────────

  /// Convertit un texte markdown en texte oral naturel via DeepSeek Flash.
  ///
  /// Si le texte est déjà propre (< 100 chars, pas de markdown), retourne
  /// le texte tel quel sans appel LLM. En cas d'échec (réseau, timeout, clé
  /// absente), retourne le texte original — l'appelant utilisera [cleanMarkdown]
  /// comme fallback.
  static Future<String> oralize(String markdown, {bool isPro = false}) async {
    // 1. Texte court : probablement déjà oral
    if (markdown.length < 100) return markdown;

    // 2. Vérifier si le texte contient du markdown problématique
    if (!_needsOralization(markdown)) return markdown;

    // 3. Tier-aware : l'oralisation LLM coûte ~$0.00003/appel via la clé DeepSeek
    //    opérateur. Réservée aux utilisateurs Pro — les utilisateurs gratuits
    //    utilisent cleanMarkdown (regex) appliqué par l'appelant (speakNaturally),
    //    gratuit et suffisant. On retourne le markdown brut ici ; l'appelant
    //    appliquera cleanMarkdown ensuite, donc l'utilisateur gratuit entend
    //    quand même un texte nettoyé (comportement pré-Oralize-Pass).
    if (!isPro) return markdown;

    // 4. Cache (LRU)
    final cacheKey = _makeCacheKey(markdown);
    final cached = _cache[cacheKey];
    if (cached != null) {
      // LRU touch : replacer l'entrée en fin d'ordre d'insertion pour ne pas
      // être évincée prématurément. Sans cela, _addToCache évince l'entrée la
      // plus ancienne (FIFO), pas la moins récemment utilisée (LRU).
      _cache.remove(cacheKey);
      _cache[cacheKey] = cached;
      debugPrint('[OralizeService] Cache hit (${cached.value.length} chars)');
      return cached.value;
    }

    // 5. Clé API
    final apiKey = AppConstants.deepSeekApiKey;
    if (apiKey.isEmpty) {
      debugPrint('[OralizeService] No DeepSeek API key — skipping oralization');
      return markdown;
    }

    // 6. Appel LLM — timeout court (4s) : en mode vocal half-duplex, cet appel
    //    bloque le tour de conversation. Mieux vaut retomber sur cleanMarkdown
    //    rapidement que de faire attendre l'utilisateur jusqu'à 8s en silence.
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': _model,
              'stream': false,
              'max_tokens': min(markdown.length ~/ 2, 1024),
              'temperature': 0.1,
              'messages': [
                {'role': 'system', 'content': _systemPrompt},
                {'role': 'user', 'content': markdown},
              ],
            }),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List<dynamic>?;
        String? content;
        if (choices != null && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map) {
            final message = first['message'];
            if (message is Map) {
              final c = message['content'];
              if (c is String) {
                content = c;
              }
            }
          }
        }

        if (content != null && content.trim().isNotEmpty) {
          debugPrint(
            '[OralizeService] Oralized: ${markdown.length} → ${content.length} chars '
            '(${(content.length / markdown.length * 100).toStringAsFixed(0)}%)',
          );
          _addToCache(cacheKey, content);
          return content;
        }
      } else {
        debugPrint(
          '[OralizeService] LLM error ${response.statusCode}: '
          '${response.body.substring(0, min(response.body.length, 200))}',
        );
      }
    } on http.ClientException catch (e) {
      debugPrint('[OralizeService] HTTP client error: $e');
    } catch (e) {
      debugPrint('[OralizeService] Unexpected error: $e');
    }

    return markdown; // Fallback : on garde le markdown, cleanMarkdown fera le taf
  }

  /// Vide le cache (utile pour les tests).
  static void clearCache() => _cache.clear();

  // ── Interne ───────────────────────────────────────────────────────────────

  /// Détecte si le texte contient des éléments markdown qui justifient
  /// une oralisation par LLM.
  static bool _needsOralization(String text) {
    // Code blocks
    if (text.contains('```')) return true;
    // Tables (pipes sur plusieurs lignes)
    if ('|'.allMatches(text).length >= 4) return true;
    // Liens markdown [text](url) ou citations [n]
    if (text.contains('[') && text.contains(']')) return true;
    // URLs
    if (text.contains('http://') || text.contains('https://')) return true;
    // Headers markdown
    if (RegExp(r'^#{1,6}\s', multiLine: true).hasMatch(text)) return true;
    // Listes numérotées (> 2 occurrences)
    if (RegExp(r'^\d+\.\s', multiLine: true).allMatches(text).length >= 3) {
      return true;
    }
    // Listes à puces (> 2 occurrences)
    if (RegExp(r'^\s*[-*]\s', multiLine: true).allMatches(text).length >= 3) {
      return true;
    }
    // Séparateurs horizontaux
    if (text.contains('---')) return true;
    // Formatage gras/italique (si plusieurs occurrences — pas un simple astérisque)
    if ('*'.allMatches(text).length >= 4) return true;

    return false;
  }

  /// Clé de cache simple basée sur le contenu.
  static String _makeCacheKey(String text) {
    // Utiliser les premiers + derniers caractères pour une clé stable
    final head = text.length <= 200 ? text : text.substring(0, 200);
    final tail =
        text.length <= 200 ? '' : text.substring(text.length - min(text.length - 200, 100));
    return '$head|$tail';
  }

  static void _addToCache(String key, String value) {
    // Éviction LRU : supprimer la plus ancienne entrée si plein
    if (_cache.length >= _maxCacheSize) {
      final oldest = _cache.entries.first;
      _cache.remove(oldest.key);
    }
    _cache[key] = _CacheEntry(value);
  }

  // ── Prompt système ────────────────────────────────────────────────────────

  static const _systemPrompt = '''
Tu es un convertisseur markdown vers oral. Ta tâche est de convertir le
texte markdown fourni en texte destiné à être lu à voix haute par un
synthétiseur vocal.

RÈGLES :
1. Supprime les sections "Sources", "Références", "Liens" et tout contenu de type note de bas de page
2. Supprime les blocs de code et remplace-les par une brève mention orale si pertinent (ex: "un extrait de code", "un exemple en Python")
3. Convertit les tableaux en phrases naturelles — pas de pipes | ni de colonnes
4. Supprime les astérisques, tirets de liste, crochets [n], et toute ponctuation markdown
5. Supprime les URLs — ne les lis jamais à voix haute
6. Supprime les emojis
7. Conserve le tutoiement et le ton chaleureux
8. Le texte doit sonner comme une conversation naturelle, pas comme un document structuré
9. Ne change PAS le sens du message — uniquement sa présentation pour l'oral
10. Retourne UNIQUEMENT le texte oralisé, sans introduction, sans commentaire, sans guillemets autour''';
}

/// Entrée du cache avec timestamp (pour debug).
class _CacheEntry {
  final String value;
  final DateTime createdAt;
  _CacheEntry(this.value) : createdAt = DateTime.now();
}
