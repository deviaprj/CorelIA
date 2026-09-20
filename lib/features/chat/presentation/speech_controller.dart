import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tts_service.dart';

/// Identifiant du message en cours de lecture à voix haute (`null` si aucun).
final speechProvider =
    NotifierProvider<SpeechNotifier, String?>(SpeechNotifier.new);

/// Pilote la lecture à voix haute : une seule réponse lue à la fois.
class SpeechNotifier extends Notifier<String?> {
  TtsService? _service;

  @override
  String? build() {
    ref.onDispose(() {
      _service?.stop();
      _service = null;
    });
    return null;
  }

  /// Lance la lecture de [text], ou l'arrête si ce message est déjà lu.
  Future<void> toggle(String messageId, String text) async {
    if (state == messageId) {
      await stop();
      return;
    }

    var service = _service;
    if (service == null) {
      service = TtsService();
      service.onDone = _handleDone;
      _service = service;
    }

    state = messageId;
    await service.speak(text);
  }

  /// Interrompt la lecture en cours.
  Future<void> stop() async {
    await _service?.stop();
    if (state != null) state = null;
  }

  void _handleDone() {
    if (state != null) state = null;
  }
}
