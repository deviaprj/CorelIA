import 'package:flutter/foundation.dart';

/// Stub web du cache TTS — Edge TTS n'est pas disponible sur web,
/// donc le cache n'est pas nécessaire. flutter_tts n'utilise pas de fichiers.
class TtsCacheService {
  static final TtsCacheService _instance = TtsCacheService._();
  factory TtsCacheService() => _instance;
  TtsCacheService._();

  Future<void> init() async {
    debugPrint('[TtsCache] Non disponible sur web');
  }

  Future<String?> get(String text, {required String voice, required double rate, required double pitch, String format = 'audio-24khz-48kbitrate-mono-mp3'}) async => null;

  Future<String?> put(String text, String sourcePath, {required String voice, required double rate, required double pitch, String format = 'audio-24khz-48kbitrate-mono-mp3'}) async => null;

  Future<void> clear() async {}

  Future<int> get size async => 0;
}