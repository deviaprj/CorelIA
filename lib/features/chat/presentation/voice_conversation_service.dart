import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'chat_notifier.dart';
import '../domain/message.dart';
import 'barge_in_intent_classifier.dart';
import 'prosody_learning_service.dart';
import 'tts_emotion.dart';
import 'emotion_parser.dart';
import 'voice_service.dart';

/// Etat du mode conversation vocale mains-libres.
enum VoiceConversationState {
  idle,
  listening,
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

/// Service de conversation vocale tour-par-tour.
///
/// Flux simplifie :
/// 1. LISTENING — STT continu (micro toujours ouvert)
/// 2. THINKING — envoi au LLM quand speech final natif
/// 3. SPEAKING — TTS du message complet (pas de streaming par phrases)
/// 4. Retour automatique a LISTENING (micro jamais coupe)
/// 5. BARGE-IN — si l'utilisateur parle pendant le TTS (speech final detecte),
///    interruption immediate + nouveau message LLM.
class VoiceConversationNotifier
    extends FamilyNotifier<VoiceConversationStatus, String> {
  late final VoiceServiceNotifier _voice;
  bool _isActive = false;

  bool _bargeInEnabled = true;
  String _lastBargeInTranscript = '';

  StreamSubscription<SpeechFinalEvent>? _speechFinalSub;

  String? _lastProcessedTranscript;
  DateTime? _lastProcessedTime;

  /// Garde contre les appels concurrents à _speakFullResponse.
  bool _isProcessingResponse = false;

  /// Emotion du TTS en cours pour le prosody learning.
  TtsEmotion _currentSpeakingEmotion = TtsEmotion.neutral;

  /// Heure de la dernière requête LLM envoyée par _sendToLLM.
  /// Utilisée pour identifier le message assistant qui correspond au tour
  /// vocal actuel (évite de parler un message d'un tour précédent si
  /// messages.last pointe sur l'ancien message).
  DateTime? _lastRequestTime;

  @override
  VoiceConversationStatus build(String conversationId) {
    _voice = ref.read(voiceServiceProvider.notifier);

    ref.listen(chatNotifierProvider(conversationId), (prev, next) {
      if (!_isActive) return;
      _handleChatState(next);
    });

    ref.onDispose(() {
      _isActive = false;
      _speechFinalSub?.cancel();
      _voice.stopListening();
      _voice.stopSpeaking();
    });

    return VoiceConversationStatus(bargeInEnabled: _bargeInEnabled);
  }

  void setBargeInEnabled(bool enabled) {
    _bargeInEnabled = enabled;
    state = state.copyWith(bargeInEnabled: enabled);
  }

  /// Demarre la conversation vocale en boucle infinie.
  Future<void> startConversation() async {
    if (_isActive) return;
    _isActive = true;
    _voice.setConversationMode(true);
    _voice.clearTranscript();

    _speechFinalSub?.cancel();
    _speechFinalSub = _voice.onSpeechFinal.listen((event) {
      if (!_isActive) return;
      _onSpeechFinal(event.transcript);
    });

    state = state.copyWith(state: VoiceConversationState.listening);
    await _voice.startListening();
  }

  void _onSpeechFinal(String transcript) {
    if (transcript.isEmpty) return;

    // Dedup : ignorer les doublons dans les 2 secondes
    if (transcript == _lastProcessedTranscript) {
      final elapsed = DateTime.now().difference(_lastProcessedTime!);
      if (elapsed < const Duration(seconds: 2)) return;
    }
    _lastProcessedTranscript = transcript;
    _lastProcessedTime = DateTime.now();

    // Barge-in pendant le TTS
    if (state.state == VoiceConversationState.speaking && _bargeInEnabled) {
      _handleBargeInDuringSpeaking(transcript);
      return;
    }

    // Normal flow : envoyer au LLM (seulement en ecoute)
    if (state.state == VoiceConversationState.listening) {
      _sendToLLM(transcript);
    }
  }

  void _sendToLLM(String transcript) {
    if (transcript.isEmpty || !_isActive) return;

    state = VoiceConversationStatus(
      state: VoiceConversationState.thinking,
      transcript: transcript,
      bargeInEnabled: _bargeInEnabled,
    );

    _voice.clearTranscript();

    // Marquer l'heure de la requete pour que _handleChatState puisse
    // identifier le message assistant du tour actuel.
    _lastRequestTime = DateTime.now();

    final chatNotifier = ref.read(chatNotifierProvider(arg).notifier);
    chatNotifier.sendMessage(transcript, isVoiceConversation: true, modelOverride: 'task:vocal');
  }

  /// Appelle quand le ChatNotifier recoit des tokens du LLM.
  void _handleChatState(ChatState chatState) {
    if (state.state != VoiceConversationState.thinking) return;
    if (_isProcessingResponse) {
      debugPrint('[VoiceConversation] _handleChatState ignored: already processing response');
      return;
    }

    final messages = chatState.messages;
    if (messages.isEmpty) return;

    // Trouver le dernier message assistant non-streaming cree APRES
    // _lastRequestTime. Cela garantit qu'on parle le message du tour
    // actuel, meme si messages.last pointe sur un ancien message a cause
    // d'un snapshot Firestore intermediaire.
    final lastRequestTime = _lastRequestTime;
    Message? targetMsg;
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (!m.isAssistant) continue;
      if (m.isStreaming) continue;
      if (m.content.isEmpty) continue;
      if (lastRequestTime != null &&
          m.createdAt.isBefore(lastRequestTime)) {
        continue;
      }
      targetMsg = m;
      break;
    }

    if (targetMsg == null) {
      debugPrint('[VoiceConversation] No assistant message found after $_lastRequestTime');
      return;
    }

    debugPrint('[VoiceConversation] Will speak msg id=${targetMsg.id}, '
        'createdAt=${targetMsg.createdAt}, len=${targetMsg.content.length}');
    _isProcessingResponse = true;
    _speakFullResponse(targetMsg.content).whenComplete(() {
      _isProcessingResponse = false;
    });
  }

  /// Parle la reponse complete d'un bloc (pas de streaming par phrases).
  Future<void> _speakFullResponse(String text) async {
    if (!_isActive) return;
    if (_isProcessingResponse && state.state == VoiceConversationState.speaking) {
      debugPrint('[VoiceConversation] _speakFullResponse skipped: already speaking');
      return;
    }

    // Couper le micro avant de parler — evite l'echo (monologue)
    await _voice.stopListening();

    state = state.copyWith(state: VoiceConversationState.speaking);

    final parseResult = EmotionParser.parse(text);
    final emotion = parseResult.hasEmotionTag
        ? parseResult.emotion
        : EmotionParser.inferFromText(text);
    _currentSpeakingEmotion = emotion;

    try {
      await _voice.speakWithEmotion(text, emotion);
      ProsodyLearningService().recordCompletion(emotion);
    } catch (e) {
      debugPrint('[VoiceConversation] TTS error: $e');
    }

    // Apres le TTS, rouvrir le micro pour le prochain tour.
    if (_isActive) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (_isActive) {
        state = state.copyWith(state: VoiceConversationState.listening, transcript: '');
        _voice.clearTranscript();
        await _voice.startListening();
      }
    }
  }

  /// Barge-in pendant le TTS : l'utilisateur parle par-dessus la reponse.
  void _handleBargeInDuringSpeaking(String transcript) {
    // Ignorer les courts transcripts (probable echo/bruit)
    final words = transcript.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (words < 3) {
      debugPrint('[VoiceConversation] Barge-in ignored (too short: $words words)');
      return;
    }

    if (transcript == _lastBargeInTranscript) return;
    _lastBargeInTranscript = transcript;

    final intent = BargeInIntentClassifier.classify(transcript);
    debugPrint('[VoiceConversation] Barge-in ($intent): $transcript');

    _voice.stopSpeaking();
    ProsodyLearningService().recordBargeIn(_currentSpeakingEmotion);

    switch (intent) {
      case BargeInIntent.repeat:
        // Relire la derniere reponse complete
        final messages = ref.read(chatNotifierProvider(arg)).messages;
        if (messages.isNotEmpty) {
          final lastAssistant = messages.lastWhere(
            (m) => m.isAssistant,
            orElse: () => messages.first,
          );
          if (lastAssistant.content.isNotEmpty) {
            _speakFullResponse(lastAssistant.content);
          }
        }
        return;
      case BargeInIntent.topicChange:
        final prefixed = 'Changement de sujet : $transcript';
        _sendToLLM(prefixed);
        return;
      case BargeInIntent.stop:
      case BargeInIntent.correction:
      case BargeInIntent.none:
        _sendToLLM(transcript);
        return;
    }
  }

  Future<void> stop() async {
    _isActive = false;
    _speechFinalSub?.cancel();
    _voice.setConversationMode(false);
    await _voice.stopListening();
    await _voice.stopSpeaking();
    state = VoiceConversationStatus(
      state: VoiceConversationState.idle,
      bargeInEnabled: _bargeInEnabled,
    );
  }

  Future<void> toggle() async {
    if (_isActive) {
      await stop();
    } else {
      await startConversation();
    }
  }
}

final voiceConversationProvider = NotifierProviderFamily<
    VoiceConversationNotifier, VoiceConversationStatus, String>(
  VoiceConversationNotifier.new,
);
