import 'audio_player_factory_stub.dart'
    if (dart.library.io) 'audio_player_factory_mobile.dart';

/// Factory pour créer et manipuler un lecteur audio.
/// Sur mobile : utilise just_audio (AudioPlayer).
/// Sur web : stub (Edge TTS non supporté sur web).
class AudioPlayerFactory {
  static Object? create() => createPlayer();
  static Future<void> setFilePath(Object player, String path) =>
      setPlayerFilePath(player, path);
  static Future<void> play(Object player) => playPlayer(player);
  static Future<void> stop(Object player) => stopPlayer(player);
  static Future<void> dispose(Object player) => disposePlayer(player);
  static Future<void> waitForCompletion(Object player) =>
      waitForPlayerCompletion(player);
}