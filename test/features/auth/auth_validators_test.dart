import 'package:corel_ia/features/auth/domain/auth_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthValidators.email', () {
    test('accepte une adresse correcte', () {
      expect(AuthValidators.email('prenom.nom+tag@example.co.uk'), isNull);
    });

    test('refuse une adresse vide ou mal formée', () {
      expect(AuthValidators.email(''), isNotNull);
      expect(AuthValidators.email(null), isNotNull);
      expect(AuthValidators.email('pasunemail'), isNotNull);
      expect(AuthValidators.email('a@b'), isNotNull);
    });
  });

  group('AuthValidators.password', () {
    test('exige longueur, lettre et chiffre', () {
      expect(AuthValidators.password('court1'), isNotNull);
      expect(AuthValidators.password('sanschiffre'), isNotNull);
      expect(AuthValidators.password('12345678'), isNotNull);
      expect(AuthValidators.password('motdepasse1'), isNull);
    });
  });

  group('AuthValidators.passwordConfirmation', () {
    test('détecte une confirmation différente', () {
      expect(AuthValidators.passwordConfirmation('abc12345', 'abc12345'), isNull);
      expect(AuthValidators.passwordConfirmation('abc12345', 'autre123'), isNotNull);
      expect(AuthValidators.passwordConfirmation('', 'abc12345'), isNotNull);
    });
  });

  group('AuthValidators.birthDate', () {
    final now = DateTime(2026, 9, 20);

    test('refuse une date absente ou future', () {
      expect(AuthValidators.birthDate(null, now: now), isNotNull);
      expect(
        AuthValidators.birthDate(DateTime(2027, 1, 1), now: now),
        isNotNull,
      );
    });

    test('refuse un âge inférieur au minimum', () {
      // 12 ans révolus : juste sous la limite.
      expect(
        AuthValidators.birthDate(DateTime(2014, 9, 19), now: now),
        isNotNull,
      );
    });

    test('accepte un âge raisonnable', () {
      expect(
        AuthValidators.birthDate(DateTime(1990, 5, 12), now: now),
        isNull,
      );
      // Le jour même de l'anniversaire des 13 ans passe.
      expect(
        AuthValidators.birthDate(DateTime(2013, 9, 20), now: now),
        isNull,
      );
    });

    test('refuse une date invraisemblable', () {
      expect(
        AuthValidators.birthDate(DateTime(1850, 1, 1), now: now),
        isNotNull,
      );
    });
  });

  group('AuthValidators.age', () {
    test('gère l\'anniversaire non encore passé', () {
      final now = DateTime(2026, 9, 20);
      expect(AuthValidators.age(DateTime(2000, 9, 21), now: now), 25);
      expect(AuthValidators.age(DateTime(2000, 9, 20), now: now), 26);
      expect(AuthValidators.age(DateTime(2000, 1, 1), now: now), 26);
    });
  });

  group('AuthValidators.isRegistrationValid', () {
    final now = DateTime(2026, 9, 20);

    test('vrai seulement quand tout est correct', () {
      expect(
        AuthValidators.isRegistrationValid(
          firstName: 'Marie',
          lastName: 'Dupont',
          birthDate: DateTime(1992, 3, 4),
          email: 'marie@example.com',
          password: 'motdepasse1',
          confirmation: 'motdepasse1',
          now: now,
        ),
        isTrue,
      );

      expect(
        AuthValidators.isRegistrationValid(
          firstName: 'M',
          lastName: 'Dupont',
          birthDate: DateTime(1992, 3, 4),
          email: 'marie@example.com',
          password: 'motdepasse1',
          confirmation: 'motdepasse1',
          now: now,
        ),
        isFalse,
      );
    });
  });
}
