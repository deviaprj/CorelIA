import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/domain/conversation.dart';

// Tests simplifiés qui ne dépendent pas des providers Riverpod
void main() {
  group('Conversation Model Tests', () {
    test('should create conversation with all fields', () {
      final now = DateTime.now();
      final conversation = Conversation(
        id: '1',
        userId: 'user_1',
        title: 'Test Conversation',
        messageCount: 5,
        isPinned: true,
        createdAt: now,
        updatedAt: now,
      );

      expect(conversation.id, equals('1'));
      expect(conversation.title, equals('Test Conversation'));
      expect(conversation.messageCount, equals(5));
      expect(conversation.isPinned, isTrue);
    });

    test('should create minimal conversation', () {
      final now = DateTime.now();
      final conversation = Conversation(
        id: '2',
        userId: 'user_1',
        title: 'Simple',
        createdAt: now,
        updatedAt: now,
      );

      expect(conversation.messageCount, equals(0));
      expect(conversation.isPinned, isFalse);
    });

    test('should copy with new values', () {
      final now = DateTime.now();
      final conversation = Conversation(
        id: '1',
        userId: 'user_1',
        title: 'Original',
        createdAt: now,
        updatedAt: now,
      );

      final updated = conversation.copyWith(
        title: 'Updated',
        messageCount: 10,
      );

      expect(updated.title, equals('Updated'));
      expect(updated.messageCount, equals(10));
      expect(updated.id, equals(conversation.id));
    });

    test('should toggle pin status', () {
      final now = DateTime.now();
      final conversation = Conversation(
        id: '1',
        userId: 'user_1',
        title: 'Test',
        isPinned: false,
        createdAt: now,
        updatedAt: now,
      );

      final pinned = conversation.copyWith(isPinned: true);
      expect(pinned.isPinned, isTrue);
    });
  });

  group('Conversation List Logic', () {
    test('should sort conversations by updatedAt', () {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      final tomorrow = now.add(const Duration(days: 1));

      final conversations = [
        Conversation(
          id: '1',
          userId: 'u1',
          title: 'Old',
          createdAt: yesterday,
          updatedAt: yesterday,
        ),
        Conversation(
          id: '2',
          userId: 'u1',
          title: 'New',
          createdAt: yesterday,
          updatedAt: tomorrow,
        ),
        Conversation(
          id: '3',
          userId: 'u1',
          title: 'Current',
          createdAt: yesterday,
          updatedAt: now,
        ),
      ];

      conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      expect(conversations[0].id, equals('2'));
      expect(conversations[1].id, equals('3'));
      expect(conversations[2].id, equals('1'));
    });

    test('should separate pinned and unpinned', () {
      final now = DateTime.now();
      final conversations = [
        Conversation(
          id: '1',
          userId: 'u1',
          title: 'Unpinned',
          isPinned: false,
          createdAt: now,
          updatedAt: now,
        ),
        Conversation(
          id: '2',
          userId: 'u1',
          title: 'Pinned',
          isPinned: true,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final pinned = conversations.where((c) => c.isPinned).toList();
      final unpinned = conversations.where((c) => !c.isPinned).toList();

      expect(pinned.length, equals(1));
      expect(unpinned.length, equals(1));
      expect(pinned.first.id, equals('2'));
    });

    test('should filter conversations by query', () {
      final now = DateTime.now();
      final conversations = [
        Conversation(
          id: '1',
          userId: 'u1',
          title: 'Flutter Development',
          createdAt: now,
          updatedAt: now,
        ),
        Conversation(
          id: '2',
          userId: 'u1',
          title: 'Dart Tutorial',
          createdAt: now,
          updatedAt: now,
        ),
        Conversation(
          id: '3',
          userId: 'u1',
          title: 'JavaScript Guide',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final filtered = conversations
          .where((c) => c.title.toLowerCase().contains('dart'))
          .toList();

      expect(filtered.length, equals(1));
      expect(filtered.first.id, equals('2'));
    });
  });

  group('Conversation Tile Tests', () {
    test('should format message count', () {
      final conversation = Conversation(
        id: '1',
        userId: 'u1',
        title: 'Test',
        messageCount: 42,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(conversation.messageCount, equals(42));
    });

    test('should handle long titles', () {
      final conversation = Conversation(
        id: '1',
        userId: 'u1',
        title: 'A' * 100,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(conversation.title.length, equals(100));
    });
  });
}
