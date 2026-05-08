import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'chat_notifier.dart';
import 'tts_emotion.dart';
import 'emotion_parser.dart';
import 'voice_service.dart';
import '../data/whisper_stt_service.dart';

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
  final bool bargeInEnabled;

  const VoiceConversationStatus({
    this.state = VoiceConversationState.idle,
    this.transcript,
    this.error,
    this.emotion = TtsEmotion.neutral,
    this.bargeInEnabled = true,
  });

  VoiceConversationStatus copyWith({
    VoiceConversationState? state,
    String? transcript,
    String? error,
    TtsEmotion? emotion,
    bool? bargeInEnabled,
  }) =>
      VoiceConversationStatus(
        state: state ?? this.state,
        transcript: transcript ?? this.transcript,
        error: error,
        emotion: emotion ?? this.emotion,
        bargeInEnabled: bargeInEnabled ?? this.bargeInEnabled,
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
/// Support du barge-in : si l'utilisateur parle pendant que le TTS parle,
/// le TTS est interrompu et on passe en mode écoute.
///
/// Support des balises prosodiques : [joyeux], [triste], [sérieux], [excité]
/// L'émotion détectée est exposée via VoiceConversationStatus.emotion
class VoiceConversationNotifier
    extends FamilyNotifier<VoiceConversationStatus, String> {
  late final VoiceServiceNotifier _voice;
  bool _isActive = false;
  String? _pendingTranscript;

  // ── Barge-in ─────────────────────────────────────────────────────────────
  bool _bargeInEnabled = true;
  String _bargeInTranscript = '';
  bool _bargeInDetected = false;

  // ── Whisper fallback ──────────────────────────────────────────────────────
  final WhisperSttService _whisperFallback = WhisperSttService();
  int _sttFailureCount = 0;

  static const _pollInterval = Duration(milliseconds: 150);
  static const _sttFinalWait = Duration(milliseconds: 100);
  static const _sttMaxWait = 30;
  static const _ttsPollInterval = Duration(milliseconds: 300);
  static const _postTtsGuard = Duration(milliseconds: 500);
  static const _stopDelay = Duration(milliseconds: 200);
  static const _bargeInPollInterval = Duration(milliseconds: 200);
  static const _bargeInMinWords = 2;

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
      _whisperFallback.dispose();
    });

    return VoiceConversationStatus(bargeInEnabled: _bargeInEnabled);
  }

  /// Active ou désactive le barge-in (interruption vocale du TTS).
  void setBargeInEnabled(bool enabled) {
    _bargeInEnabled = enabled;
    state = state.copyWith(bargeInEnabled: enabled);
  }

  Future<void> startConversation() async {
    _isActive = true;
    _sttFailureCount = 0;
    var consecutiveFailures = 0;
    const maxFailures = 3;

    while (_isActive) {
      state = VoiceConversationStatus(
        state: VoiceConversationState.listening,
        bargeInEnabled: _bargeInEnabled,
      );
      final transcript = await _listenWithVad();

      if (!_isActive) break;

      if (transcript == null) {
        consecutiveFailures++;
        if (consecutiveFailures >= maxFailures) {
          state = VoiceConversationStatus(
            state: VoiceConversationState.error,
            error: 'Microphone non disponible. Verifiez les permissions.',
            bargeInEnabled: _bargeInEnabled,
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
        bargeInEnabled: _bargeInEnabled,
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
          bargeInEnabled: _bargeInEnabled,
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
  /// Si barge-in est activé, surveille l'entrée micro pendant le TTS.
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

    _bargeInDetected = false;
    _bargeInTranscript = '';

    try {
      // Lancer le TTS
      await _voice.speakWithEmotion(text, emotion);

      if (_bargeInEnabled) {
        // Barge-in : démarrer l'écoute pendant le TTS
        // Le délai de 500ms évite que le micro capte le TTS qui vient de démarrer
        await Future<void>.delayed(const Duration(milliseconds: 500));

        if (_isActive && _voice.state.isSpeaking) {
          await _voice.startListening();

          while (_voice.state.isSpeaking && _isActive && !_bargeInDetected) {
            final micInput = _voice.state.transcript;
            if (micInput.isNotEmpty) {
              // Vérifier que ce n'est pas juste du bruit (minimum 2 mots)
              final words = micInput.trim().split(RegExp(r'\s+'));
              if (words.length >= _bargeInMinWords) {
                _bargeInDetected = true;
                _bargeInTranscript = micInput;
                debugPrint('[VoiceConversation] Barge-in détecté: "$micInput"');
                break;
              }
            }
            await Future<void>.delayed(_bargeInPollInterval);
          }

          // Arrêter l'écoute de barge-in
          await _voice.stopListening();
        }
      } else {
        // Mode classique : attendre la fin du TTS
        while (_voice.state.isSpeaking && _isActive) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    } catch (e) {
      debugPrint('[VoiceConversation] TTS erreur : $e');
    }

    if (_bargeInDetected && _bargeInTranscript.isNotEmpty) {
      // L'utilisateur a interrompu — arrêter le TTS et traiter la nouvelle entrée
      await _voice.stopSpeaking();

      _pendingTranscript = _bargeInTranscript;
      state = VoiceConversationStatus(
        state: VoiceConversationState.thinking,
        transcript: _bargeInTranscript,
        bargeInEnabled: _bargeInEnabled,
      );

      try {
        final chatNotifier = ref.read(chatNotifierProvider(arg).notifier);
        await chatNotifier.sendMessage(_bargeInTranscript, isVoiceConversation: true);
      } catch (e) {
        debugPrint('[VoiceConversation] Erreur envoi barge-in : $e');
      }
      return;
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

      // Fallback : essayer Whisper si le STT natif est indisponible
      if (!kIsWeb && _whisperFallback.isAvailable) {
        debugPrint('[VoiceConversation] Tentative Whisper fallback');
        return await _listenWithWhisper();
      }

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

  /// Fallback Whisper : enregistre l'audio puis le transcrit via API.
  Future<String?> _listenWithWhisper() async {
    if (!_whisperFallback.isAvailable) return null;

    final started = await _whisperFallback.startRecording();
    if (!started) {
      debugPrint('[VoiceConversation] Whisper fallback : échec démarrage');
      return null;
    }

    // Afficher l'état listening
    state = state.copyWith(
      state: VoiceConversationState.listening,
      transcript: '(écoute Whisper en cours...)',
    );

    // Écouter pendant 10 secondes max
    await Future<void>.delayed(const Duration(seconds: 10));

    final audioPath = await _whisperFallback.stopRecording();
    if (audioPath == null) return null;

    state = state.copyWith(
      state: VoiceConversationState.processingStt,
      transcript: '(transcription en cours...)',
    );

    try {
      final transcript = await _whisperFallback.transcribe(language: 'fr');
      _sttFailureCount = 0;
      return transcript.isEmpty ? null : transcript;
    } catch (e) {
      debugPrint('[VoiceConversation] Whisper fallback error : $e');
      _sttFailureCount++;
      return null;
    }
  }

  Future<void> stop() async {
    _isActive = false;
    _bargeInDetected = false;
    _bargeInTranscript = '';
    _pendingTranscript = null;
    await _voice.stopListening();
    await _voice.stopSpeaking();
    state = VoiceConversationStatus(
      state: VoiceConversationState.idle,
      bargeInEnabled: _bargeInEnabled,
    );
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
    state = VoiceConversationStatus(bargeInEnabled: _bargeInEnabled);
  }
}

final voiceConversationProvider = NotifierProviderFamily<
    VoiceConversationNotifier, VoiceConversationStatus, String>(
  VoiceConversationNotifier.new,
);