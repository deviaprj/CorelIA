import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
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
  late final stt.SpeechToText _stt;
  late final TtsNaturalService _tts;

  @override
  VoiceState build() {
    _stt = stt.SpeechToText();
    _tts = TtsNaturalService();
    ref.onDispose(() {
      _tts.dispose();
      _stt.stop();
    });
    _init();
    return const VoiceState();
  }

  Future<void> _init() async {
    // Initialisation asynchrone ; si elle echoue on reessayera au premier tap
    try {
      final available = await _stt.initialize(
        onError: (_) => state = state.copyWith(isListening: false),
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            state = state.copyWith(isListening: false);
          }
        },
      );
      await _tts.init();
      // Appliquer la vitesse stockee dans les preferences
      final speed = ref.read(ttsSpeedProvider);
      await _tts.setSpeed(speed);
      state = state.copyWith(isAvailable: available);
    } catch (e) {
      debugPrint('[VoiceService] Init STT echouee : $e');
      state = state.copyWith(isAvailable: false);
    }
  }

  /// Initialise a la demande si la premiere tentative a echoue
  Future<bool> ensureInitialized() async {
    if (state.isAvailable) return true;
    await _init();
    return state.isAvailable;
  }

  Future<void> startListening() async {
    if (!state.isAvailable || state.isListening) return;
    state = state.copyWith(isListening: true, transcript: '');
    await _stt.listen(
      onResult: (result) {
        state = state.copyWith(
          transcript: result.recognizedWords,
          isListening: !result.finalResult,
        );
      },
      localeId: 'fr_FR',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }

  Future<void> stopListening() async {
    await _stt.stop();
    state = state.copyWith(isListening: false);
  }

  /// Lecture TTS naturelle avec decoupage intelligent et pauses.
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

  /// Force la reinitialisation de l'etat vocal (micro + TTS coupes).
  /// Utilise quand on quitte le mode conversation pour eviter
  /// qu'un prochain startListening() soit bloque par un etat fantome.
  void forceReset() {
    _stt.stop();
    _tts.stop();
    state = state.copyWith(isListening: false, isSpeaking: false, transcript: '');
  }
}

final voiceServiceProvider =
    NotifierProvider<VoiceServiceNotifier, VoiceState>(
  VoiceServiceNotifier.new,
);
