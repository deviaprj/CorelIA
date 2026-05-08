import 'package:flutter/foundation.dart';

/// Stub web — Whisper STT non disponible sur web/extension.
/// Sur web, on utilise WebSpeechBridge (Web Speech API) à la place.
class WhisperSttService {
  bool get isRecording => false;
  bool get isAvailable => false;

  Future<bool> startRecording() async {
    debugPrint('[WhisperStt] Non disponible sur web');
    return false;
  }

  Future<String?> stopRecording() async => null;

  Future<String> transcribe({String language = 'fr'}) async {
    throw UnsupportedError('Whisper STT non disponible sur web');
  }

  Future<void> cancel() async {}

  void dispose() {}
}