import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/presentation/chat_notifier.dart';
import 'package:airon_bot/features/chat/domain/message.dart';

void main() {
  group('ChatState', () {
    test('should have correct defaults', () {
      const state = ChatState();

      expect(state.messages, isEmpty);
      expect(state.isStreaming, isFalse);
      expect(state.error, isNull);
      expect(state.remainingRequests, isNull);
    });

    test('should copyWith correctly', () {
      const state = ChatState();
      final msg = Message(
        id: '1',
        conversationId: 'c1',
        role: Role.user,
        content: 'Hello',
        createdAt: DateTime(2024),
      );
      final updated = state.copyWith(
        messages: [msg],
        isStreaming: true,
        error: 'test_error',
        remainingRequests: 5,
      );

      expect(updated.messages.length, equals(1));
      expect(updated.isStreaming, isTrue);
      expect(updated.error, equals('test_error'));
      expect(updated.remainingRequests, equals(5));
    });

    test('copyWith clears error when set to null', () {
      final state = const ChatState().copyWith(error: 'some_error');
      expect(state.error, equals('some_error'));

      final cleared = state.copyWith();
      expect(cleared.error, isNull);
    });

    test('copyWith preserves values when not specified', () {
      const state = ChatState(
        isStreaming: true,
        remainingRequests: 10,
      );
      final updated = state.copyWith(error: 'err');

      expect(updated.isStreaming, isTrue);
      expect(updated.remainingRequests, equals(10));
    });
  });
}
