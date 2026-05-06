import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/monetization/credits/credit_service.dart';

void main() {
  group('CreditService', () {
    test('addBonus existe et est une méthode', () {
      final service = CreditService();
      expect(service.addBonus, isA<Function>());
    });

    test('CreditsExhaustedException message est correct', () {
      const e = CreditsExhaustedException('Test message');
      expect(e.message, 'Test message');
      expect(e.toString(), contains('Test message'));
    });
  });
}