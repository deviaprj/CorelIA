import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/data/file_quota_service.dart';

void main() {
  group('FileQuotaService', () {
    test('addBonus existe et est une méthode', () {
      final service = FileQuotaService();
      expect(service.addBonus, isA<Function>());
    });

    test('FileQuotaExceededException est bien formée', () {
      const e = FileQuotaExceededException();
      expect(e.toString(), contains('fichiers'));
    });

    test('freeUploadsPerDay est 10', () {
      expect(FileQuotaService.freeUploadsPerDay, 10);
    });
  });
}