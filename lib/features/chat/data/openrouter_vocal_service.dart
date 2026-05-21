import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';
import 'ai_client.dart';
import 'openrouter_tts_service.dart';

/// OpenRouter Vocal Service
///
/// Encapsule le routage intelligent LLM + TTS pour les conversations vocales.
///
/// Strategie LLM :
///   - useJovial=true  -> arcee/trinity (gratuit, personnalite joyeuse)
///   - useJovial=false -> neversleep/ring-2.6-1t (gratuit, ultra-rapide)
///   - Echec -> deepseek/deepseek-r1:free (gratuit, naturel)
///   - Echec -> openai/gpt-4o-mini (payant, fiable)
///
/// Strategie TTS :
///   - openai/gpt-4o-mini-tts (voix nova/shimmer) ->
///   - sillytavern/kokoro-82m (fallback gratuit)
///   - flutter_tts (fallback ultime natif)
///
/// Parametres vocaux recommandes :
///   - temperature = 0.95  (creativite controlee)
///   - top_p = 0.95
///   - frequency_penalty = 0.2
///   - TTS speed = 1.0
///   - TTS voice = nova (joviale) | shimmer (enthousiaste)
class OpenRouterVocalService {
  static final _httpClient = http.Client();

  // Parametres LLM vocaux
  static const double _vocalTemperature = 0.95;
  static const double _vocalTopP = 0.95;
  static const double _vocalFrequencyPenalty = 0.2;
  static const int _vocalMaxTokens = 2048;

  // Parametres TTS vocaux
  static const double _vocalTtsSpeed = 1.0;

  // Chaines de fallback
  static const List<String> _jovialChain = [
    AppConstants.arceeTrinityFree,
    AppConstants.ringFastFree,
    AppConstants.deepseekR1Free,
    AppConstants.gpt4oMini,
  ];

  static const List<String> _fastChain = [
    AppConstants.ringFastFree,
    AppConstants.arceeTrinityFree,
    AppConstants.deepseekR1Free,
    AppConstants.gpt4oMini,
  ];

  static List<String> _chainFor({required bool useJovial}) =>
      useJovial ? _jovialChain : _fastChain;

  /// LLM : genere une reponse texte pour la conversation vocale
  ///
  /// [prompt]        : message utilisateur
  /// [history]       : historique au format OpenAI [{role, content}]
  /// [useJovial]     : true -> trinity (joyeux), false -> ring (rapide)
  /// [systemPrompt]  : prompt systeme (si null, prompt jovial par defaut)
  ///
  /// Retourne le texte genere ou leve [AiException] si tous les modeles
  /// echouent.
  static Future<String> getVocalResponse(
    String prompt, {
    List<Map<String, dynamic>> history = const [],
    bool useJovial = true,
    String? systemPrompt,
  }) async {
    final apiKey = AppConstants.openRouterApiKey;
    if (apiKey.isEmpty) {
      throw const AiException('Cle API OpenRouter manquante');
    }

    const defaultSystem =
        "MODE VOCAL ACTIF — Reponds comme un ami au telephone : "
        "jovial, naturel, concis (2-3 phrases max), pas de listes, pas de markdown. "
        "Tutoie, sois chaleureux et dynamique. Pas de 'En tant qu\'IA' ni d\'excuses inutiles. "
        "Va droit au but avec le sourire.";

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt ?? defaultSystem},
      ...history,
      {'role': 'user', 'content': prompt},
    ];

    final chain = _chainFor(useJovial: useJovial);
    String? lastError;

    for (final modelId in chain) {
      try {
        debugPrint('[OpenRouterVocal] LLM attempt: $modelId (jovial=$useJovial)');
        final text = await _callChat(
          modelId: modelId,
          messages: messages,
          apiKey: apiKey,
        );
        if (text.isNotEmpty) {
          debugPrint('[OpenRouterVocal] LLM OK: $modelId');
          return text;
        }
      } on AiException catch (e) {
        debugPrint('[OpenRouterVocal] LLM fail $modelId: $e');
        lastError = e.message;
        if (e.statusCode == 429) continue;
        continue;
      } catch (e) {
        debugPrint('[OpenRouterVocal] LLM error $modelId: $e');
        lastError = e.toString();
        continue;
      }
    }

    throw AiException(
      'Tous les modeles vocaux ont echoue. Dernier erreur: ${lastError ?? "inconnue"}',
    );
  }

  static Future<String> _callChat({
    required String modelId,
    required List<Map<String, dynamic>> messages,
    required String apiKey,
  }) async {
    final body = jsonEncode({
      'model': modelId,
      'messages': messages,
      'temperature': _vocalTemperature,
      'top_p': _vocalTopP,
      'frequency_penalty': _vocalFrequencyPenalty,
      'max_tokens': _vocalMaxTokens,
    });

    final request = http.Request(
      'POST',
      Uri.parse(AppConstants.openRouterBaseUrl),
    )
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': AppConstants.appWebUrl,
        'X-Title': AppConstants.appName,
      })
      ..body = body;

    final response = await _httpClient.send(request);
    if (response.statusCode == 429) {
      throw const AiException('Rate limit', statusCode: 429);
    }
    if (response.statusCode != 200) {
      final err = await response.stream.bytesToString();
      throw AiException('HTTP ${response.statusCode}: $err');
    }

    final respBody = await response.stream.bytesToString();
    final json = jsonDecode(respBody) as Map<String, dynamic>;
    final content = (json['choices'] as List?)
        ?.firstOrNull?['message']?['content'] as String?;
    if (content == null || content.isEmpty) {
      throw const AiException('Reponse vide');
    }
    return content;
  }

  /// TTS : synthetise du texte en audio MP3
  ///
  /// [text]   : texte a synthetiser (tronque a 4096 caracteres)
  /// [voice]  : voix OpenRouter (defaut: nova — joviale et naturelle)
  /// [speed]  : vitesse (defaut: 1.0)
  ///
  /// Retourne les bytes audio MP3 ou null si tous les TTS echouent.
  static Future<Uint8List?> synthesizeVocal(
    String text, {
    TtsVoice voice = TtsVoice.nova,
    double speed = _vocalTtsSpeed,
  }) async {
    return OpenRouterTtsService.synthesize(
      text,
      voice: voice,
      speed: speed,
    );
  }

  /// Helper : voix recommandee selon l'emotion
  static TtsVoice voiceForEmotion(String emotionName) {
    return emotionVoiceMap[emotionName.toLowerCase()] ?? TtsVoice.nova;
  }

  /// Helper : voix recommandee selon le mode jovial
  static TtsVoice defaultVoice({bool useJovial = true}) =>
      useJovial ? TtsVoice.shimmer : TtsVoice.nova;

  static void dispose() {
    _httpClient.close();
  }
}
