import 'package:corel_ia/core/models/user_role.dart';
import 'package:corel_ia/features/subscription/domain/quota_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuotaPolicies', () {
    test('Free limite les requêtes et les pièces jointes', () {
      expect(QuotaPolicies.free.unlimited, isFalse);
      expect(QuotaPolicies.free.limited, isTrue);
      expect(QuotaPolicies.free.dailyRequests, 20);
      expect(QuotaPolicies.free.maxAttachmentBytes, 5 * 1024 * 1024);
      expect(QuotaPolicies.free.searchEnabled, isTrue);
      expect(QuotaPolicies.free.advancedFeatures, isFalse);
    });

    test('Full est illimité avec des fonctionnalités avancées', () {
      expect(QuotaPolicies.full.unlimited, isTrue);
      expect(QuotaPolicies.full.dailyRequests, isNull);
      expect(QuotaPolicies.full.maxAttachmentBytes, 25 * 1024 * 1024);
      expect(QuotaPolicies.full.advancedFeatures, isTrue);
    });

    test('forRole retourne la bonne politique', () {
      expect(QuotaPolicies.forRole(UserRole.free), QuotaPolicies.free);
      expect(QuotaPolicies.forRole(UserRole.full), QuotaPolicies.full);
    });

    test('la limite Full est plus permissive que la limite Free', () {
      expect(
        QuotaPolicies.full.maxAttachmentBytes,
        greaterThan(QuotaPolicies.free.maxAttachmentBytes),
      );
    });
  });
}
