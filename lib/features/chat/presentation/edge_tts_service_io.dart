import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'tts_emotion.dart';

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

  static const _emotionVoices = <TtsEmotion, String>{
    TtsEmotion.neutral: 'fr-FR-HenriNeural',
    TtsEmotion.joyful: 'fr-FR-DeniseNeural',
    TtsEmotion.sad: 'fr-FR-ClaudeNeural',
    TtsEmotion.serious: 'fr-FR-MichelNeural',
    TtsEmotion.excited: 'fr-FR-AlloyNeural',
    TtsEmotion.cheerful: 'fr-FR-DeniseNeural',
    TtsEmotion.friendly: 'fr-FR-HenriNeural',
  };

  void setEmotion(TtsEmotion emotion) {
    final config = edgeEmotionTtsConfigs[emotion] ?? edgeEmotionTtsConfigs[TtsEmotion.neutral]!;
    _voice = _emotionVoices[emotion] ?? defaultVoice;
    _rate = config.rate;
    _pitch = config.pitch;
  }

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

  /// Synthèse incrémentale — retourne un Stream qui émet le chemin du fichier
  /// audio dès que suffisamment de données sont disponibles pour commencer
  /// la lecture. Le fichier est écrit incrémentalement.
  ///
  /// Le premier événement du stream est le chemin du fichier (lecture possible),
  /// le dernier est `null` (synthèse terminée).
  Stream<String?> synthesizeStream(String text) async* {
    if (text.trim().isEmpty) {
      throw ArgumentError('Text cannot be empty');
    }

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
          'Content-Type:application/ssml+xml\r\nPath:ssml\r\nXRequestId:$requestId\r\nXTimestamp:$timestamp\r\n\r\n$ssml';
      channel.sink.add(ssmlMsg);

      // 3. Fichier temporaire pour écriture incrémentale
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/edge_tts_stream_${_uuid.v4()}.mp3';
      final file = File(filePath);
      final sink = file.openWrite();

      var firstChunkWritten = false;
      var totalBytes = 0;

      try {
        await for (final msg in channel.stream) {
          List<int>? audioData;

          if (msg is String) {
            if (msg.contains('Path:turn.end')) {
              // Synthèse terminée
              await sink.flush();
              await sink.close();
              await channel.sink.close();

              if (totalBytes > 0) {
                yield filePath; // Fichier complet et prêt
              }
              yield null; // Signal de fin
              return;
            }
            if (msg.contains('Path:audio')) {
              audioData = _extractAudioFromStringMessage(msg);
            }
          } else {
            final bytes = msg;
            if (bytes is List<int> && bytes.length > 2) {
              final headerLen = (bytes[0] << 8) | bytes[1];
              final audioStart = 2 + headerLen;
              if (audioStart < bytes.length) {
                audioData = bytes.sublist(audioStart);
              }
            }
          }

          if (audioData != null && audioData.isNotEmpty) {
            sink.add(audioData);
            totalBytes += audioData.length;

            // Émettre le chemin du fichier dès qu'on a suffisamment de données
            // pour que le lecteur audio puisse commencer la lecture.
            // MP3 frames need at least ~4KB to start decoding.
            if (!firstChunkWritten && totalBytes >= 4096) {
              await sink.flush();
              firstChunkWritten = true;
              yield filePath; // Fichier partiellement écrit, lecture possible
            }
          }
        }
      } catch (e) {
        await sink.close();
        await channel.sink.close();
        if (await file.exists()) await file.delete();
        rethrow;
      }

      // Si on arrive ici sans turn.end, on finalise quand même
      await sink.flush();
      await sink.close();
      await channel.sink.close();

      if (totalBytes > 0) {
        yield filePath;
      }
      yield null;
    } catch (e) {
      try {
        await channel.sink.close();
      } catch (_) {}
      rethrow;
    }
  }
}