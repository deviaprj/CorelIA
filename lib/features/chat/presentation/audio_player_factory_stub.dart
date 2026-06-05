import 'package:flutter/foundation.dart';

/// Stub web du factory AudioPlayer — juste_audio n'est pas utilisé sur web.
/// Edge TTS n'est pas supporté sur web, donc ce stub ne sera jamais appelé en pratique.
Object? createPlayer() {
  debugPrint('[AudioPlayerFactory] Audio player not available on web');
  return null;
}

Future<void> setPlayerFilePath(Object player, String path) async {
  throw UnsupportedError('Audio player not available on web');
}

Future<void> playPlayer(Object player) async {
  throw UnsupportedError('Audio player not available on web');
}

Future<void> stopPlayer(Object player) async {}

Future<void> disposePlayer(Object player) async {}

Future<void> waitForPlayerCompletion(Object player) async {
  throw UnsupportedError('Audio player not available on web');
}