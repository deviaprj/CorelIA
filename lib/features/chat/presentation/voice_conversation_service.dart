import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'chat_notifier.dart';
import 'tts_emotion.dart';
import 'emotion_parser.dart';
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
  final TtsEmotion emotion;

  const VoiceConversationStatus({
    this.state = VoiceConversationState.idle,
    this.transcript,
    this.error,
    this.emotion = TtsEmotion.neutral,
  });

  VoiceConversationStatus copyWith({
    VoiceConversationState? state,
    String? transcript,
    String? error,
    TtsEmotion? emotion,
  }) =>
      VoiceConversationStatus(
        state: state ?? this.state,
        transcript: transcript ?? this.transcript,
        error: error,
        emotion: emotion ?? this.emotion,
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
/// Support des balises prosodiques : [joyeux], [triste], [sérieux], [excité]
/// L'émotion détectée est exposée via VoiceConversationStatus.emotion
class VoiceConversationNotifier
    extends FamilyNotifier<VoiceConversationStatus, String> {
  late final VoiceServiceNotifier _voice;
  bool _isActive = false;
  String? _pendingTranscript;

  static const _pollInterval = Duration(milliseconds: 150);
  static const _sttFinalWait = Duration(milliseconds: 100);
  static const _sttMaxWait = 30;
  static const _ttsPollInterval = Duration(milliseconds: 300);
  static const _postTtsGuard = Duration(milliseconds: 500);
  static const _stopDelay = Duration(milliseconds: 200);

  @override
  VoiceConversationStatus build(String conversationId) {
    _voice = ref.read(voiceServiceProvider.notifier);

    ref.listen(messagesStreamProvider(conversationId), (prev, next) {
      if (!_isActive || !next.hasValue) return;
      final messages = next.value!;
      if (messages.isEmpty) return;

      final lastMsg = messages.last;
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

  Future<void> startConversation() async {
    _isActive = true;
    var consecutiveFailures = 0;
    const maxFailures = 3;

    while (_isActive) {
      state = const VoiceConversationStatus(
        state: VoiceConversationState.listening,
      );
      final transcript = await _listenWithVad();

      if (!_isActive) break;

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

      if (transcript.isEmpty) {
        consecutiveFailures = 0;
        continue;
      }

      consecutiveFailures = 0;
      _pendingTranscript = transcript;

      state = VoiceConversationStatus(
        state: VoiceConversationState.thinking,
        transcript: transcript,
      );

      try {
        final chatNotifier = ref.read(chatNotifierProvider(arg).notifier);
        await chatNotifier.sendMessage(transcript, isVoiceConversation: true);
      } catch (e) {
        debugPrint('[VoiceConversation] Erreur envoi chat : $e');
        state = VoiceConversationStatus(
          state: VoiceConversationState.error,
          error: e.toString(),
          transcript: transcript,
        );
        break;
      }

      while (_isActive &&
          (state.state == VoiceConversationState.thinking ||
              state.state == VoiceConversationState.speaking)) {
        await Future<void>.delayed(_ttsPollInterval);
      }

      if (!_isActive) break;
      if (state.state == VoiceConversationState.error) break;
    }

    _reset();
  }

  /// Lit la reponse IA a voix haute puis rend la main.
  /// Extrait l'émotion des balises prosodiques pour le splash.
  Future<void> _speakResponseAndLoop(String text) async {
    if (!_isActive) return;

    await _voice.stopListening();

    // Parser l'émotion du texte
    final parseResult = EmotionParser.parse(text);
    final emotion = parseResult.hasEmotionTag
        ? parseResult.emotion
        : EmotionParser.inferFromText(text);

    state = state.copyWith(
      state: VoiceConversationState.speaking,
      emotion: emotion,
    );

    try {
      await _voice.speakWithEmotion(text, emotion);
      while (_voice.state.isSpeaking && _isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } catch (e) {
      debugPrint('[VoiceConversation] TTS erreur : $e');
    }

    if (_isActive) {
      await Future<void>.delayed(_postTtsGuard);
    }

    if (_isActive) {
      state = state.copyWith(state: VoiceConversationState.idle);
    }
  }

  Future<String?> _listenWithVad() async {
    await _voice.stopListening();
    await _voice.startListening();

    if (!_voice.state.isAvailable && !_voice.state.isListening) {
      debugPrint('[VoiceConversation] STT non disponible');
      return null;
    }

    while (_voice.state.isListening && _isActive) {
      final newTranscript = _voice.state.transcript;
      if (newTranscript != state.transcript) {
        state = state.copyWith(transcript: newTranscript);
      }
      await Future<void>.delayed(_pollInterval);
    }

    if (!_isActive) return '';

    for (var i = 0; i < _sttMaxWait; i++) {
      if (!_voice.state.isListening || !_isActive) break;
      await Future<void>.delayed(_sttFinalWait);
    }

    if (!_isActive) return '';

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

  Future<void> stop() async {
    _isActive = false;
    _pendingTranscript = null;
    await _voice.stopListening();
    await _voice.stopSpeaking();
    state = const VoiceConversationStatus(state: VoiceConversationState.idle);
    await Future<void>.delayed(_stopDelay);
  }

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