import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/constants.dart';

/// Service STT fallback utilisant l'API Whisper (OpenAI-compatible).
///
/// Utilisé quand speech_to_text natif est indisponible ou échoue.
/// Enregistre un fichier audio WAV via le package `record`,
/// puis l'envoie à l'API DeepSeek pour transcription.
///
/// Uniquement disponible sur mobile (nécessite dart:io + enregistrement fichier).
class WhisperSttService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentRecordingPath;
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  bool get isAvailable => AppConstants.deepSeekApiKey.isNotEmpty;

  /// Démarre l'enregistrement audio.
  Future<bool> startRecording() async {
    if (_isRecording) return true;
    if (!isAvailable) {
      debugPrint('[WhisperStt] Pas de clé API disponible');
      return false;
    }

    try {
      if (!await _recorder.hasPermission()) {
        debugPrint('[WhisperStt] Permission micro refusée');
        return false;
      }

      final tempDir = await getTemporaryDirectory();
      _currentRecordingPath =
          '${tempDir.path}/whisper_stt_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 128000,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      debugPrint('[WhisperStt] Enregistrement démarré');
      return true;
    } catch (e) {
      debugPrint('[WhisperStt] Erreur démarrage enregistrement : $e');
      _isRecording = false;
      return false;
    }
  }

  /// Arrête l'enregistrement et retourne le chemin du fichier audio.
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      final path = await _recorder.stop();
      _isRecording = false;
      debugPrint('[WhisperStt] Enregistrement arrêté: $path');
      return path;
    } catch (e) {
      debugPrint('[WhisperStt] Erreur arrêt enregistrement : $e');
      _isRecording = false;
      return null;
    }
  }

  /// Transcrit le fichier audio via l'API Whisper (DeepSeek compatible OpenAI).
  Future<String> transcribe({String language = 'fr'}) async {
    final audioPath = _currentRecordingPath;
    if (audioPath == null) throw StateError('Aucun fichier audio à transcrire');

    final audioFile = File(audioPath);
    if (!await audioFile.exists()) {
      throw StateError('Fichier audio introuvable: $audioPath');
    }

    try {
      return await _callWhisperApi(audioPath, language);
    } finally {
      try {
        if (await audioFile.exists()) await audioFile.delete();
      } catch (_) {}
      _currentRecordingPath = null;
    }
  }

  /// Appel à l'API Whisper via multipart HTTP.
  Future<String> _callWhisperApi(String audioPath, String language) async {
    final apiKey = AppConstants.deepSeekApiKey;
    if (apiKey.isEmpty) {
      throw StateError('Clé API DeepSeek non configurée');
    }

    final audioFile = File(audioPath);
    final audioBytes = await audioFile.readAsBytes();
    final fileName = audioPath.split('/').last;

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.deepseek.com/v1/audio/transcriptions'),
    );

    request.headers['Authorization'] = 'Bearer $apiKey';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      audioBytes,
      filename: fileName,
    ));
    request.fields['model'] = 'whisper-1';
    request.fields['language'] = language;

    try {
      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode != 200) {
        debugPrint('[WhisperStt] API error ${streamedResponse.statusCode}: $responseBody');
        throw StateError('Whisper API error: ${streamedResponse.statusCode}');
      }

      // Réponse JSON : {"text": "transcription"}
      final textMatch = RegExp(r'"text"\s*:\s*"((?:[^"\\]|\\.)*)"')
          .firstMatch(responseBody);
      if (textMatch != null) {
        // Unescape JSON string
        var text = textMatch.group(1) ?? '';
        text = text
            .replaceAll(r'\"', '"')
            .replaceAll(r'\\', '\\')
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\t', '\t');
        return text.trim();
      }
      debugPrint('[WhisperStt] Réponse inattendue: $responseBody');
      return responseBody.trim();
    } catch (e) {
      debugPrint('[WhisperStt] Erreur API : $e');
      rethrow;
    }
  }

  /// Annule l'enregistrement en cours.
  Future<void> cancel() async {
    if (!_isRecording) return;
    try {
      await _recorder.stop();
      _isRecording = false;
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) await file.delete();
        _currentRecordingPath = null;
      }
    } catch (e) {
      debugPrint('[WhisperStt] Cancel error: $e');
      _isRecording = false;
    }
  }

  void dispose() {
    _recorder.dispose();
  }
}