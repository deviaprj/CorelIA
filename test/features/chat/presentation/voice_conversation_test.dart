import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/presentation/voice_conversation_service.dart';
import 'package:airon_bot/features/chat/presentation/edge_tts_service.dart';

void main() {
  group('VoiceConversationState', () {
    test('tous les états existent', () {
      expect(VoiceConversationState.values.length, 6);
      expect(VoiceConversationState.values, contains(VoiceConversationState.idle));
      expect(VoiceConversationState.values, contains(VoiceConversationState.listening));
      expect(VoiceConversationState.values, contains(VoiceConversationState.thinking));
      expect(VoiceConversationState.values, contains(VoiceConversationState.speaking));
      expect(VoiceConversationState.values, contains(VoiceConversationState.processingStt));
      expect(VoiceConversationState.values, contains(VoiceConversationState.error));
    });
  });

  group('VoiceConversationStatus', () {
    test('constructeur par défaut', () {
      const status = VoiceConversationStatus();
      expect(status.state, VoiceConversationState.idle);
      expect(status.transcript, isNull);
      expect(status.error, isNull);
      expect(status.emotion, TtsEmotion.neutral);
    });

    test('copyWith préserve les valeurs non modifiées', () {
      const original = VoiceConversationStatus(
        state: VoiceConversationState.speaking,
        transcript: 'Bonjour',
        emotion: TtsEmotion.joyful,
      );
      final copied = original.copyWith(error: 'Test error');
      expect(copied.state, VoiceConversationState.speaking);
      expect(copied.transcript, 'Bonjour');
      expect(copied.emotion, TtsEmotion.joyful);
      expect(copied.error, 'Test error');
    });

    test('copyWith modifie les valeurs spécifiées', () {
      const original = VoiceConversationStatus(
        state: VoiceConversationState.idle,
        emotion: TtsEmotion.neutral,
      );
      final copied = original.copyWith(
        state: VoiceConversationState.listening,
        emotion: TtsEmotion.excited,
      );
      expect(copied.state, VoiceConversationState.listening);
      expect(copied.emotion, TtsEmotion.excited);
    });
  });

  group('Emotion integration', () {
    test('émotion par défaut est neutral', () {
      const status = VoiceConversationStatus();
      expect(status.emotion, TtsEmotion.neutral);
    });

    test('émotion peut être mise à jour via copyWith', () {
      const status = VoiceConversationStatus(emotion: TtsEmotion.sad);
      final updated = status.copyWith(emotion: TtsEmotion.excited);
      expect(updated.emotion, TtsEmotion.excited);
    });
  });
}