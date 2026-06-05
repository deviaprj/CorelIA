import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/features/projects/domain/project.dart';

void main() {
  group('Project', () {
    test('should create with factory constructor', () {
      final project = Project.create(
        userId: 'user1',
        name: 'Test Project',
        description: 'A test project',
      );

      expect(project.userId, equals('user1'));
      expect(project.name, equals('Test Project'));
      expect(project.description, equals('A test project'));
      expect(project.id, isNotEmpty);
      expect(project.conversationIds, isEmpty);
    });

    test('should create with default empty description', () {
      final project = Project.create(
        userId: 'user1',
        name: 'Test',
      );

      expect(project.description, equals(''));
    });

    test('should convert to Firestore map', () {
      final now = DateTime(2024, 1, 1);
      final project = Project(
        id: 'p1',
        userId: 'user1',
        name: 'Test',
        description: 'Desc',
        conversationIds: ['c1', 'c2'],
        createdAt: now,
        updatedAt: now,
      );

      final map = project.toFirestore();
      expect(map['userId'], equals('user1'));
      expect(map['name'], equals('Test'));
      expect(map['description'], equals('Desc'));
      expect(map['conversationIds'], equals(['c1', 'c2']));
    });

    test('should copyWith correctly', () {
      final now = DateTime(2024, 1, 1);
      final project = Project(
        id: 'p1',
        userId: 'user1',
        name: 'Old Name',
        description: 'Old Desc',
        createdAt: now,
        updatedAt: now,
      );

      final updated = project.copyWith(
        name: 'New Name',
        description: 'New Desc',
      );

      expect(updated.name, equals('New Name'));
      expect(updated.description, equals('New Desc'));
      expect(updated.id, equals('p1'));
      expect(updated.userId, equals('user1'));
    });

    test('copyWith preserves original values when not specified', () {
      final now = DateTime(2024, 1, 1);
      final project = Project(
        id: 'p1',
        userId: 'user1',
        name: 'Name',
        description: 'Desc',
        conversationIds: ['c1'],
        createdAt: now,
        updatedAt: now,
      );

      final updated = project.copyWith(name: 'New');

      expect(updated.description, equals('Desc'));
      expect(updated.conversationIds, equals(['c1']));
    });
  });
}
