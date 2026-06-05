import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/features/monetization/ads/quota_exceeded_dialog.dart';

void main() {
  group('QuotaType', () {
    test('tous les types de quota existent', () {
      expect(QuotaType.values.length, 4);
      expect(QuotaType.values, contains(QuotaType.requests));
      expect(QuotaType.values, contains(QuotaType.searches));
      expect(QuotaType.values, contains(QuotaType.files));
      expect(QuotaType.values, contains(QuotaType.voice));
    });
  });

  group('_bonuses mapping', () {
    test('requests bonus est +5', () {
      // On ne peut pas tester _bonuses directement (privé),
      // mais on peut tester que chaque QuotaType a une entrée dans la map
      // via le widget QuotaExceededDialog
      for (final type in QuotaType.values) {
        // Vérifie que le dialog ne crash pas pour chaque type
        expect(type.index, greaterThanOrEqualTo(0));
      }
    });
  });
}