import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../../../core/providers/app_providers.dart';
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

  const VoiceState({
    this.isAvailable = false,
    this.isListening = false,
    this.isSpeaking = false,
    this.transcript = '',
    this.currentEmotion = TtsEmotion.neutral,
    this.micLevel = 0.0,
  });

  VoiceState copyWith({
    bool? isAvailable,
    bool? isListening,
    bool? isSpeaking,
    String? transcript,
    TtsEmotion? currentEmotion,
    double? micLevel,
  }) =>
      VoiceState(
        isAvailable: isAvailable ?? this.isAvailable,
        isListening: isListening ?? this.isListening,
        isSpeaking: isSpeaking ?? this.isSpeaking,
        transcript: transcript ?? this.transcript,
        currentEmotion: currentEmotion ?? this.currentEmotion,
        micLevel: micLevel ?? this.micLevel,
      );
}

class VoiceServiceNotifier extends Notifier<VoiceState> {
  stt.SpeechToText? _stt;
  bool _sttInitialized = false;
  late final TtsNaturalService _tts;
  bool _microphonePermissionGranted = false;

  @override
  VoiceState build() {
    _tts = TtsNaturalService();
    ref.onDispose(() {
      _tts.dispose();
      _stt?.stop();
      _stt = null;
      _sttInitialized = false;
    });
    _initTts();
    // Initialiser le STT une seule fois au build
    _initSttOnce();
    return const VoiceState();
  }

  Future<void> _initTts() async {
    try {
      await _tts.init();
      final speed = ref.read(ttsSpeedProvider);
      await _tts.setSpeed(speed);
    } catch (e) {
      debugPrint('[VoiceService] TTS init failed: $e');
    }
  }

  /// Initialise le STT une seule fois. Ne recrée JAMAIS l'instance sauf
  /// si elle est dans un état irrécupérable (null ou _sttInitialized = false).
  Future<void> _initSttOnce() async {
    if (_sttInitialized && _stt != null) return;

    final newStt = stt.SpeechToText();
    try {
      final available = await newStt.initialize(
        onError: (_) {
          state = state.copyWith(isListening: false);
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            state = state.copyWith(isListening: false);
          }
        },
      );
      if (available) {
        _stt = newStt;
        _sttInitialized = true;
        state = state.copyWith(isAvailable: true);
        debugPrint('[VoiceService] STT initialized (once)');
      } else {
        debugPrint('[VoiceService] STT not available on this device');
        state = state.copyWith(isAvailable: false);
      }
    } catch (e) {
      debugPrint('[VoiceService] STT init failed: $e');
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

    debugPrint('[VoiceService] Requesting microphone permission');
    final result = await Permission.microphone.request();
    if (result.isGranted) {
      _microphonePermissionGranted = true;
      return true;
    }

    debugPrint('[VoiceService] Microphone permission denied');
    return false;
  }

  /// Démarre l'écoute. Réutilise l'instance STT existante.
  /// Appelle .listen() sur l'instance déjà initialisée → pas de bip de reconnexion.
  Future<void> startListening() async {
    final hasPermission = await _ensureMicrophonePermission();
    if (!hasPermission) {
      state = state.copyWith(isListening: false);
      return;
    }

    // S'assurer que le STT est initialisé (une seule fois)
    await _initSttOnce();
    if (_stt == null || !_sttInitialized) {
      state = state.copyWith(isListening: false);
      return;
    }

    // Si déjà en écoute, ne rien faire (évite le double listen)
    if (state.isListening) return;

    state = state.copyWith(isListening: true, transcript: '', micLevel: 0.0);
    try {
      await _stt!.listen(
        onResult: (result) {
          state = state.copyWith(
            transcript: result.recognizedWords,
            isListening: !result.finalResult,
          );
        },
        onSoundLevelChange: (level) {
          state = state.copyWith(micLevel: level.abs().clamp(0.0, 120.0) / 120.0);
        },
        localeId: 'fr_FR',
        listenFor: const Duration(seconds: 120),
        pauseFor: const Duration(seconds: 10),
        listenMode: stt.ListenMode.dictation,
      );
    } catch (e) {
      debugPrint('[VoiceService] STT listen error: $e');
      // Si l'instance est corrompue, la réinitialiser au prochain appel
      _sttInitialized = false;
      _stt = null;
      state = state.copyWith(isListening: false);
    }
  }

  Future<void> stopListening() async {
    try {
      await _stt?.stop();
    } catch (_) {}
    state = state.copyWith(isListening: false, micLevel: 0.0);
  }

  /// Lecture TTS naturelle avec détection d'émotion.
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
      debugPrint('[TTS] Error: $e');
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
      debugPrint('[TTS] Error: $e');
    } finally {
      state = state.copyWith(isSpeaking: false);
    }
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
    state = state.copyWith(isSpeaking: false);
  }

  void forceReset() {
    _stt?.stop();
    _sttInitialized = false;
    _stt = null;
    _tts.stop();
    _microphonePermissionGranted = false;
    state = const VoiceState();
  }

  TtsNaturalService get ttsService => _tts;
}

final voiceServiceProvider =
    NotifierProvider<VoiceServiceNotifier, VoiceState>(
  VoiceServiceNotifier.new,
);