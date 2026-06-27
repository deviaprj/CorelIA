import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/api/api_config.dart';
import '../../../core/constants.dart';

/// Service TTS via OmniVoice backend (k2-fsa/OmniVoice).
///
/// OmniVoice is a state-of-the-art multilingual zero-shot TTS model
/// supporting 646 languages (French: 23 675h training), voice cloning,
/// voice design, and non-verbal tags ([laughter], [sigh], ...).
///
/// This service acts as an HTTP client to the backend `/voice/omnivoice`
/// endpoint. The backend handles GPU inference (CUDA/MPS/XPU/CPU).
class OmniVoiceTtsService {
  static final _httpClient = http.Client();

  /// Backend endpoint for OmniVoice TTS synthesis.
  static String get _endpoint => '${ApiConfig.baseUrl}/voice/omnivoice';

  /// Stream endpoint for SSE audio chunks.
  static String get _streamEndpoint =>
      '${ApiConfig.baseUrl}/voice/omnivoice/stream';

  /// Voice design preview endpoint.
  static String get _designEndpoint => '${ApiConfig.baseUrl}/voice/design';

  /// Check if OmniVoice backend is reachable.
  static Future<bool> isAvailable() async {
    try {
      final response = await _httpClient
          .get(Uri.parse('${ApiConfig.baseUrl}/voice/status'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['available'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('[OmniVoiceTTS] Backend unavailable: $e');
      return false;
    }
  }

  /// Synthesize speech from text via OmniVoice backend.
  ///
  /// Returns WAV audio bytes on success, null on failure.
  ///
  /// [text] — text to synthesize (max 5000 chars)
  /// [mode] — "auto", "design", or "clone"
  /// [instruct] — voice design string, e.g. "female, young adult, high pitch"
  /// [emotion] — CorelIA emotion name (neutral, joyful, sad, ...)
  /// [isPro] — Pro users get quality mode (num_step=32), free get fast (16)
  /// [speed] — speed factor (0.5-2.0)
  static Future<Uint8List?> synthesize(
    String text, {
    String mode = 'auto',
    String? instruct,
    String? emotion,
    bool isPro = false,
    double speed = 1.0,
    double? duration,
  }) async {
    final body = <String, dynamic>{
      'text': text.length > 5000 ? text.substring(0, 5000) : text,
      'mode': mode,
      'quality': isPro ? 'hq' : 'fast',
      'speed': speed,
      'is_pro': isPro,
    };

    if (instruct != null && instruct.isNotEmpty) {
      body['instruct'] = instruct;
    }
    if (emotion != null && emotion.isNotEmpty) {
      body['emotion'] = emotion;
    }
    if (duration != null) {
      body['duration'] = duration;
    }

    try {
      final response = await _httpClient
          .post(
            Uri.parse(_endpoint),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final durationHeader = response.headers['x-audio-duration'];
        debugPrint(
          '[OmniVoiceTTS] OK — ${bytes.length} bytes, '
          '${durationHeader ?? "?"}s, mode=$mode',
        );
        return Uint8List.fromList(bytes);
      }

      debugPrint(
        '[OmniVoiceTTS] Error ${response.statusCode}: ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[OmniVoiceTTS] Exception: $e');
      return null;
    }
  }

  /// Stream audio chunks via SSE from the backend.
  ///
  /// Yields base64-encoded WAV chunks as they arrive.
  /// Useful for reducing Time-To-First-Audio on mobile.
  static Stream<String> synthesizeStream(
    String text, {
    String mode = 'auto',
    String? instruct,
    String? emotion,
    bool isPro = false,
    double speed = 1.0,
  }) async* {
    final body = <String, dynamic>{
      'text': text.length > 5000 ? text.substring(0, 5000) : text,
      'mode': mode,
      'quality': isPro ? 'hq' : 'fast',
      'speed': speed,
      'is_pro': isPro,
    };

    if (instruct != null && instruct.isNotEmpty) {
      body['instruct'] = instruct;
    }
    if (emotion != null && emotion.isNotEmpty) {
      body['emotion'] = emotion;
    }

    try {
      final request = http.Request('POST', Uri.parse(_streamEndpoint))
        ..headers.addAll(_headers)
        ..body = jsonEncode(body);

      final response = await _httpClient.send(request);

      if (response.statusCode == 200) {
        await for (final chunk in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (chunk.startsWith('data: ')) {
            final data = chunk.substring(6);
            try {
              final event = jsonDecode(data) as Map<String, dynamic>;
              if (event['type'] == 'chunk') {
                yield event['audio'] as String;
              } else if (event['type'] == 'error') {
                debugPrint(
                  '[OmniVoiceTTS] Stream error: ${event['message']}',
                );
                return;
              }
            } catch (_) {}
          }
        }
      } else {
        debugPrint(
          '[OmniVoiceTTS] Stream error ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[OmniVoiceTTS] Stream exception: $e');
    }
  }

  /// Build a voice design `instruct` string from individual attributes.
  ///
  /// Returns comma-separated attributes, e.g. "female, young adult, high pitch".
  static String buildInstruct({
    String? gender, // "male", "female"
    String? age, // "child", "teenager", "young adult", "middle-aged", "elderly"
    String? pitch, // "very low pitch", "low pitch", "moderate pitch", "high pitch", "very high pitch"
    String? accent, // "american accent", "british accent", "french accent", ...
    String? style, // "whisper"
  }) {
    final parts = <String>[];
    if (gender != null && gender.isNotEmpty) parts.add(gender);
    if (age != null && age.isNotEmpty) parts.add(age);
    if (pitch != null && pitch.isNotEmpty) parts.add(pitch);
    if (accent != null && accent.isNotEmpty) parts.add(accent);
    if (style != null && style.isNotEmpty) parts.add(style);
    return parts.join(', ');
  }

  /// CorelIA emotion → OmniVoice instruct (client-side mirror of backend map).
  static String? emotionToInstruct(String emotion) {
    return switch (emotion) {
      'joyful' || 'cheerful' => 'female, young adult, high pitch',
      'sad' => 'low pitch',
      'serious' => 'male, middle-aged, moderate pitch',
      'excited' => 'female, young adult, very high pitch',
      'friendly' => 'female, young adult, moderate pitch',
      'neutral' => 'moderate pitch',
      _ => null,
    };
  }

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (AppConstants.backendApiKey.isNotEmpty)
      'X-API-Key': AppConstants.backendApiKey,
  };
}
