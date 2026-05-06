import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Service TTS via Microsoft Edge TTS (gratuit, voix neurales).
///
/// Protocole WebSocket :
/// 1. Connexion wss://speech.platform.bing.com/...edge/v1
/// 2. Envoi config audio (format MP3 24kHz)
/// 3. Envoi SSML avec voix et texte
/// 4. Réception chunks audio (binary frames) → fichier temp → just_audio
class EdgeTtsService {
  static const _wsUrl =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';
  static const _trustedToken = '6A5AA1D4EAFF4E9B37E45D702E9B2A8F';
  static const _uuid = Uuid();

  static const defaultVoice = 'fr-FR-HenriNeural';

  static const frVoices = [
    'fr-FR-HenriNeural',
    'fr-FR-DeniseNeural',
    'fr-FR-AlloyNeural',
    'fr-FR-ClaudeNeural',
    'fr-FR-MichelNeural',
  ];

  String _voice;
  double _rate;
  double _pitch;
  String _outputFormat;

  EdgeTtsService({
    String voice = defaultVoice,
    double rate = 1.0,
    double pitch = 1.0,
    String outputFormat = 'audio-24khz-48kbitrate-mono-mp3',
  })  : _voice = voice,
        _rate = rate.clamp(0.5, 3.0),
        _pitch = pitch.clamp(0.5, 2.0),
        _outputFormat = outputFormat;

  String get voice => _voice;

  void setVoice(String voice) => _voice = voice;
  void setRate(double rate) => _rate = rate.clamp(0.5, 3.0);
  void setPitch(double pitch) => _pitch = pitch.clamp(0.5, 2.0);

  /// Synthétise le texte en audio et retourne le chemin du fichier MP3.
  Future<String> synthesize(String text) async {
    if (text.trim().isEmpty) throw ArgumentError('Text cannot be empty');

    final connectionId = _uuid.v4();
    final requestId = _uuid.v4();
    final uri = Uri.parse(
      '$_wsUrl?TrustedClientToken=$_trustedToken&ConnectionId=$connectionId',
    );

    final channel = WebSocketChannel.connect(uri);

    try {
      // 1. Configuration audio
      final configMsg =
          'Content-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n'
          '{"context":{"synthesis":{"audio":{"metadataoptions":'
          '{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"true"},'
          '"outputFormat":"$_outputFormat"}}}}';
      channel.sink.add(configMsg);

      // 2. SSML
      final timestamp = DateTime.now().toUtc().toIso8601String();
      final rateStr = _formatProsody(_rate);
      final pitchStr = _formatProsody(_pitch);

      final ssml =
          '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="fr-FR">'
          '<voice name="$_voice">'
          '<prosody rate="$rateStr" pitch="$pitchStr">'
          '${_escapeXml(text)}'
          '</prosody>'
          '</voice></speak>';

      final ssmlMsg =
          'Content-Type:application/ssml+xml\r\nPath:ssml\r\nX-RequestId:$requestId\r\nX-Timestamp:$timestamp\r\n\r\n$ssml';
      channel.sink.add(ssmlMsg);

      // 3. Collecter les chunks audio
      final audioChunks = <int>[];
      var turnEnded = false;

      await for (final msg in channel.stream) {
        if (msg is String) {
          // Message texte — chercher Path:turn.end
          if (msg.contains('Path:turn.end')) {
            turnEnded = true;
            break;
          }
          // Les messages Path:audio peuvent aussi venir en texte
          // mais l'audio est généralement en binaire
          if (msg.contains('Path:audio')) {
            final audioData = _extractAudioFromStringMessage(msg);
            if (audioData != null) audioChunks.addAll(audioData);
          }
        } else {
          // Message binaire — c'est l'audio
          final bytes = msg;
          if (bytes is List<int>) {
            // Format binaire Edge TTS :
            // [2 bytes header length (big-endian)][header JSON][audio data]
            if (bytes.length > 2) {
              final headerLen = (bytes[0] << 8) | bytes[1];
              final audioStart = 2 + headerLen;
              if (audioStart < bytes.length) {
                audioChunks.addAll(bytes.sublist(audioStart));
              }
            }
          }
        }
      }

      await channel.sink.close();

      if (!turnEnded && audioChunks.isEmpty) {
        throw StateError('Edge TTS: no audio data received');
      }

      if (audioChunks.isEmpty) {
        throw StateError('Edge TTS: audio chunks empty');
      }

      // 4. Sauvegarder en fichier temporaire
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/edge_tts_${_uuid.v4()}.mp3';
      final file = File(filePath);
      await file.writeAsBytes(Uint8List.fromList(audioChunks));

      return filePath;
    } catch (e) {
      try {
        await channel.sink.close();
      } catch (_) {}
      rethrow;
    }
  }

  /// Extrait l'audio d'un message texte contenant Path:audio.
  /// Format : headers\r\n\r\n[2 bytes header len][header][audio data]
  static List<int>? _extractAudioFromStringMessage(String msg) {
    final separatorIndex = msg.indexOf('\r\n\r\n');
    if (separatorIndex == -1) return null;

    final afterHeader = msg.substring(separatorIndex + 4);
    if (afterHeader.isEmpty) return null;

    final codeUnits = afterHeader.codeUnits;
    if (codeUnits.length < 2) return null;

    final headerLen = (codeUnits[0] << 8) | codeUnits[1];
    final audioStart = 2 + headerLen;
    if (audioStart >= codeUnits.length) return null;

    return codeUnits.sublist(audioStart);
  }

  static String _formatProsody(double value) {
    if (value == 1.0) return '+0%';
    final percent = ((value - 1.0) * 100).round();
    return '${percent >= 0 ? '+' : ''}$percent%';
  }

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Teste si le service Edge TTS est disponible.
  static Future<bool> isAvailable() async {
    try {
      final service = EdgeTtsService();
      final filePath = await service.synthesize('Test');
      final file = File(filePath);
      final exists = await file.exists();
      if (exists) {
        final size = await file.length();
        await file.delete();
        return size > 100; // Un fichier MP3 valide fait au moins quelques centaines d'octets
      }
      return false;
    } catch (e) {
      debugPrint('[EdgeTtsService] Availability check failed: $e');
      return false;
    }
  }
}

/// Émotions mappées à des voix et paramètres Edge TTS.
enum TtsEmotion {
  neutral,
  joyful,
  sad,
  serious,
  excited,
  cheerful,
  friendly,
}

/// Configuration TTS pour une émotion donnée.
class EmotionTtsConfig {
  final String voice;
  final double rate;
  final double pitch;

  const EmotionTtsConfig({
    required this.voice,
    required this.rate,
    required this.pitch,
  });
}

/// Mapping émotion → configuration Edge TTS.
const emotionTtsConfigs = {
  TtsEmotion.neutral: EmotionTtsConfig(voice: 'fr-FR-HenriNeural', rate: 1.0, pitch: 1.0),
  TtsEmotion.joyful: EmotionTtsConfig(voice: 'fr-FR-HenriNeural', rate: 1.15, pitch: 1.25),
  TtsEmotion.sad: EmotionTtsConfig(voice: 'fr-FR-HenriNeural', rate: 0.85, pitch: 0.85),
  TtsEmotion.serious: EmotionTtsConfig(voice: 'fr-FR-HenriNeural', rate: 0.9, pitch: 0.9),
  TtsEmotion.excited: EmotionTtsConfig(voice: 'fr-FR-HenriNeural', rate: 1.25, pitch: 1.35),
  TtsEmotion.cheerful: EmotionTtsConfig(voice: 'fr-FR-DeniseNeural', rate: 1.1, pitch: 1.2),
  TtsEmotion.friendly: EmotionTtsConfig(voice: 'fr-FR-DeniseNeural', rate: 1.05, pitch: 1.1),
};