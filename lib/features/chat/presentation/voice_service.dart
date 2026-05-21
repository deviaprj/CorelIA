import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../../../core/providers/app_providers.dart';
import '../data/web_speech_bridge.dart';
import 'tts_emotion.dart';
import 'emotion_parser.dart';
import 'tts_natural_service.dart';

class VoiceState {
  final bool isAvailable;
  final bool isListening;
  final bool isSpeaking;
  final String transcript;
  final TtsEmotion currentEmotion;
  final double micLevel;
  /// True quand l'utilisateur a fait une pause de parole (silence detecte).
  final bool speechFinal;

  const VoiceState({
    this.isAvailable = false,
    this.isListening = false,
    this.isSpeaking = false,
    this.transcript = '',
    this.currentEmotion = TtsEmotion.neutral,
    this.micLevel = 0.0,
    this.speechFinal = false,
  });

  VoiceState copyWith({
    bool? isAvailable,
    bool? isListening,
    bool? isSpeaking,
    String? transcript,
    TtsEmotion? currentEmotion,
    double? micLevel,
    bool? speechFinal,
  }) =>
      VoiceState(
        isAvailable: isAvailable ?? this.isAvailable,
        isListening: isListening ?? this.isListening,
        isSpeaking: isSpeaking ?? this.isSpeaking,
        transcript: transcript ?? this.transcript,
        currentEmotion: currentEmotion ?? this.currentEmotion,
        micLevel: micLevel ?? this.micLevel,
        speechFinal: speechFinal ?? this.speechFinal,
      );
}

/// Evenement emis quand une phrase vocale est consideree comme finalisee.
class SpeechFinalEvent {
  final String transcript;
  SpeechFinalEvent(this.transcript);
}

class VoiceServiceNotifier extends Notifier<VoiceState> {
  stt.SpeechToText? _stt;
  bool _sttInitialized = false;
  late final TtsNaturalService _tts;
  bool _microphonePermissionGranted = false;
  WebSpeechBridge? _webBridge;
  StreamSubscription<String>? _webResultSub;
  StreamSubscription<bool>? _webIsFinalSub;
  StreamSubscription<void>? _webEndSub;
  StreamSubscription<String>? _webErrorSub;

  // ── Continuous listening & VAD ───────────────────────────────────────────
  Timer? _silenceTimer;
  String _lastTranscript = '';
  final _speechFinalController = StreamController<SpeechFinalEvent>.broadcast();
  Stream<SpeechFinalEvent> get onSpeechFinal => _speechFinalController.stream;
  bool _continuousMode = false;
  bool _isRestartingStt = false;

  @override
  VoiceState build() {
    _tts = TtsNaturalService();
    ref.onDispose(() {
      _silenceTimer?.cancel();
      _speechFinalController.close();
      _tts.dispose();
      _stt?.stop();
      _stt = null;
      _sttInitialized = false;
      _webBridge?.dispose();
    });
    _initTts();
    if (kIsWeb) {
      _webBridge = WebSpeechBridge();
      return VoiceState(isAvailable: _webBridge!.isAvailable);
    } else {
      _initSttOnce();
      return const VoiceState();
    }
  }

  Future<void> _initTts() async {
    try {
      await _tts.init();
      final speed = ref.read(ttsSpeedProvider);
      await _tts.setSpeed(speed);
    } catch (e) {
      debugPrint('[VoiceService] TTS init failed: \$e');
    }
  }

  Future<void> _initSttOnce() async {
    if (_sttInitialized && _stt != null) return;

    final newStt = stt.SpeechToText();
    try {
      final available = await newStt.initialize(
        onError: (_) {
          if (!_continuousMode) {
            state = state.copyWith(isListening: false);
          }
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _silenceTimer?.cancel();
            if (!_continuousMode) {
              state = state.copyWith(isListening: false);
            } else {
              // En mode continu, ne pas redemarrer automatiquement ici.
              // Le VoiceConversationNotifier gère le cycle apres le TTS.
              state = state.copyWith(isListening: false);
            }
          }
        },
      );
      if (available) {
        _stt = newStt;
        _sttInitialized = true;
        state = state.copyWith(isAvailable: true);
      } else {
        state = state.copyWith(isAvailable: false);
      }
    } catch (e) {
      debugPrint('[VoiceService] STT init failed: \$e');
      state = state.copyWith(isAvailable: false);
    }
  }

  Future<bool> _ensureMicrophonePermission() async {
    if (_microphonePermissionGranted) return true;
    final status = await Permission.microphone.status;
    if (status.isGranted) {
      _microphonePermissionGranted = true;
      return true;
    }
    final result = await Permission.microphone.request();
    _microphonePermissionGranted = result.isGranted;
    return result.isGranted;
  }

  // ── Mode conversation continu ─────────────────────────────────────────────

  /// Active le mode ecoute continue (pas de stop/start a chaque tour).
  void setContinuousMode(bool enabled) {
    _continuousMode = enabled;
    if (!enabled) {
      _silenceTimer?.cancel();
    }
  }

  Future<void> _restartSttSoon() async {
    if (_isRestartingStt || !_continuousMode || !_sttInitialized) return;
    _isRestartingStt = true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (_continuousMode && _sttInitialized && _stt != null) {
      // Ne PAS appeler stop() — cela cause un bip système.
      await _startSttListen();
    }
    _isRestartingStt = false;
  }

  Future<void> startListening() async {
    if (kIsWeb && _webBridge != null) {
      // ... (garde le code web existant)
      return;
    }

    final hasPermission = await _ensureMicrophonePermission();
    if (!hasPermission) {
      state = state.copyWith(isListening: false);
      return;
    }

    await _initSttOnce();
    if (_stt == null || !_sttInitialized) {
      state = state.copyWith(isListening: false);
      return;
    }

    if (state.isListening) return;
    await _startSttListen();
  }

  Future<void> _startSttListen() async {
    state = state.copyWith(isListening: true, transcript: '', micLevel: 0.0, speechFinal: false);
    _lastTranscript = '';

    try {
      await _stt!.listen(
        onResult: (result) {
          final text = result.recognizedWords;
          final isFinal = result.finalResult;

          // VAD adaptative : reset timer quand le texte change
          if (text != _lastTranscript && text.isNotEmpty) {
            final hasFinalPunctuation = RegExp(r'[.!?;。！？；]\s*$').hasMatch(text.trim());
            _resetSilenceTimer(hasFinalPunctuation: hasFinalPunctuation);
          }

          _lastTranscript = text;
          state = state.copyWith(
            transcript: text,
            isListening: true,
            speechFinal: false,
          );

          // Si speech_to_text considere final natif, emit aussi
          if (isFinal && text.trim().isNotEmpty) {
            _silenceTimer?.cancel();
            _speechFinalController.add(SpeechFinalEvent(text.trim()));
            state = state.copyWith(speechFinal: true);
          }
        },
        onSoundLevelChange: (level) {
          state = state.copyWith(micLevel: level.abs().clamp(0.0, 120.0) / 120.0);
        },
        localeId: 'fr_FR',
        listenFor: _continuousMode
            ? const Duration(minutes: 30)
            : const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      );
    } catch (e) {
      debugPrint('[VoiceService] STT listen error: \$e');
      _sttInitialized = false;
      _stt = null;
      state = state.copyWith(isListening: false);
    }
  }

  /// VAD adaptative : 400ms si ponctuation finale, 900ms sinon.
  void _resetSilenceTimer({bool hasFinalPunctuation = false}) {
    _silenceTimer?.cancel();
    final delay = hasFinalPunctuation
        ? const Duration(milliseconds: 400)
        : const Duration(milliseconds: 900);
    _silenceTimer = Timer(delay, () {
      if (_lastTranscript.trim().isNotEmpty) {
        debugPrint('[VoiceService] Speech final (silence, punct=$hasFinalPunctuation): ${_lastTranscript.trim()}');
        _speechFinalController.add(SpeechFinalEvent(_lastTranscript.trim()));
        state = state.copyWith(speechFinal: true);
      }
    });
  }

  Future<void> stopListening() async {
    _silenceTimer?.cancel();
    _continuousMode = false;
    if (kIsWeb && _webBridge != null) {
      await _webBridge!.stopListening();
      await _cancelWebSubscriptions();
    } else {
      try {
        await _stt?.stop();
      } catch (_) {}
    }
    state = state.copyWith(isListening: false, micLevel: 0.0, speechFinal: false);
  }

  Future<void> _cancelWebSubscriptions() async {
    await _webResultSub?.cancel();
    await _webIsFinalSub?.cancel();
    await _webEndSub?.cancel();
    await _webErrorSub?.cancel();
    _webResultSub = null;
    _webIsFinalSub = null;
    _webEndSub = null;
    _webErrorSub = null;
  }


  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    if (state.isSpeaking) await _tts.stop();

    final parseResult = EmotionParser.parse(text);
    final emotion = parseResult.hasEmotionTag ? parseResult.emotion : EmotionParser.inferFromText(text);

    state = state.copyWith(isSpeaking: true, currentEmotion: emotion);
    _tts.setEmotion(emotion);

    try {
      await _tts.speakNaturally(text);
    } catch (e) {
      debugPrint('[TTS] Error: \$e');
    } finally {
      state = state.copyWith(isSpeaking: false);
    }
  }

  Future<void> speakWithEmotion(String text, TtsEmotion emotion) async {
    if (text.isEmpty) return;
    if (state.isSpeaking) await _tts.stop();
    _tts.setEmotion(emotion);
    state = state.copyWith(isSpeaking: true, currentEmotion: emotion);
    try {
      await _tts.speakNaturally(text);
    } catch (e) {
      debugPrint('[TTS] Error: \$e');
    } finally {
      state = state.copyWith(isSpeaking: false);
    }
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
    state = state.copyWith(isSpeaking: false);
  }

  void forceReset() {
    _silenceTimer?.cancel();
    _continuousMode = false;
    _stt?.stop();
    _sttInitialized = false;
    _stt = null;
    _tts.stop();
    _webBridge?.stopListening();
    _cancelWebSubscriptions();
    _microphonePermissionGranted = false;
    state = const VoiceState();
  }

  void clearTranscript() {
    state = state.copyWith(transcript: '', speechFinal: false);
    _lastTranscript = '';
  }

  TtsNaturalService get ttsService => _tts;
}

final voiceServiceProvider =
    NotifierProvider<VoiceServiceNotifier, VoiceState>(
  VoiceServiceNotifier.new,
);
