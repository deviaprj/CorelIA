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
/// 4. IDLE — retour automatique pour conversation continue
///
/// Aucun appel backend — tout est natif : speech_to_text + flutter_tts.
class VoiceConversationNotifier
    extends FamilyNotifier<VoiceConversationStatus, String> {
  late final VoiceServiceNotifier _voice;
  bool _isActive = false;
  String? _pendingTranscript;

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
    if (_isActive) return;
    _isActive = true;

    while (_isActive) {
      // 1. LISTENING — STT natif avec VAD
      state = const VoiceConversationStatus(
        state: VoiceConversationState.listening,
      );
      final transcript = await _listenWithVad();

      if (transcript == null || transcript.isEmpty || !_isActive) {
        break;
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
      // Timeout de 60s pour la reponse IA
      var attempts = 0;
      while (_isActive &&
             state.state == VoiceConversationState.thinking &&
             attempts < 300) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        attempts++;
      }

      if (!_isActive) break;
      if (state.state == VoiceConversationState.error) break;

      // 4. Apres speaking, retour a idle puis on relance listening
      // _speakResponseAndLoop s'occupe de la transition
    }

    if (_isActive) {
      _reset();
    }
  }

  /// Ecoute avec VAD (Voice Activity Detection) natif.
  ///
  /// Utilise speech_to_text avec pauseFor=2s comme detection de silence.
  /// Transcription temps reel affichee via l'etat.
  Future<String?> _listenWithVad() async {
    final ok = await _voice.ensureInitialized();
    if (!ok) {
      debugPrint('[VoiceConversation] STT natif non disponible');
      return null;
    }

    await _voice.startListening();

    // Poll temps reel pour mettre a jour le transcript dans l'UI
    while (_voice.state.isListening && _isActive) {
      state = state.copyWith(transcript: _voice.state.transcript);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    // Attendre que le STT soit vraiment termine et laisser le temps
    // au dernier resultat final d'arriver avant de relancer quoi que ce soit.
    var waitCount = 0;
    while (_voice.state.isListening && _isActive && waitCount < 20) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    // Delai supplementaire pour stabiliser le transcript final
    await Future<void>.delayed(const Duration(milliseconds: 800));

    final finalTranscript = _voice.state.transcript;
    state = state.copyWith(
      transcript: finalTranscript,
      state: VoiceConversationState.processingStt,
    );

    return finalTranscript.isEmpty ? null : finalTranscript;
  }

  /// Lit la reponse IA et relance la boucle.
  Future<void> _speakResponseAndLoop(String text) async {
    if (!_isActive) return;

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
    // le son du haut-parleur (echo) avant de relancer l'ecoute.
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    if (_isActive) {
      state = state.copyWith(state: VoiceConversationState.idle);
      // La boucle while dans startConversation va relancer listening
    }
  }

  /// Arrete immediatement la conversation vocale.
  void stop() {
    _isActive = false;
    _pendingTranscript = null;
    _voice.stopListening();
    _voice.stopSpeaking();
    _reset();
  }

  void _reset() {
    state = const VoiceConversationStatus();
  }
}

final voiceConversationProvider = NotifierProviderFamily<
    VoiceConversationNotifier, VoiceConversationStatus, String>(
  VoiceConversationNotifier.new,
);
