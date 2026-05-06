import 'package:flutter/foundation.dart';
import 'tts_emotion.dart';

/// Stub EdgeTtsService pour web — Edge TTS n'est pas disponible sur web
/// car il nécessite WebSocket + écriture de fichiers locaux.
/// Sur web, on utilise flutter_tts (via Web SpeechSynthesis).
class EdgeTtsService {
  static const defaultVoice = 'fr-FR-HenriNeural';
  static const frVoices = <String>[];

  String _voice = defaultVoice;
  double _rate = 1.0;
  double _pitch = 1.0;

  void setVoice(String voice) => _voice = voice;
  void setRate(double rate) => _rate = rate;
  void setPitch(double pitch) => _pitch = pitch;

  Future<String> synthesize(String text) async {
    throw UnsupportedError('Edge TTS is not available on web');
  }

  static Future<bool> isAvailable() async {
    debugPrint('[EdgeTtsService] Not available on web platform');
    return false;
  }
}