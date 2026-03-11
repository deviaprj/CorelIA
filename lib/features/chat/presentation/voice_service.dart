import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

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
  late final FlutterTts _tts;

  @override
  VoiceState build() {
    _stt = stt.SpeechToText();
    _tts = FlutterTts();
    _init();
    return const VoiceState();
  }

  Future<void> _init() async {
    final available = await _stt.initialize(
      onError: (_) => state = state.copyWith(isListening: false),
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          state = state.copyWith(isListening: false);
        }
      },
    );
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.9);
    state = state.copyWith(isAvailable: available);
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
      pauseFor: const Duration(seconds: 5),
    );
  }

  Future<void> stopListening() async {
    await _stt.stop();
    state = state.copyWith(isListening: false);
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    if (state.isSpeaking) await _tts.stop();
    state = state.copyWith(isSpeaking: true);
    try {
      await _tts.speak(text);
      _tts.setCompletionHandler(() {
        state = state.copyWith(isSpeaking: false);
      });
    } catch (e) {
      state = state.copyWith(isSpeaking: false);
      debugPrint('[TTS] Error: $e');
    }
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
    state = state.copyWith(isSpeaking: false);
  }
}

final voiceServiceProvider =
    NotifierProvider<VoiceServiceNotifier, VoiceState>(
  VoiceServiceNotifier.new,
);
