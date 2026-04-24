import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../core/api/dio_client.dart';
import 'voice_advanced_service.dart';
import 'voice_service.dart';

/// État du mode conversation vocale mains-libres.
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

  const VoiceConversationStatus({
    this.state = VoiceConversationState.idle,
    this.transcript,
    this.error,
  });

  VoiceConversationStatus copyWith({
    VoiceConversationState? state,
    String? transcript,
    String? error,
  }) =>
      VoiceConversationStatus(
        state: state ?? this.state,
        transcript: transcript ?? this.transcript,
        error: error ?? this.error,
      );
}

/// Service de conversation vocale mains-libres.
///
/// Flux :
/// 1. Enregistrement audio (voice_advanced_service)
/// 2. Envoi au backend /voice/stt (Ollama whisper)
/// 3. Récupération du texte transcrit
/// 4. Envoi au chat
/// 5. Réception de la réponse texte
/// 6. Lecture TTS (voice_service / flutter_tts natif en fallback)
class VoiceConversationNotifier extends Notifier<VoiceConversationStatus> {
  late final VoiceAdvancedNotifier _voiceAdvanced;
  late final VoiceServiceNotifier _voiceBasic;
  final _dio = DioClientFactory.create();
  bool _isActive = false;

  @override
  VoiceConversationStatus build() {
    _voiceAdvanced = ref.read(voiceAdvancedProvider.notifier);
    _voiceBasic = ref.read(voiceServiceProvider.notifier);

    ref.onDispose(() {
      _isActive = false;
    });

    return const VoiceConversationStatus();
  }

  /// Démarre une boucle conversation vocale.
  Future<void> startConversation() async {
    if (_isActive) return;
    _isActive = true;

    state = state.copyWith(state: VoiceConversationState.listening);

    // 1. Enregistrer l'audio
    try {
      await _voiceAdvanced.startRecording();
      // Attendre 5s ou jusqu'à ce que l'utilisateur arrête
      await Future.delayed(const Duration(seconds: 5));
      final audioPath = await _voiceAdvanced.stopRecording();

      if (audioPath == null || !_isActive) {
        _reset();
        return;
      }

      // 2. Envoyer au backend STT
      state = state.copyWith(state: VoiceConversationState.processingStt);
      final transcript = await _sendToStt(audioPath);

      if (transcript == null || transcript.isEmpty || !_isActive) {
        _reset();
        return;
      }

      state = state.copyWith(transcript: transcript);
      debugPrint('[VoiceConversation] Transcription : $transcript');

      // 3. Transmettre le texte au caller (chat)
      // Cette étape est gérée par l'appelant via onTranscript
      // qui doit appeler sendMessage sur le ChatNotifier.
      // On arrête ici et on attend la réponse.
      state = state.copyWith(state: VoiceConversationState.thinking);

      // Nettoyer le fichier temporaire
      try {
        await File(audioPath).delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('[VoiceConversation] Erreur : $e');
      state = state.copyWith(state: VoiceConversationState.error, error: e.toString());
    }
  }

  /// Appelé par l'UI quand la réponse chat est reçue.
  Future<void> playResponse(String text) async {
    if (!_isActive) return;
    state = state.copyWith(state: VoiceConversationState.speaking);

    try {
      // Essayer TTS backend d'abord, sinon fallback natif
      await _voiceBasic.speak(text);

      // Attendre la fin de la lecture
      await Future.delayed(const Duration(seconds: 1));
      while (_voiceBasic.state.isSpeaking && _isActive) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (e) {
      debugPrint('[VoiceConversation] TTS erreur : $e');
    }

    if (_isActive) {
      // Relancer la boucle
      state = state.copyWith(state: VoiceConversationState.idle);
      await startConversation();
    }
  }

  void stop() {
    _isActive = false;
    _voiceAdvanced.stopRecording();
    _voiceBasic.stopSpeaking();
    _reset();
  }

  void _reset() {
    state = const VoiceConversationStatus();
  }

  Future<String?> _sendToStt(String audioPath) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) return null;

      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(
          audioPath,
          filename: p.basename(audioPath),
        ),
        'model': 'whisper',
      });

      final response = await _dio.post('/voice/stt', data: formData);
      if (response.statusCode == 200 && response.data is Map) {
        return response.data['text'] as String?;
      }
      return null;
    } on DioException catch (e) {
      debugPrint('[VoiceConversation] STT backend error : ${e.message}');
      // Fallback silencieux : retourner null pour que l'UI bascule sur speech_to_text
      return null;
    } catch (e) {
      debugPrint('[VoiceConversation] STT error : $e');
      return null;
    }
  }
}

final voiceConversationProvider =
    NotifierProvider<VoiceConversationNotifier, VoiceConversationStatus>(
  VoiceConversationNotifier.new,
);
