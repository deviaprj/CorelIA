import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// État du service vocal avancé.
class VoiceAdvancedState {
  final bool isRecording;
  final bool isPlaying;
  final String transcript;
  final double recordingDurationMs;
  final bool hasPermission;

  const VoiceAdvancedState({
    this.isRecording = false,
    this.isPlaying = false,
    this.transcript = '',
    this.recordingDurationMs = 0,
    this.hasPermission = false,
  });

  VoiceAdvancedState copyWith({
    bool? isRecording,
    bool? isPlaying,
    String? transcript,
    double? recordingDurationMs,
    bool? hasPermission,
  }) =>
      VoiceAdvancedState(
        isRecording: isRecording ?? this.isRecording,
        isPlaying: isPlaying ?? this.isPlaying,
        transcript: transcript ?? this.transcript,
        recordingDurationMs: recordingDurationMs ?? this.recordingDurationMs,
        hasPermission: hasPermission ?? this.hasPermission,
      );
}

/// Service vocal avancé utilisant `record` + `just_audio`.
///
/// Responsabilités :
/// - Enregistrement audio haute qualité (WAV/PCM) avec `record`
/// - Lecture streaming avec `just_audio` (interruption possible)
/// - Gestion des permissions micro
///
/// Ce service est conçu pour être étendu vers un backend Ollama local
/// (modèles `whisper` pour STT, `piper` pour TTS) en mode Pro.
/// Aucun service vocal payant n'est utilisé.
class VoiceAdvancedNotifier extends Notifier<VoiceAdvancedState> {
  late final AudioRecorder _recorder;
  late final AudioPlayer _player;
  Timer? _durationTimer;
  DateTime? _recordingStart;

  @override
  VoiceAdvancedState build() {
    _recorder = AudioRecorder();
    _player = AudioPlayer();

    ref.onDispose(() async {
      await _stopRecordingInternal();
      await _player.dispose();
      await _recorder.dispose();
      _durationTimer?.cancel();
    });

    _init();
    return const VoiceAdvancedState();
  }

  Future<void> _init() async {
    final hasMic = await Permission.microphone.request().isGranted;
    state = state.copyWith(hasPermission: hasMic);
  }

  /// Démarre l'enregistrement audio.
  Future<void> startRecording() async {
    if (!state.hasPermission || state.isRecording) return;

    try {
      // Config WAV pour qualité max (Ollama STT préfère)
      const config = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      );

      final path = await _getRecordingPath();
      await _recorder.start(config, path: path);

      _recordingStart = DateTime.now();
      _durationTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) {
          if (_recordingStart != null) {
            final elapsed = DateTime.now().difference(_recordingStart!).inMilliseconds;
            state = state.copyWith(recordingDurationMs: elapsed.toDouble());
          }
        },
      );

      state = state.copyWith(
        isRecording: true,
        transcript: '',
        recordingDurationMs: 0,
      );
    } catch (e) {
      debugPrint('[VoiceAdvanced] Erreur enregistrement : $e');
      state = state.copyWith(isRecording: false);
    }
  }

  /// Arrête l'enregistrement et retourne le chemin du fichier.
  Future<String?> stopRecording() async {
    final path = await _stopRecordingInternal();
    _durationTimer?.cancel();
    _recordingStart = null;
    state = state.copyWith(isRecording: false, recordingDurationMs: 0);
    return path;
  }

  Future<String?> _stopRecordingInternal() async {
    try {
      return await _recorder.stop();
    } catch (e) {
      debugPrint('[VoiceAdvanced] Erreur arrêt : $e');
      return null;
    }
  }

  /// Joue un fichier audio local ou distant.
  Future<void> playAudio(String sourcePath) async {
    if (state.isPlaying) await stopAudio();

    try {
      await _player.setAudioSource(AudioSource.uri(Uri.parse(sourcePath)));
      await _player.play();
      state = state.copyWith(isPlaying: true);

      _player.processingStateStream.listen((ps) {
        if (ps == ProcessingState.completed) {
          state = state.copyWith(isPlaying: false);
        }
      });
    } catch (e) {
      debugPrint('[VoiceAdvanced] Erreur lecture : $e');
      state = state.copyWith(isPlaying: false);
    }
  }

  /// Arrête la lecture audio.
  Future<void> stopAudio() async {
    await _player.stop();
    state = state.copyWith(isPlaying: false);
  }

  /// Interrompt la lecture (pause).
  Future<void> pauseAudio() async {
    await _player.pause();
    state = state.copyWith(isPlaying: false);
  }

  Future<String> _getRecordingPath() async {
    final dir = Directory.systemTemp;
    final name = 'airon_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    return '${dir.path}/$name';
  }
}

final voiceAdvancedProvider =
    NotifierProvider<VoiceAdvancedNotifier, VoiceAdvancedState>(
  VoiceAdvancedNotifier.new,
);
