import 'package:corel_ia/core/models/app_user.dart';
import 'package:corel_ia/core/providers/firebase_providers.dart';
import 'package:corel_ia/features/auth/domain/auth_error_text.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUser', () {
    AppUser buildUser() => AppUser(
          uid: 'u1',
          email: 'marie.dupont@example.com',
          firstName: 'Marie',
          lastName: 'Dupont',
          birthDate: DateTime(1992, 3, 4),
          createdAt: DateTime(2026, 9, 20),
        );

    test('écrit le profil complet dans Firestore', () {
      final data = buildUser().toFirestore();

      expect(data['email'], 'marie.dupont@example.com');
      expect(data['firstName'], 'Marie');
      expect(data['lastName'], 'Dupont');
      expect(data['birthDate'], isNotNull);
      expect(data['plan'], isNotNull);
    });

    test('label privilégie « Prénom Nom »', () {
      expect(buildUser().label, 'Marie Dupont');
    });

    test('label retombe sur le pseudonyme puis l\'e-mail', () {
      final sansIdentite = AppUser(
        uid: 'u2',
        displayName: 'MarieD',
        createdAt: DateTime(2026, 9, 20),
      );
      expect(sansIdentite.label, 'MarieD');

      final sansNom = AppUser(
        uid: 'u3',
        email: 'marie.dupont@example.com',
        createdAt: DateTime(2026, 9, 20),
      );
      expect(sansNom.label, 'marie.dupont');

      final vide = AppUser(uid: 'u4', createdAt: DateTime(2026, 9, 20));
      expect(vide.label, 'Utilisateur');
    });

    test('copyWith conserve les champs non fournis', () {
      final updated = buildUser().copyWith(displayName: 'Marie D.');
      expect(updated.firstName, 'Marie');
      expect(updated.birthDate, DateTime(1992, 3, 4));
      expect(updated.displayName, 'Marie D.');
    });
  });

  group('AppUserLike — vérification de l\'adresse', () {
    test('un compte e-mail non confirmé doit être vérifié', () {
      const user = AppUserLike(
        uid: 'u1',
        email: 'marie@example.com',
        signedInWithPassword: true,
      );
      expect(user.needsEmailVerification, isTrue);
    });

    test('un compte Google (ou invité) n\'exige pas de confirmation', () {
      const user = AppUserLike(uid: 'u1', email: 'marie@example.com');
      expect(user.needsEmailVerification, isFalse);
    });

    test('un compte e-mail confirmé passe', () {
      const user = AppUserLike(
        uid: 'u1',
        email: 'marie@example.com',
        emailVerified: true,
        signedInWithPassword: true,
      );
      expect(user.needsEmailVerification, isFalse);
    });
  });

  group('authErrorMessage', () {
    test('traduit les codes Firebase connus', () {
      expect(
        authErrorMessage(
          FirebaseAuthException(code: 'wrong-password', message: 'nope'),
        ),
        'E-mail ou mot de passe incorrect.',
      );
      expect(
        authErrorMessage(
          FirebaseAuthException(code: 'email-already-in-use', message: 'nope'),
        ),
        contains('existe déjà'),
      );
      expect(
        authErrorMessage(
          FirebaseAuthException(code: 'network-request-failed', message: 'nope'),
        ),
        contains('Internet'),
      );
    });

    test('reste lisible pour un code inconnu', () {
      final message = authErrorMessage(
        FirebaseAuthException(code: 'code-inconnu', message: 'oops'),
      );
      expect(message, contains('code-inconnu'));
    });
  });
}
