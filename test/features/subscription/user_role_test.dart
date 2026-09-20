import 'package:corel_ia/core/models/user_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserRole', () {
    test('expose les deux niveaux d\'abonnement', () {
      expect(UserRole.values, containsAll([UserRole.free, UserRole.full]));
      expect(UserRole.free.id, 'free');
      expect(UserRole.full.id, 'full');
    });

    test('isFull distingue les rôles', () {
      expect(UserRole.full.isFull, isTrue);
      expect(UserRole.free.isFull, isFalse);
    });

    test('fromId tolère l\'ancien identifiant pro', () {
      expect(UserRole.fromId('full'), UserRole.full);
      expect(UserRole.fromId('pro'), UserRole.full);
      expect(UserRole.fromId('free'), UserRole.free);
      expect(UserRole.fromId(null), UserRole.free);
      expect(UserRole.fromId('inconnu'), UserRole.free);
    });

    test('les libellés sont explicites', () {
      expect(UserRole.free.label, 'Assistant IA Free');
      expect(UserRole.full.label, 'Agent IA Full');
    });
  });
}
