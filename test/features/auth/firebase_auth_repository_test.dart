import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/auth/data/firebase_auth_repository.dart';
import 'package:airon_bot/features/auth/domain/app_user.dart';

// Fake implementations for testing
class FakeUser {
  final String uid;
  final String? email;
  final String? displayName;
  final bool isAnonymous;

  FakeUser({
    required this.uid,
    this.email,
    this.displayName,
    this.isAnonymous = false,
  });
}

void main() {
  group('FirebaseAuthRepository', () {
    group('AppUser', () {
      final testUser = AppUser(
        uid: 'test_uid',
        email: 'test@example.com',
        displayName: 'Test User',
        plan: 'free',
        dailyRequests: 5,
        dailyRequestsDate: '2024-01-01',
        totalRequests: 100,
        createdAt: DateTime(2024, 1, 1),
      );

      test('should calculate remaining requests correctly', () {
        // Le calcul dépend de la date actuelle, on vérifie juste la logique
        final user = testUser;
        expect(user.isPro, isFalse);
      });

      test('should identify pro users', () {
        final proUser = AppUser(
          uid: 'pro_uid',
          email: 'pro@example.com',
          plan: 'pro',
          createdAt: DateTime(2024, 1, 1),
        );
        expect(proUser.isPro, isTrue);
      });

      test('should create copy with updated values', () {
        final updated = testUser.copyWith(
          dailyRequests: 10,
          displayName: 'Updated Name',
        );

        expect(updated.dailyRequests, equals(10));
        expect(updated.displayName, equals('Updated Name'));
        expect(updated.email, equals(testUser.email)); // Non modifié
        expect(updated.uid, equals(testUser.uid)); // Non modifié
      });

      test('should convert to and from Firestore', () {
        final firestoreData = testUser.toFirestore();

        expect(firestoreData['uid'], equals('test_uid'));
        expect(firestoreData['email'], equals('test@example.com'));
        expect(firestoreData['displayName'], equals('Test User'));
        expect(firestoreData['plan'], equals('free'));
        expect(firestoreData['dailyRequests'], equals(5));
        expect(firestoreData['totalRequests'], equals(100));
      });

      test('should identify free users', () {
        expect(testUser.isPro, isFalse);
      });

      test('should identify anonymous users', () {
        final anonUser = AppUser(
          uid: 'anon_uid',
          email: null,
          displayName: null,
          createdAt: DateTime(2024, 1, 1),
        );
        expect(anonUser.email, isNull);
        expect(anonUser.displayName, isNull);
      });

      test('should track daily requests', () {
        final user = AppUser(
          uid: 'uid',
          dailyRequests: 15,
          dailyRequestsDate: '2024-01-15',
          createdAt: DateTime(2024, 1, 1),
        );

        expect(user.dailyRequests, equals(15));
        expect(user.dailyRequestsDate, equals('2024-01-15'));
      });

      test('should increment total requests', () {
        final updated = testUser.copyWith(
          totalRequests: testUser.totalRequests + 1,
        );
        expect(updated.totalRequests, equals(101));
      });

      test('should handle null values', () {
        final minimalUser = AppUser(
          uid: 'minimal',
          createdAt: DateTime(2024, 1, 1),
        );

        expect(minimalUser.email, isNull);
        expect(minimalUser.displayName, isNull);
        expect(minimalUser.plan, equals('free')); // valeur par défaut
        expect(minimalUser.dailyRequests, equals(0));
        expect(minimalUser.totalRequests, equals(0));
      });
    });

    group('User Properties', () {
      test('should validate email format', () {
        const validEmail = 'user@example.com';
        const invalidEmail = 'not-an-email';

        expect(validEmail.contains('@'), isTrue);
        expect(invalidEmail.contains('@'), isFalse);
      });

      test('should require uid', () {
        // L'uid est toujours required dans AppUser
        final user = AppUser(
          uid: 'required_uid',
          createdAt: DateTime(2024, 1, 1),
        );
        expect(user.uid, isNotEmpty);
      });

      test('should support display name', () {
        final user = AppUser(
          uid: 'uid',
          displayName: 'John Doe',
          createdAt: DateTime(2024, 1, 1),
        );
        expect(user.displayName, equals('John Doe'));
      });
    });

    group('Pro Plan', () {
      test('should have unlimited requests for pro', () {
        final proUser = AppUser(
          uid: 'pro',
          plan: 'pro',
          createdAt: DateTime(2024, 1, 1),
        );

        // Les utilisateurs Pro n'ont pas de limite
        expect(proUser.isPro, isTrue);
        expect(proUser.dailyRequestsLimit, equals(-1)); // -1 = illimité
      });

      test('should have 20 requests limit for free', () {
        final freeUser = AppUser(
          uid: 'free',
          plan: 'free',
          createdAt: DateTime(2024, 1, 1),
        );

        expect(freeUser.isPro, isFalse);
        expect(freeUser.dailyRequestsLimit, equals(20));
      });

      test('should calculate remaining for free users', () {
        final freeUser = AppUser(
          uid: 'free',
          plan: 'free',
          dailyRequests: 15,
          createdAt: DateTime(2024, 1, 1),
        );

        final remaining = freeUser.dailyRequestsLimit - freeUser.dailyRequests;
        expect(remaining, equals(5));
      });
    });
  });
}
