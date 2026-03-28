import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/presentation/voice_service.dart';

void main() {
  group('VoiceState', () {
    test('should have correct defaults', () {
      const state = VoiceState();

      expect(state.isAvailable, isFalse);
      expect(state.isListening, isFalse);
      expect(state.isSpeaking, isFalse);
      expect(state.transcript, isEmpty);
    });

    test('should copyWith correctly', () {
      const state = VoiceState();
      final updated = state.copyWith(
        isAvailable: true,
        isListening: true,
        transcript: 'Hello',
      );

      expect(updated.isAvailable, isTrue);
      expect(updated.isListening, isTrue);
      expect(updated.isSpeaking, isFalse);
      expect(updated.transcript, equals('Hello'));
    });

    test('copyWith preserves values when not specified', () {
      const state = VoiceState(
        isAvailable: true,
        isListening: true,
        isSpeaking: true,
        transcript: 'Test',
      );
      final updated = state.copyWith(isListening: false);

      expect(updated.isAvailable, isTrue);
      expect(updated.isListening, isFalse);
      expect(updated.isSpeaking, isTrue);
      expect(updated.transcript, equals('Test'));
    });
  });
}
