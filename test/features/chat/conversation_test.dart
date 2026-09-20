import 'package:corel_ia/core/models/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Conversation', () {
    final base = Conversation(
      id: 'c1',
      userId: 'u1',
      title: 'Nouvelle conversation',
      createdAt: DateTime(2026, 9, 20),
      updatedAt: DateTime(2026, 9, 20),
    );

    test('copyWith met à jour titre et compteur', () {
      final updated = base.copyWith(title: 'Ma question', messageCount: 4);
      expect(updated.title, 'Ma question');
      expect(updated.messageCount, 4);
      expect(updated.id, base.id);
      expect(updated.createdAt, base.createdAt);
    });

    test('copyWith conserve les valeurs non fournies', () {
      final updated = base.copyWith(updatedAt: DateTime(2026, 9, 21));
      expect(updated.title, base.title);
      expect(updated.userId, base.userId);
      expect(updated.updatedAt, DateTime(2026, 9, 21));
    });
  });
}
