import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../../../core/providers/app_providers.dart';
import 'tts_natural_service.dart';

class VoiceState {
  final bool isAvailable;
  final bool isListening;
  final bool isSpeaking;
  final String transcript;

  const VoiceState({
    this.isAvailable = false,
    this.isListening = false,
    this.isSpeaking = false,
    this.transcript = '',
  });

  VoiceState copyWith({
    bool? isAvailable,
    bool? isListening,
    bool? isSpeaking,
    String? transcript,
  }) =>
      VoiceState(
        isAvailable: isAvailable ?? this.isAvailable,
        isListening: isListening ?? this.isListening,
        isSpeaking: isSpeaking ?? this.isSpeaking,
        transcript: transcript ?? this.transcript,
      );
}

class VoiceServiceNotifier extends Notifier<VoiceState> {
  stt.SpeechToText? _stt;
  late final TtsNaturalService _tts;
  bool _microphonePermissionGranted = false;

  @override
  VoiceState build() {
    _tts = TtsNaturalService();
    ref.onDispose(() {
      _tts.dispose();
      _stt?.stop();
      _stt = null;
    });
    // Init TTS uniquement (le STT sera initialise a la demande dans startListening)
    _initTts();
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

  /// Cree une instance fraiche de SpeechToText et l'initialise.
  /// Appele a chaque entree en ecoute pour garantir un etat propre.
  Future<bool> _createAndInitStt() async {
    // Detruire l'ancienne instance proprement
    if (_stt != null) {
      try {
        await _stt!.stop();
      } catch (_) {}
      _stt = null;
    }

    final newStt = stt.SpeechToText();
    try {
      final available = await newStt.initialize(
        onError: (_) {
          if (_stt == newStt) {
            state = state.copyWith(isListening: false);
          }
        },
        onStatus: (status) {
          if (_stt == newStt &&
              (status == 'done' || status == 'notListening')) {
            state = state.copyWith(isListening: false);
          }
        },
      );
      if (available) {
        _stt = newStt;
        state = state.copyWith(isAvailable: true);
        debugPrint('[VoiceService] STT initialized successfully');
        return true;
      } else {
        debugPrint('[VoiceService] STT not available on this device');
        state = state.copyWith(isAvailable: false);
        return false;
      }
    } catch (e) {
      debugPrint('[VoiceService] STT init failed: $e');
      state = state.copyWith(isAvailable: false);
      return false;
    }
  }

  /// Verifie et demande la permission microphone si necessaire.
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

  /// Demarre l'ecoute vocale.
  /// Chaque appel cree une instance STT fraiche pour eviter
  /// les etats corrompus herites d'une session precedente.
  Future<void> startListening() async {
    // 1. Si deja en ecoute, arreter proprement d'abord
    if (state.isListening) {
      await stopListening();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    // 2. Permission microphone
    final hasPermission = await _ensureMicrophonePermission();
    if (!hasPermission) {
      state = state.copyWith(isListening: false);
      return;
    }

    // 3. Creer et initialiser une instance STT fraiche
    final sttReady = await _createAndInitStt();
    if (!sttReady || _stt == null) {
      state = state.copyWith(isListening: false);
      return;
    }

    // 4. Demarrer l'ecoute
    state = state.copyWith(isListening: true, transcript: '');
    try {
      await _stt!.listen(
        onResult: (result) {
          state = state.copyWith(
            transcript: result.recognizedWords,
            isListening: !result.finalResult,
          );
        },
        localeId: 'fr_FR',
        listenFor: const Duration(seconds: 120),
        pauseFor: const Duration(seconds: 10),
        listenMode: stt.ListenMode.dictation,
      );
    } catch (e) {
      debugPrint('[VoiceService] STT listen error: $e');
      state = state.copyWith(isListening: false);
    }
  }

  Future<void> stopListening() async {
    try {
      await _stt?.stop();
    } catch (_) {}
    state = state.copyWith(isListening: false);
  }

  /// Lecture TTS naturelle.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    if (state.isSpeaking) await _tts.stop();
    state = state.copyWith(isSpeaking: true);
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

  /// Reinitialisation complete — coupe micro + TTS, reinitialise permissions.
  void forceReset() {
    _stt?.stop();
    _stt = null;
    _tts.stop();
    _microphonePermissionGranted = false;
    state = state.copyWith(
      isListening: false,
      isSpeaking: false,
      transcript: '',
      isAvailable: false,
    );
  }
}

final voiceServiceProvider =
    NotifierProvider<VoiceServiceNotifier, VoiceState>(
  VoiceServiceNotifier.new,
);
