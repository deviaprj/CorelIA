import 'package:corel_ia/core/models/message.dart';
import 'package:corel_ia/features/chat/presentation/chat_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatState', () {
    test('valeurs par défaut', () {
      const state = ChatState();
      expect(state.messages, isEmpty);
      expect(state.isStreaming, isFalse);
      expect(state.isSearching, isFalse);
      expect(state.useSearch, isFalse);
      expect(state.remainingRequests, isNull);
      expect(state.quotaBlocked, isFalse);
      expect(state.error, isNull);
    });

    test('copyWith met à jour les champs', () {
      const state = ChatState();
      final updated = state.copyWith(
        isStreaming: true,
        isSearching: true,
        useSearch: true,
        remainingRequests: 12,
        error: 'oops',
      );
      expect(updated.isStreaming, isTrue);
      expect(updated.isSearching, isTrue);
      expect(updated.useSearch, isTrue);
      expect(updated.remainingRequests, 12);
      expect(updated.error, 'oops');
    });

    test('clearError efface l\'erreur et le blocage de quota', () {
      const state = ChatState(error: kQuotaExceededError, quotaBlocked: true);
      final cleared = state.copyWith(clearError: true, quotaBlocked: false);
      expect(cleared.error, isNull);
      expect(cleared.quotaBlocked, isFalse);
    });

    test('copyWith conserve les messages par défaut', () {
      final messages = [
        Message(
          id: 'm1',
          conversationId: 'c1',
          role: Role.user,
          content: 'salut',
          createdAt: DateTime(2026, 9, 20),
        ),
      ];
      final state = ChatState(messages: messages).copyWith(isStreaming: true);
      expect(state.messages, hasLength(1));
      expect(state.messages.first.content, 'salut');
    });
  });
}
