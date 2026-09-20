import 'package:corel_ia/shared/extensions/string_extensions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StringExt', () {
    test('capitalized met la première lettre en majuscule', () {
      expect('bonjour'.capitalized, 'Bonjour');
      expect(''.capitalized, '');
    });

    test('truncate coupe et ajoute une ellipsis', () {
      expect('abcdef'.truncate(3), 'abc…');
      expect('abc'.truncate(5), 'abc');
    });

    test('isValidEmail valide le format', () {
      expect('test@example.com'.isValidEmail, isTrue);
      expect('test@zentic.fr'.isValidEmail, isTrue);
      expect('invalide'.isValidEmail, isFalse);
      expect('a@b'.isValidEmail, isFalse);
    });

    test('isStrongPassword exige 8 caractères', () {
      expect('motdepasse'.isStrongPassword, isTrue);
      expect('court'.isStrongPassword, isFalse);
    });
  });
}
