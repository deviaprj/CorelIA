import 'package:corel_ia/core/models/user_role.dart';
import 'package:corel_ia/features/subscription/data/quota_service.dart';
import 'package:corel_ia/features/subscription/domain/quota_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('QuotaService', () {
    test('Free démarre avec la limite du jour', () async {
      final service = QuotaService();
      expect(
        await service.remaining(UserRole.free),
        QuotaPolicies.free.dailyRequests,
      );
    });

    test('Free décrémente à chaque requête', () async {
      final service = QuotaService();
      final first = await service.consume(UserRole.free);
      expect(first, QuotaPolicies.free.dailyRequests! - 1);
      final second = await service.consume(UserRole.free);
      expect(second, QuotaPolicies.free.dailyRequests! - 2);
    });

    test('Free bloque une fois le quota épuisé', () async {
      final service = QuotaService();
      for (var i = 0; i < QuotaPolicies.free.dailyRequests!; i++) {
        await service.consume(UserRole.free);
      }
      expect(await service.remaining(UserRole.free), 0);
      await expectLater(
        service.consume(UserRole.free),
        throwsA(isA<QuotaExceededException>()),
      );
    });

    test('l\'exception porte le rôle et la limite', () async {
      final service = QuotaService();
      await expectLater(
        () async {
          // Simule un compteur déjà à zéro.
          for (var i = 0; i <= QuotaPolicies.free.dailyRequests!; i++) {
            await service.consume(UserRole.free);
          }
        }(),
        throwsA(
          isA<QuotaExceededException>()
              .having((e) => e.role, 'role', UserRole.free)
              .having((e) => e.dailyLimit, 'dailyLimit',
                  QuotaPolicies.free.dailyRequests),
        ),
      );
    });

    test('Full est illimité', () async {
      final service = QuotaService();
      expect(await service.remaining(UserRole.full), isNull);
      for (var i = 0; i < 100; i++) {
        expect(await service.consume(UserRole.full), isNull);
      }
    });

    test('reset restaure le quota Free', () async {
      final service = QuotaService();
      await service.consume(UserRole.free);
      await service.reset();
      expect(
        await service.remaining(UserRole.free),
        QuotaPolicies.free.dailyRequests,
      );
    });
  });
}
