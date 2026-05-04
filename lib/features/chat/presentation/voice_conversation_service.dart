import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'chat_notifier.dart';
import 'voice_service.dart';

/// Etat du mode conversation vocale mains-libres.
enum VoiceConversationState {
  idle,
  listening,
  processingStt,
  thinking,
  speaking,
  error,
}

class VoiceConversationStatus {
  final VoiceConversationState state;
  final String? transcript;
  final String? error;

  const VoiceConversationStatus({
    this.state = VoiceConversationState.idle,
    this.transcript,
    this.error,
  });

  VoiceConversationStatus copyWith({
    VoiceConversationState? state,
    String? transcript,
    String? error,
  }) =>
      VoiceConversationStatus(
        state: state ?? this.state,
        transcript: transcript ?? this.transcript,
        error: error,
      );
}

/// Service de conversation vocale mains-libres — 100% autonome et natif.
///
/// Flux complet autonome :
/// 1. LISTENING — speech_to_text natif avec VAD (pauseFor = silence detection)
/// 2. THINKING — envoi automatique au ChatNotifier
/// 3. SPEAKING — TTS naturel quand la reponse IA arrive (detectee via messagesStream)
/// 4. Boucle continue tant que l'utilisateur parle
///
/// Aucun appel backend — tout est natif : speech_to_text + flutter_tts.
class VoiceConversationNotifier
    extends FamilyNotifier<VoiceConversationStatus, String> {
  late final VoiceServiceNotifier _voice;
  bool _isActive = false;
  String? _pendingTranscript;

  // Delais constants pour éviter les magic numbers
  static const _pollInterval = Duration(milliseconds: 150);
  static const _sttFinalWait = Duration(milliseconds: 100);
  static const _sttMaxWait = 30;
  static const _ttsPollInterval = Duration(milliseconds: 300);
  static const _postTtsGuard = Duration(milliseconds: 500);
  static const _stopDelay = Duration(milliseconds: 200);

  @override
  VoiceConversationStatus build(String conversationId) {
    _voice = ref.read(voiceServiceProvider.notifier);

    // Ecouter les messages pour detecter la reponse IA automatiquement
    ref.listen(messagesStreamProvider(conversationId), (prev, next) {
      if (!_isActive || !next.hasValue) return;
      final messages = next.value!;
      if (messages.isEmpty) return;

      final lastMsg = messages.last;
      // Si c'est un message assistant final (pas streaming) et qu'on attend une reponse
      if (lastMsg.isAssistant &&
          !lastMsg.isStreaming &&
          lastMsg.content.isNotEmpty &&
          state.state == VoiceConversationState.thinking &&
          _pendingTranscript != null) {
        _pendingTranscript = null;
        _speakResponseAndLoop(lastMsg.content);
      }
    });

    ref.onDispose(() {
      _isActive = false;
      _voice.stopListening();
      _voice.stopSpeaking();
    });

    return const VoiceConversationStatus();
  }

  /// Demarre une boucle conversation vocale mains-libres.
  Future<void> startConversation() async {
    _isActive = true;

    while (_isActive) {
      // 1. LISTENING — STT natif avec VAD
      state = const VoiceConversationStatus(
        state: VoiceConversationState.listening,
      );
      final transcript = await _listenWithVad();

      // Si transcript vide ou arret utilisateur
      if (transcript == null || transcript.isEmpty || !_isActive) {
        if (!_isActive) break;
        // Si arret manuel, quitter directement
        continue;
      }

      _pendingTranscript = transcript;

      // 2. THINKING — envoi au chat
      state = VoiceConversationStatus(
        state: VoiceConversationState.thinking,
        transcript: transcript,
      );

      try {
        final chatNotifier =
            ref.read(chatNotifierProvider(arg).notifier);
        await chatNotifier.sendMessage(transcript);
      } catch (e) {
        debugPrint('[VoiceConversation] Erreur envoi chat : $e');
        state = VoiceConversationStatus(
          state: VoiceConversationState.error,
          error: e.toString(),
          transcript: transcript,
        );
        break;
      }

      // 3. Attendre que ref.listen detecte la reponse IA et passe a speaking
      while (_isActive && state.state == VoiceConversationState.thinking) {
        await Future<void>.delayed(_ttsPollInterval);
      }

      if (!_isActive) break;
      if (state.state == VoiceConversationState.error) break;

      // 4. Attendre explicitement la fin du TTS avant de relancer l'ecoute
      while (_isActive && state.state == VoiceConversationState.speaking) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      if (!_isActive) break;

      // Boucle continue - on retourne au etat listening
    }

    _reset();
  }

  /// Lit la reponse IA et relance la boucle.
  Future<void> _speakResponseAndLoop(String text) async {
    if (!_isActive) return;

    // Couper explicitement le micro avant de parler
    await _voice.stopListening();

    state = state.copyWith(state: VoiceConversationState.speaking);

    try {
      await _voice.speak(text);
      // Attendre la fin de la lecture TTS
      while (_voice.state.isSpeaking && _isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } catch (e) {
      debugPrint('[VoiceConversation] TTS erreur : $e');
    }

    // Pause de garde apres le TTS pour eviter que le micro ne capte
    // le son du haut-parleur (echo)
    if (_isActive) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Ecoute avec VAD (Voice Activity Detection) natif.
  Future<String?> _listenWithVad() async {
    final ok = await _voice.ensureInitialized();
    if (!ok) {
      debugPrint('[VoiceConversation] STT natif non disponible');
      return null;
    }

    // Reset du transcript avant de commencer
    _voice.state = VoiceState(transcript: '');
    await _voice.startListening();

    // Poll temps reel pour mettre a jour le transcript dans l'UI
    while (_voice.state.isListening && _isActive) {
      final newTranscript = _voice.state.transcript;
      if (newTranscript != state.transcript) {
        state = state.copyWith(transcript: newTranscript);
      }
      await Future<void>.delayed(_pollInterval);
    }

    // Attendre que le STT soit vraiment termine
    for (var i = 0; i < _sttMaxWait; i++) {
      if (!_voice.state.isListening || !_isActive) break;
      await Future<void>.delayed(_sttFinalWait);
    }

    // Delai supplementaire pour stabiliser le transcript final
    await Future<void>.delayed(_postTtsGuard);

    final finalTranscript = _voice.state.transcript;
    // Ne pas changer le state si on a ete arrete manuellement
    if (_isActive) {
      state = state.copyWith(
        transcript: finalTranscript,
        state: VoiceConversationState.processingStt,
      );
    }

    return finalTranscript.isEmpty ? null : finalTranscript;
  }

  /// Arrete immediatement la conversation vocale.
  Future<void> stop() async {
    _isActive = false;
    _pendingTranscript = null;
    await _voice.stopListening();
    await _voice.stopSpeaking();
    state = const VoiceConversationStatus(state: VoiceConversationState.idle);
    await Future<void>.delayed(_stopDelay);
  }

  /// Toggle pour reactivuer le mode vocal apres un arret
  Future<void> toggle() async {
    if (_isActive) {
      await stop();
    } else {
      await startConversation();
    }
  }

  void _reset() {
    state = const VoiceConversationStatus();
  }
}

final voiceConversationProvider = NotifierProviderFamily<
    VoiceConversationNotifier, VoiceConversationStatus, String>(
  VoiceConversationNotifier.new,
);
