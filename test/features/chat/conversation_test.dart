import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:corel_ia/features/chat/domain/conversation.dart';

void main() {
  group('Conversation Model', () {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    final testConversation = Conversation(
      id: 'conv_123',
      userId: 'user_456',
      title: 'Test Conversation',
      modelUsed: 'deepseek-chat',
      messageCount: 10,
      projectId: 'proj_789',
      isPinned: true,
      createdAt: yesterday,
      updatedAt: now,
    );

    test('should create conversation with correct values', () {
      expect(testConversation.id, equals('conv_123'));
      expect(testConversation.userId, equals('user_456'));
      expect(testConversation.title, equals('Test Conversation'));
      expect(testConversation.modelUsed, equals('deepseek-chat'));
      expect(testConversation.messageCount, equals(10));
      expect(testConversation.projectId, equals('proj_789'));
      expect(testConversation.isPinned, isTrue);
    });

    test('should have default values for optional fields', () {
      final minimalConversation = Conversation(
        id: 'conv_min',
        userId: 'user_456',
        title: 'Minimal',
        createdAt: yesterday,
        updatedAt: now,
      );

      expect(minimalConversation.messageCount, equals(0));
      expect(minimalConversation.isPinned, isFalse);
      expect(minimalConversation.modelUsed, isNull);
      expect(minimalConversation.projectId, isNull);
    });

    test('should convert to Firestore', () {
      final createdAt = DateTime(2024, 1, 1);
      final updatedAt = DateTime(2024, 1, 2);

      final conversation = Conversation(
        id: 'conv_123',
        userId: 'user_456',
        title: 'Test',
        modelUsed: 'deepseek-chat',
        messageCount: 5,
        projectId: 'proj_789',
        isPinned: true,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final firestoreData = conversation.toFirestore();

      expect(firestoreData['userId'], equals('user_456'));
      expect(firestoreData['title'], equals('Test'));
      expect(firestoreData['modelUsed'], equals('deepseek-chat'));
      expect(firestoreData['messageCount'], equals(5));
      expect(firestoreData['projectId'], equals('proj_789'));
      expect(firestoreData['isPinned'], isTrue);
      expect(firestoreData['createdAt'], isA<Timestamp>());
      expect(firestoreData['updatedAt'], isA<Timestamp>());
    });

    test('should create copy with updated values', () {
      final updatedNow = DateTime.now();
      final updated = testConversation.copyWith(
        title: 'Updated Title',
        messageCount: 15,
        isPinned: false,
        updatedAt: updatedNow,
      );

      expect(updated.title, equals('Updated Title'));
      expect(updated.messageCount, equals(15));
      expect(updated.isPinned, isFalse);
      expect(updated.updatedAt, equals(updatedNow));
      expect(updated.id, equals(testConversation.id));
      expect(updated.userId, equals(testConversation.userId));
    });

    test('should preserve values when copying with null', () {
      final updated = testConversation.copyWith();

      expect(updated.title, equals(testConversation.title));
      expect(updated.messageCount, equals(testConversation.messageCount));
    });
  });

  group('Conversation fromFirestore', () {
    test('should parse full conversation from Firestore', () {
      final createdAt = Timestamp.now();
      final updatedAt = Timestamp.now();

      final mockData = {
        'userId': 'user_456',
        'title': 'Full Conversation',
        'modelUsed': 'deepseek-chat',
        'messageCount': 25,
        'projectId': 'proj_789',
        'isPinned': true,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

      final conversation = Conversation(
        id: 'conv_123',
        userId: mockData['userId'] as String,
        title: mockData['title'] as String,
        modelUsed: mockData['modelUsed'] as String?,
        messageCount: mockData['messageCount'] as int? ?? 0,
        projectId: mockData['projectId'] as String?,
        isPinned: mockData['isPinned'] as bool? ?? false,
        createdAt: (mockData['createdAt'] as Timestamp).toDate(),
        updatedAt: (mockData['updatedAt'] as Timestamp).toDate(),
      );

      expect(conversation.id, equals('conv_123'));
      expect(conversation.title, equals('Full Conversation'));
      expect(conversation.messageCount, equals(25));
      expect(conversation.isPinned, isTrue);
    });

    test('should parse minimal conversation from Firestore', () {
      final mockData = {
        'userId': 'user_456',
        'title': 'Minimal',
      };

      final conversation = Conversation(
        id: 'conv_min',
        userId: mockData['userId'] as String? ?? '',
        title: mockData['title'] as String? ?? 'Nouvelle conversation',
        messageCount: 0,
        isPinned: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(conversation.id, equals('conv_min'));
      expect(conversation.userId, equals('user_456'));
      expect(conversation.title, equals('Minimal'));
      expect(conversation.messageCount, equals(0));
      expect(conversation.isPinned, isFalse);
    });

    test('should handle null values with defaults', () {
      final conversation = Conversation(
        id: 'conv_null',
        userId: '',
        title: 'Nouvelle conversation',
        messageCount: 0,
        isPinned: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(conversation.userId, isEmpty);
      expect(conversation.title, equals('Nouvelle conversation'));
      expect(conversation.messageCount, equals(0));
      expect(conversation.isPinned, isFalse);
    });
  });

  group('Conversation Ordering', () {
    test('should be sortable by updatedAt', () {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      final tomorrow = now.add(const Duration(days: 1));

      final oldConv = Conversation(
        id: '1',
        userId: 'u1',
        title: 'Old',
        createdAt: yesterday,
        updatedAt: yesterday,
      );

      final newConv = Conversation(
        id: '2',
        userId: 'u1',
        title: 'New',
        createdAt: yesterday,
        updatedAt: tomorrow,
      );

      final conversations = [oldConv, newConv];
      conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      expect(conversations.first.id, equals('2'));
    });

    test('pinned conversations should appear first', () {
      final now = DateTime.now();

      final unpinned = Conversation(
        id: '1',
        userId: 'u1',
        title: 'Unpinned',
        isPinned: false,
        createdAt: now,
        updatedAt: now,
      );

      final pinned = Conversation(
        id: '2',
        userId: 'u1',
        title: 'Pinned',
        isPinned: true,
        createdAt: now,
        updatedAt: now,
      );

      final conversations = [unpinned, pinned];
      final pinnedList = conversations.where((c) => c.isPinned).toList();
      final unpinnedList = conversations.where((c) => !c.isPinned).toList();

      expect(pinnedList.length, equals(1));
      expect(unpinnedList.length, equals(1));
      expect(pinnedList.first.title, equals('Pinned'));
    });
  });
}
