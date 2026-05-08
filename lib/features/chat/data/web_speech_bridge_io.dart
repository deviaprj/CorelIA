import 'package:flutter/foundation.dart';

/// Bridge vocal web — stub mobile (pas de Web Speech API sur iOS/Android).
/// Le mobile utilise speech_to_text + flutter_tts directement.
class WebSpeechBridge {
  bool get isAvailable => false;

  Future<void> startListening(String lang) async {
    debugPrint('[WebSpeechBridge] STT non disponible sur mobile');
  }

  Future<void> stopListening() async {}

  Stream<String> get onResult => const Stream.empty();
  Stream<bool> get onResultIsFinal => const Stream.empty();
  Stream<void> get onEnd => const Stream.empty();
  Stream<String> get onError => const Stream.empty();

  Future<void> speak(String text, {String emotion = 'neutral'}) async {
    debugPrint('[WebSpeechBridge] TTS non disponible sur mobile');
  }

  Future<void> stopSpeaking() async {}

  Stream<void> get onSpeakEnd => const Stream.empty();

  void dispose() {}
}