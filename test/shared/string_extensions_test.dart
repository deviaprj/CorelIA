import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/shared/extensions/string_extensions.dart';

void main() {
  group('StringExt', () {
    group('capitalized', () {
      test('capitalizes first letter', () {
        expect('hello'.capitalized, equals('Hello'));
      });

      test('returns empty string unchanged', () {
        expect(''.capitalized, equals(''));
      });

      test('handles single character', () {
        expect('a'.capitalized, equals('A'));
      });

      test('handles already capitalized', () {
        expect('Hello'.capitalized, equals('Hello'));
      });
    });

    group('truncate', () {
      test('truncates long string with ellipsis', () {
        expect('Hello World'.truncate(5), equals('Hello…'));
      });

      test('returns short string unchanged', () {
        expect('Hi'.truncate(10), equals('Hi'));
      });

      test('handles exact length', () {
        expect('Hello'.truncate(5), equals('Hello'));
      });
    });

    group('isValidEmail', () {
      test('accepts valid email', () {
        expect('user@example.com'.isValidEmail, isTrue);
      });

      test('accepts email with dash in domain', () {
        expect('user@my-domain.com'.isValidEmail, isTrue);
      });

      test('accepts email with plus', () {
        expect('user+tag@example.com'.isValidEmail, isTrue);
      });

      test('rejects email without @', () {
        expect('userexample.com'.isValidEmail, isFalse);
      });

      test('rejects email without domain', () {
        expect('user@'.isValidEmail, isFalse);
      });

      test('rejects empty string', () {
        expect(''.isValidEmail, isFalse);
      });
    });

    group('isStrongPassword', () {
      test('accepts 8+ character password', () {
        expect('12345678'.isStrongPassword, isTrue);
      });

      test('rejects short password', () {
        expect('1234567'.isStrongPassword, isFalse);
      });

      test('rejects empty password', () {
        expect(''.isStrongPassword, isFalse);
      });
    });
  });
}
