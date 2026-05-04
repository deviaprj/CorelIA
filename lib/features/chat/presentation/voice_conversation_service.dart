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
    var consecutiveFailures = 0;
    const maxFailures = 3;

    while (_isActive) {
      // 1. LISTENING — STT natif avec VAD
      state = const VoiceConversationStatus(
        state: VoiceConversationState.listening,
      );
      final transcript = await _listenWithVad();

      if (!_isActive) break;

      // Echec ecoute (STT indisponible) — delai + retry
      if (transcript == null) {
        consecutiveFailures++;
        if (consecutiveFailures >= maxFailures) {
          state = VoiceConversationStatus(
            state: VoiceConversationState.error,
            error: 'Microphone non disponible. Verifiez les permissions.',
          );
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        continue;
      }

      // Transcript vide (silence) — on reessaie
      if (transcript.isEmpty) {
        consecutiveFailures = 0;
        continue;
      }

      consecutiveFailures = 0;
      _pendingTranscript = transcript;

      // 2. THINKING — envoi au chat
      state = VoiceConversationStatus(
        state: VoiceConversationState.thinking,
        transcript: transcript,
      );

      try {
        final chatNotifier = ref.read(chatNotifierProvider(arg).notifier);
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

      // 3. Attendre la fin de la reponse IA ET du TTS
      //    La callback ref.listen declenche _speakResponseAndLoop qui
      //    passe le state thinking→speaking→idle (ou error).
      while (_isActive &&
          (state.state == VoiceConversationState.thinking ||
           state.state == VoiceConversationState.speaking)) {
        await Future<void>.delayed(_ttsPollInterval);
      }

      if (!_isActive) break;
      if (state.state == VoiceConversationState.error) break;

      // Retour automatique en haut de boucle → listening
    }

    _reset();
  }

  /// Lit la reponse IA a voix haute puis rend la main.
  Future<void> _speakResponseAndLoop(String text) async {
    if (!_isActive) return;

    // Couper le micro avant de parler
    await _voice.stopListening();

    state = state.copyWith(state: VoiceConversationState.speaking);

    try {
      await _voice.speak(text);
      // Attendre la fin reelle de la lecture TTS
      while (_voice.state.isSpeaking && _isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } catch (e) {
      debugPrint('[VoiceConversation] TTS erreur : $e');
    }

    // Pause de garde anti-echo (le son du haut-parleur vers le micro)
    if (_isActive) {
      await Future<void>.delayed(_postTtsGuard);
    }

    // Signaler a startConversation que la lecture est terminee
    if (_isActive) {
      state = state.copyWith(state: VoiceConversationState.idle);
    }
  }

  /// Ecoute avec VAD (Voice Activity Detection) natif.
  /// Retourne le transcript final, ou null si le STT est indisponible.
  Future<String?> _listenWithVad() async {
    // Toujours arreter l'ecoute precedente avant d'en demarrer une nouvelle
    await _voice.stopListening();

    // startListening() gere tout : permission, creation STT fraiche, init, ecoute
    await _voice.startListening();

    // Si apres startListening() le STT n'est toujours pas dispo, echec
    if (!_voice.state.isAvailable && !_voice.state.isListening) {
      debugPrint('[VoiceConversation] STT non disponible');
      return null;
    }

    // Poll temps reel pour mettre a jour le transcript dans l'UI
    while (_voice.state.isListening && _isActive) {
      final newTranscript = _voice.state.transcript;
      if (newTranscript != state.transcript) {
        state = state.copyWith(transcript: newTranscript);
      }
      await Future<void>.delayed(_pollInterval);
    }

    if (!_isActive) return '';

    // Attendre que le STT soit vraiment termine
    for (var i = 0; i < _sttMaxWait; i++) {
      if (!_voice.state.isListening || !_isActive) break;
      await Future<void>.delayed(_sttFinalWait);
    }

    if (!_isActive) return '';

    // Delai supplementaire pour stabiliser le transcript final
    await Future<void>.delayed(_postTtsGuard);

    final finalTranscript = _voice.state.transcript;
    if (_isActive) {
      state = state.copyWith(
        transcript: finalTranscript,
        state: VoiceConversationState.processingStt,
      );
    }

    return finalTranscript;
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
