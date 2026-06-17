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

/// Service de conversation vocale tour-par-tour (half-duplex).
///
/// Flux :
/// 1. LISTENING — STT continu (micro ouvert), `SpeechFinalEvent` natif déclenche le tour.
/// 2. THINKING — envoi au LLM quand speech final natif.
/// 3. SPEAKING — TTS du message complet d'un bloc (pas de streaming par phrases) ;
///    micro coupé avant le TTS (anti-écho/monologue).
/// 4. Retour à LISTENING — micro rouvert après une pause 1200ms (réinit STT Android
///    ~300-500ms + anti-écho résiduel).
/// 5. BARGE-IN — si l'utilisateur parle pendant le TTS (speech final > 3 mots),
///    interruption immédiate + nouveau tour (repeat / topicChange / LLM).
///
/// Robustesse — token de génération (Bloc 2) :
/// Chaque frontière de tour (démarrage, barge-in, stop, dispose) incrémente
/// `_generation`. Toute continuation asynchrone (réouverture du micro après TTS,
/// délai post-TTS) capture la génération de son tour et **bail si elle est
/// obsolète** (`gen != _generation`). Cela évite qu'un `_speakFullResponse`
/// supplanté par un barge-in ne rouvre le micro ou n'écrase l'état du nouveau
/// tour. Le garde `_isProcessingResponse` empêche un double déclenchement de
/// `_handleChatState` pendant la fenêtre thinking→speaking ; il n'est libéré
/// que par le tour qui l'a posé (`_generation == gen`).
class VoiceConversationNotifier
    extends FamilyNotifier<VoiceConversationStatus, String> {
  late final VoiceServiceNotifier _voice;
  bool _isActive = false;

  bool _bargeInEnabled = true;
  String _lastBargeInTranscript = '';

  StreamSubscription<SpeechFinalEvent>? _speechFinalSub;
  StreamSubscription<String>? _sttErrorSub;

  String? _lastProcessedTranscript;
  DateTime? _lastProcessedTime;

  /// Garde contre les appels concurrents à _speakFullResponse pendant la
  /// fenêtre thinking→speaking. Posé par le tour courant, libéré par le même
  /// tour (via la génération capturée).
  bool _isProcessingResponse = false;

  /// Compteur d'échecs STT consécutifs (mid-conversation). ≥ 3 → état error
  /// (anti-boucle infinie sur micro instable). Reset à 0 sur un speech final
  /// exploitable (STT fonctionne).
  int _sttFailureCount = 0;

  /// Emotion du TTS en cours pour le prosody learning.
  TtsEmotion _currentSpeakingEmotion = TtsEmotion.neutral;

  /// Heure de la dernière requête LLM envoyée par _sendToLLM. Utilisée pour
  /// identifier le message assistant du tour vocal actuel (évite de parler un
  /// message d'un tour précédent si messages.last pointe sur l'ancien message).
  DateTime? _lastRequestTime;

  /// Token de génération (Bloc 2). Incrémenté à chaque frontière de tour.
  /// Les continuations async capturent la génération et bail si obsolète.
  int _generation = 0;

  @override
  VoiceConversationStatus build(String conversationId) {
    _voice = ref.read(voiceServiceProvider.notifier);

    ref.listen(chatNotifierProvider(conversationId), (prev, next) {
      if (!_isActive) return;
      _handleChatState(next);
    });

    ref.onDispose(() {
      _isActive = false;
      _resetTurnState();
      _speechFinalSub?.cancel();
      _sttErrorSub?.cancel();
      _voice.stopListening();
      _voice.stopSpeaking();
    });

    return VoiceConversationStatus(bargeInEnabled: _bargeInEnabled);
  }

  void setBargeInEnabled(bool enabled) {
    _bargeInEnabled = enabled;
    state = state.copyWith(bargeInEnabled: enabled);
  }

  /// Réinitialise l'état d'un tour : invalide les continuations async en cours
  /// (bump génération) et vide les drapeaux stale. Appelé à chaque frontière
  /// (start, stop, dispose) pour éviter qu'un tour précédent ne pollue le
  /// suivant (anti-race : micro rouvert par un _speakFullResponse obsolète,
  /// _isProcessingResponse resté bloqué, etc.).
  void _resetTurnState() {
    _generation++;
    _isProcessingResponse = false;
    _lastProcessedTranscript = null;
    _lastProcessedTime = null;
    _lastBargeInTranscript = '';
    _lastRequestTime = null;
    _sttFailureCount = 0;
  }

  /// Demarre la conversation vocale en boucle infinie.
  Future<void> startConversation() async {
    if (_isActive) return;
    _resetTurnState();
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

    // Vérifier que le micro a bien démarré après un court délai. Cet check
    // reste responsable de l'échec du DÉMARRAGE INITIAL ; les échecs STT
    // mid-conversation sont gérés par _onSttError (comptage + reprise).
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!_isActive) return; // stop() pendant le délai
    if (!_voice.state.isListening) {
      final available = _voice.state.isAvailable;
      state = state.copyWith(
        state: VoiceConversationState.error,
        error: available
            ? 'Le micro n\'a pas pu démarrer. Réessayez.'
            : 'Microphone non disponible. Vérifiez la permission dans '
                'Paramètres → Applications → Corely → Autorisations → Microphone.',
      );
      await stop();
      return;
    }

    // Démarrage réussi : écouter les erreurs STT pour la reprise
    // mid-conversation (comptage → reprise ou état error après 3 échecs).
    _sttErrorSub?.cancel();
    _sttErrorSub = _voice.onSttError.listen(_onSttError);
  }

  void _onSpeechFinal(String transcript) {
    if (transcript.isEmpty) return;

    // Dedup : ignorer les doublons dans les 2 secondes (null-check défensif —
    // _lastProcessedTime n'est posé qu'avec _lastProcessedTranscript, mais on
    // ne force pas l unwrap pour éviter un crash si l'invariant est rompu).
    if (transcript == _lastProcessedTranscript && _lastProcessedTime != null) {
      final elapsed = DateTime.now().difference(_lastProcessedTime!);
      if (elapsed < const Duration(seconds: 2)) return;
    }
    _lastProcessedTranscript = transcript;
    _lastProcessedTime = DateTime.now();
    // Un speech final exploitable = le STT fonctionne → reset le compteur.
    _sttFailureCount = 0;

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

  /// Erreur STT mid-conversation : compte, tente une reprise, ou bascule en
  /// état error après 3 échecs consécutifs (anti-boucle infinie).
  void _onSttError(String _) {
    if (!_isActive || state.state != VoiceConversationState.listening) return;
    _sttFailureCount++;
    debugPrint('[VoiceConversation] STT failure #$_sttFailureCount');

    if (_sttFailureCount >= 3) {
      state = state.copyWith(
        state: VoiceConversationState.error,
        error: 'Micro instable après plusieurs essais. Vérifiez le micro '
            'et réessayez.',
      );
      stop();
      return;
    }

    // Reprise : redémarrer le micro après un court délai, seulement s'il
    // n'est pas déjà reparti (anti re-entrance).
    Future<void>.delayed(const Duration(milliseconds: 400)).then((_) {
      if (_isActive &&
          state.state == VoiceConversationState.listening &&
          !_voice.state.isListening) {
        _voice.startListening();
      }
    });
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
      if (lastRequestTime != null && m.createdAt.isBefore(lastRequestTime)) {
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
    final gen = _generation;
    _isProcessingResponse = true;
    _speakFullResponse(targetMsg.content, generation: gen).whenComplete(() {
      // Ne libérer le garde que si on est toujours sur le même tour :
      // un barge-in/stop a bumpé _generation → on ne touche pas au drapeau
      // (qui a déjà été réinitialisé par _resetTurnState/_handleBargeIn).
      if (_generation == gen) _isProcessingResponse = false;
    });
  }

  /// Parle la reponse complete d'un bloc (pas de streaming par phrases).
  /// [generation] attache ce speak à un tour ; si _generation a bumpé
  /// (barge-in/stop/dispose), la continuation bail et ne rouvre pas le micro.
  Future<void> _speakFullResponse(String text, {int? generation}) async {
    if (!_isActive) return;
    final gen = generation ?? _generation;
    if (gen != _generation) return; // tour supplanté

    // Couper le micro avant de parler — evite l'echo (monologue).
    await _voice.stopListening();
    if (!_isActive || gen != _generation) return;

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

    // Apres le TTS, rouvrir le micro pour le prochain tour — uniquement si
    // ce tour n'a pas ete supplanté (barge-in/stop). Délai 1200ms : réinit
    // SpeechToText Android (~300-500ms par instance) + anti-écho résiduel.
    if (!_isActive || gen != _generation) return;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!_isActive || gen != _generation) return;
    state = state.copyWith(state: VoiceConversationState.listening, transcript: '');
    _voice.clearTranscript();
    await _voice.startListening();
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

    // Invalider le tour en cours : bump de génération → le _speakFullResponse
    // d'origine ne rouvrira pas le micro (gen != _generation) ni n'écrasera
    // l'état. On libère _isProcessingResponse pour qu'un nouveau tour puisse
    // démarrer (son whenComplete ne le retouchera pas : gen obsolète).
    _generation++;
    _isProcessingResponse = false;
    _voice.stopSpeaking();
    ProsodyLearningService().recordBargeIn(_currentSpeakingEmotion);

    switch (intent) {
      case BargeInIntent.repeat:
        // Relire la derniere reponse complete (sans repasser par le LLM).
        _respeakLastAssistant();
        return;
      case BargeInIntent.topicChange:
        _sendToLLM('Changement de sujet : $transcript');
        return;
      case BargeInIntent.stop:
        // "chut / tais-toi / arrête / pause / silence" : couper le TTS et
        // reprendre l'écoute sans envoyer de message au LLM (l'utilisateur
        // reprend la parole). Anciennement mal routé vers _sendToLLM, ce qui
        // envoyait le mot "stop" au LLM et déclenchait une nouvelle réponse —
        // l'utilisateur voulait du silence, obtenait le contraire.
        _returnToListening();
        return;
      case BargeInIntent.correction:
      case BargeInIntent.none:
        _sendToLLM(transcript);
        return;
    }
  }

  /// Re-parle le dernier message assistant (barge-in "repeat"). La génération
  /// a déjà été bumpée et le garde libéré dans _handleBargeInDuringSpeaking,
  /// donc _speakFullResponse procédera (pas de skip par le garde speaking).
  void _respeakLastAssistant() {
    final messages = ref.read(chatNotifierProvider(arg)).messages;
    if (messages.isEmpty) return;
    final lastAssistant = messages.lastWhere(
      (m) => m.isAssistant,
      orElse: () => messages.first,
    );
    if (lastAssistant.content.isEmpty) return;
    _speakFullResponse(lastAssistant.content);
  }

  /// Barge-in "stop" (chut / arrête / pause / silence) : le TTS est déjà coupé
  /// par _handleBargeInDuringSpeaking et le tour en cours est invalidé (bump
  /// génération). On repasse simplement en écoute sans round-trip LLM, pour
  /// que l'utilisateur reprenne la parole. Évite d'envoyer le mot "stop" au
  /// LLM (ancien comportement qui déclenchait une nouvelle réponse).
  Future<void> _returnToListening() async {
    if (!_isActive) return;
    state = state.copyWith(state: VoiceConversationState.listening, transcript: '');
    _voice.clearTranscript();
    await _voice.startListening();
  }

  Future<void> stop() async {
    _isActive = false;
    _resetTurnState();
    _speechFinalSub?.cancel();
    _sttErrorSub?.cancel();
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