import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';

/// Voix TTS OpenRouter disponibles.
enum TtsVoice { nova, shimmer, alloy, echo, fable, onyx }

/// Mapping émotion → voix OpenRouter.
const emotionVoiceMap = <String, TtsVoice>{
  'neutral': TtsVoice.nova,
  'joyful': TtsVoice.shimmer,
  'friendly': TtsVoice.shimmer,
  'cheerful': TtsVoice.shimmer,
  'excited': TtsVoice.fable,
  'serious': TtsVoice.echo,
  'sad': TtsVoice.onyx,
};

/// Service TTS via OpenRouter (gpt-4o-mini-tts / kokoro-82m).
/// Retourne des bytes audio MP3.
class OpenRouterTtsService {
  static final _httpClient = http.Client();

  /// Synthétise du texte en audio via OpenRouter TTS.
  /// Fallback : gpt-4o-mini-tts → kokoro-82m → null.
  static Future<Uint8List?> synthesize(
    String text, {
    TtsVoice voice = TtsVoice.nova,
    double speed = 1.0,
  }) async {
    final apiKey = AppConstants.openRouterApiKey;
    if (apiKey.isEmpty) return null;

    // Essayer le modèle principal
    final result = await _callTtsApi(
      model: AppConstants.ttsModel,
      text: text,
      voice: voice,
      speed: speed,
      apiKey: apiKey,
    );
    if (result != null) return result;

    // Fallback kokoro-82m
    debugPrint('[OpenRouterTTS] gpt-4o-mini-tts échoué, fallback kokoro-82m');
    return _callTtsApi(
      model: AppConstants.ttsModelFallback,
      text: text,
      voice: voice,
      speed: speed,
      apiKey: apiKey,
    );
  }

  static Future<Uint8List?> _callTtsApi({
    required String model,
    required String text,
    required TtsVoice voice,
    required double speed,
    required String apiKey,
  }) async {
    final body = _buildBody(model: model, text: text, voice: voice, speed: speed);
    final uri = Uri.parse(AppConstants.openRouterTtsUrl);

    try {
      final request = http.Request('POST', uri)
        ..headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        })
        ..body = body;

      final response = await _httpClient.send(request);
      if (response.statusCode == 200) {
        final bytes = await response.stream.toBytes();
        debugPrint('[OpenRouterTTS] $model OK — ${bytes.length} bytes');
        return Uint8List.fromList(bytes);
      }

      final errBody = await response.stream.bytesToString();
      debugPrint('[OpenRouterTTS] $model error ${response.statusCode}: $errBody');
      return null;
    } catch (e) {
      debugPrint('[OpenRouterTTS] $model exception: $e');
      return null;
    }
  }

  static String _buildBody({
    required String model,
    required String text,
    required TtsVoice voice,
    required double speed,
  }) {
    // Limiter la longueur du texte (les API TTS ont des limites)
    final truncated = text.length > 4096 ? text.substring(0, 4096) : text;
    return '{"model":"$model","input":${_escapeJson(truncated)},'
        '"voice":"${voice.name}","speed":$speed,"response_format":"mp3"}';
  }

  static String _escapeJson(String s) {
    return '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n').replaceAll('\r', '\\r').replaceAll('\t', '\\t')}"';
  }

  /// Vérifie si le service est disponible (clé API présente).
  static bool get isAvailable => AppConstants.openRouterApiKey.isNotEmpty;
}