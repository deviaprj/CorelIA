import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'chat_notifier.dart';
import 'barge_in_intent_classifier.dart';
import 'tts_emotion.dart';
import 'emotion_parser.dart';
import 'voice_service.dart';
import '../data/whisper_stt_service.dart';

/// Etat du mode conversation vocale mains-libres.
enum VoiceConversationState {
  processingStt,
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

/// Service de conversation vocale mains-libres — vrai chat vocal continu.
///
/// Flux :
/// 1. LISTENING — ecoute continue sans bips, VAD logiciel (1.5s silence = fin)
/// 2. THINKING — envoi automatique au ChatNotifier des que speech final
/// 3. SPEAKING — TTS streaming par phrases des les premiers tokens recus
/// 4. Apres reponse, retour automatique a LISTENING (conversation infinie)
/// 5. BARGE-IN — si l'utilisateur parle pendant le TTS, interruption immediate
class VoiceConversationNotifier
    extends FamilyNotifier<VoiceConversationStatus, String> {
  late final VoiceServiceNotifier _voice;
  bool _isActive = false;

  // ── Streaming TTS ──────────────────────────────────────────────────────────
  final StringBuffer _ttsBuffer = StringBuffer();
  int _lastSpokenSentenceEnd = 0;

  // ── Barge-in ───────────────────────────────────────────────────────────────
  bool _bargeInEnabled = true;
  String _lastBargeInTranscript = '';
  DateTime? _bargeInAudioStart;

  // ── Whisper fallback ──────────────────────────────────────────────────────
  final WhisperSttService _whisperFallback = WhisperSttService();

  // ── Subscriptions ──────────────────────────────────────────────────────────
  StreamSubscription<SpeechFinalEvent>? _speechFinalSub;
  StreamSubscription<void>? _ttsDoneSub;

  static const _ttsSentenceMinLength = 20;
  static const _ttsFirstSentenceMinLength = 12;
  static const _bargeInMinWords = 2;
  String _lastSpokenText = '';

  @override
  VoiceConversationStatus build(String conversationId) {
    _voice = ref.read(voiceServiceProvider.notifier);

    // Ecouter le ChatNotifier pour streaming TTS (plus rapide que Firestore)
    ref.listen(chatNotifierProvider(conversationId), (prev, next) {
      if (!_isActive) return;
      _handleChatState(next);
    });

    // Ecouter le VoiceService pour barge-in audio temps réel
    ref.listen(voiceServiceProvider, (prev, next) {
      if (!_isActive) return;
      _handleVoiceState(next);
    });

    ref.onDispose(() {
      _isActive = false;
      _speechFinalSub?.cancel();
      _ttsDoneSub?.cancel();
      _voice.stopListening();
      _voice.stopSpeaking();
      _whisperFallback.dispose();
    });

    return VoiceConversationStatus(bargeInEnabled: _bargeInEnabled);
  }

  void setBargeInEnabled(bool enabled) {
    _bargeInEnabled = enabled;
    state = state.copyWith(bargeInEnabled: enabled);
  }

  /// Barge-in audio temps reel : detecte le son du micro pendant le TTS.
  /// Exige un niveau mic > 0.12 pendant > 200ms pour eviter les pics parasites.
  void _handleVoiceState(VoiceState voiceState) {
    if (!_isActive) return;
    if (state.state == VoiceConversationState.speaking && _bargeInEnabled) {
      final micHigh = voiceState.micLevel > 0.12 && voiceState.isListening;
      if (micHigh) {
        _bargeInAudioStart ??= DateTime.now();
        final sustained = DateTime.now().difference(_bargeInAudioStart!);
        if (sustained >= const Duration(milliseconds: 200)) {
          debugPrint('[VoiceConversation] Barge-in audio sustained (micLevel=${voiceState.micLevel}, ${sustained.inMilliseconds}ms)');
          _bargeInAudioStart = null;
          _voice.stopSpeaking();
          _ttsBuffer.clear();
          _lastSpokenSentenceEnd = 0;
          state = state.copyWith(state: VoiceConversationState.listening);
        }
      } else {
        _bargeInAudioStart = null;
      }
    }
  }

  /// Demarre la conversation vocale en boucle infinie.
  Future<void> startConversation() async {
    if (_isActive) return;
    _isActive = true;
    _voice.setContinuousMode(true);
    _voice.clearTranscript();
    _ttsBuffer.clear();
    _lastSpokenSentenceEnd = 0;

    // Ecouter les evenements speech final du VoiceService
    _speechFinalSub?.cancel();
    _speechFinalSub = _voice.onSpeechFinal.listen((event) {
      if (!_isActive) return;
      _onSpeechFinal(event.transcript);
    });

    // Premier tour d'ecoute
    state = state.copyWith(state: VoiceConversationState.listening);
    await _voice.startListening();
  }

  void _onSpeechFinal(String transcript) {
    if (transcript.isEmpty) return;

    // Barge-in detection : si on parle pendant que le bot parle
    if (state.state == VoiceConversationState.speaking) {
      if (!_bargeInEnabled) return;
      final intent = BargeInIntentClassifier.classify(transcript);
      if (intent == BargeInIntent.none) {
        final words = transcript.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        if (words < _bargeInMinWords) return;
      }
      _handleBargeIn(transcript, intent: intent);
      return;
    }

    // Normal flow : envoyer au LLM
    _sendToLLM(transcript);
  }

  void _sendToLLM(String transcript) {
    if (transcript.isEmpty || !_isActive) return;

    state = VoiceConversationStatus(
      state: VoiceConversationState.thinking,
      transcript: transcript,
      bargeInEnabled: _bargeInEnabled,
    );

    // Nettoyer le buffer TTS pour la nouvelle reponse
    _ttsBuffer.clear();
    _lastSpokenSentenceEnd = 0;

    // Vider le transcript vocal immediatement pour eviter qu'il reapparaisse
    // dans l'InputBar lors du prochain rebuild.
    _voice.clearTranscript();

    final chatNotifier = ref.read(chatNotifierProvider(arg).notifier);
    chatNotifier.sendMessage(transcript, isVoiceConversation: true, modelOverride: 'task:vocal');
  }

  /// Appelle quand le ChatNotifier recoit des tokens du LLM.
  void _handleChatState(ChatState chatState) {
    final messages = chatState.messages;
    if (messages.isEmpty) return;

    final lastMsg = messages.last;
    if (!lastMsg.isAssistant) return;

    final content = lastMsg.content;
    if (content.isEmpty) return;

    // Streaming en cours : parler les phrases completes au fur et a mesure
    if (lastMsg.isStreaming) {
      _speakStreamingSentences(content);
    } else if (state.state == VoiceConversationState.thinking) {
      // Stream vient de finir, dire le reste si non dit
      _speakRemaining(content);
    }
  }

  /// Parle les phrases completes des qu'elles sont disponibles dans le stream.
  /// Si aucune fin de phrase n'est trouvee apres 120 chars, parle le fragment.
  void _speakStreamingSentences(String fullText) {
    if (fullText.length <= _lastSpokenSentenceEnd) return;
    final newText = fullText.substring(_lastSpokenSentenceEnd);

    // Chercher une phrase complete (finie par . ! ? ;)
    final sentenceEnd = _findSentenceEnd(newText);
    if (sentenceEnd == -1) {
      // Pas de fin de phrase : parler le fragment si trop long
      if (newText.length > 120) {
        final fragment = newText.substring(0, 120).trim();
        _lastSpokenSentenceEnd += 120;
        _speakSentence(fragment);
      }
      return;
    }

    final sentence = newText.substring(0, sentenceEnd + 1).trim();
    final minLen = _lastSpokenSentenceEnd == 0
        ? _ttsFirstSentenceMinLength
        : _ttsSentenceMinLength;
    if (sentence.length >= minLen) {
      _lastSpokenSentenceEnd = _lastSpokenSentenceEnd + sentenceEnd + 1;
      _speakSentence(sentence);
    }
  }

  /// Parle le texte restant quand le stream se termine.
  void _speakRemaining(String fullText) {
    if (fullText.length <= _lastSpokenSentenceEnd) {
      _restartListeningAfterTts();
      return;
    }
    final remaining = fullText.substring(_lastSpokenSentenceEnd).trim();
    if (remaining.isNotEmpty) {
      _speakSentence(remaining);
    } else {
      _restartListeningAfterTts();
    }
  }

  void _speakSentence(String sentence) {
    if (sentence.isEmpty || !_isActive) return;

    _lastSpokenText = sentence;
    state = state.copyWith(state: VoiceConversationState.speaking);

    final parseResult = EmotionParser.parse(sentence);
    final emotion = parseResult.hasEmotionTag
        ? parseResult.emotion
        : EmotionParser.inferFromText(sentence);

    _voice.speakStreamingWithEmotion(sentence, emotion).then((_) {
      // Si on est toujours en speaking, le TTS a termine normalement -> redemarrer ecoute
      // Si barge-in a change l'etat en thinking, ne rien faire (le barge-in gere le flux)
      if (_isActive && state.state == VoiceConversationState.speaking) {
        _restartListeningAfterTts();
      }
    }).catchError((e) {
      debugPrint('[VoiceConversation] TTS error: \$e');
    });
  }

  /// Barge-in : interruption vocale pendant que le bot parle.
  void _handleBargeIn(String transcript, {BargeInIntent intent = BargeInIntent.stop}) {
    if (transcript == _lastBargeInTranscript) return;
    _lastBargeInTranscript = transcript;

    debugPrint('[VoiceConversation] Barge-in ($intent): \$transcript');
    _voice.stopSpeaking();
    _ttsBuffer.clear();
    _lastSpokenSentenceEnd = 0;

    switch (intent) {
      case BargeInIntent.repeat:
        // Relire la derniere reponse sans appeler le LLM
        if (_lastSpokenText.isNotEmpty) {
          state = state.copyWith(state: VoiceConversationState.speaking);
          _speakSentence(_lastSpokenText);
        }
        return;
      case BargeInIntent.topicChange:
        // Prefixer pour signaler le changement de sujet
        final prefixed = 'Changement de sujet : $transcript';
        state = VoiceConversationStatus(
          state: VoiceConversationState.thinking,
          transcript: prefixed,
          bargeInEnabled: _bargeInEnabled,
        );
        final chatNotifier = ref.read(chatNotifierProvider(arg).notifier);
        chatNotifier.sendMessage(prefixed, isVoiceConversation: true, modelOverride: 'task:vocal');
        return;
      case BargeInIntent.stop:
      case BargeInIntent.correction:
      case BargeInIntent.none:
        // Interruption immediate + nouveau message LLM
        state = VoiceConversationStatus(
          state: VoiceConversationState.thinking,
          transcript: transcript,
          bargeInEnabled: _bargeInEnabled,
        );
        final chatNotifier = ref.read(chatNotifierProvider(arg).notifier);
        chatNotifier.sendMessage(transcript, isVoiceConversation: true, modelOverride: 'task:vocal');
        return;
    }
  }

  /// Trouve la fin de la premiere phrase complete dans [text].
  /// Retourne l'index du dernier caractere de la phrase, ou -1 si pas trouve.
  int _findSentenceEnd(String text) {
    const enders = ['. ', '! ', '? ', '.\n', '!\n', '?\n', '；', '。'];
    var earliest = -1;
    for (final ender in enders) {
      final idx = text.indexOf(ender);
      if (idx != -1 && (earliest == -1 || idx < earliest)) {
        earliest = idx;
      }
    }
    return earliest;
  }

  Future<void> _restartListeningAfterTts() async {
    if (!_isActive) return;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!_isActive) return;

    state = state.copyWith(state: VoiceConversationState.listening);
    _voice.clearTranscript();

    // Ne redémarrer que si le micro s'est arrêté — évite les bips inutiles
    if (!_voice.state.isListening) {
      await _voice.startListening();
    }
  }

  Future<void> stop() async {
    _isActive = false;
    _speechFinalSub?.cancel();
    _voice.setContinuousMode(false);
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
