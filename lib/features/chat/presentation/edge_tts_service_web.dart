import 'package:flutter/foundation.dart';

/// Stub EdgeTtsService pour web — Edge TTS n'est pas disponible sur web
/// car il nécessite WebSocket + écriture de fichiers locaux.
/// Sur web, on utilise flutter_tts (via Web SpeechSynthesis).
class EdgeTtsService {
  static const defaultVoice = 'fr-FR-HenriNeural';
  static const frVoices = <String>[];

  String _voice = defaultVoice;

  String get voice => _voice;

  void setVoice(String voice) => _voice = voice;
  // setRate/setPitch : stubs no-op sur web — Edge TTS n'est pas disponible
  // (cf. setEmotion). On garde les signatures pour la compat d'interface
  // avec edge_tts_service_io.dart (conditional export).
  void setRate(double rate) {}
  void setPitch(double pitch) {}

  void setEmotion(dynamic emotion) {
    // Stub : pas d'effet sur web
  }

  Future<String> synthesize(String text) async {
    throw UnsupportedError('Edge TTS is not available on web');
  }

  Stream<String?> synthesizeStream(String text) async* {
    throw UnsupportedError('Edge TTS is not available on web');
  }

  static Future<bool> isAvailable() async {
    debugPrint('[EdgeTtsService] Not available on web platform');
    return false;
  }
}