import 'package:just_audio/just_audio.dart';

/// Implémentation mobile (just_audio) du factory AudioPlayer.
Object? createPlayer() => AudioPlayer();

Future<void> setPlayerFilePath(Object player, String path) async {
  await (player as AudioPlayer).setFilePath(path);
}

Future<void> playPlayer(Object player) async {
  await (player as AudioPlayer).play();
}

Future<void> stopPlayer(Object player) async {
  await (player as AudioPlayer).stop();
}

Future<void> disposePlayer(Object player) async {
  await (player as AudioPlayer).dispose();
}

Future<void> waitForPlayerCompletion(Object player) async {
  await (player as AudioPlayer).processingStateStream
      .firstWhere((state) => state == ProcessingState.completed || state == ProcessingState.idle);
}