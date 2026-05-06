import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/data/search_quota_service.dart';

void main() {
  group('SearchQuotaService', () {
    test('freeSearchesPerDay est 5', () {
      expect(SearchQuotaService.freeSearchesPerDay, 5);
    });

    test('SearchQuotaExceededException est bien formée', () {
      const exception = SearchQuotaExceededException();
      expect(exception.toString(), contains('recherches'));
    });
  });

  group('SearchQuotaExceededException', () {
    test('toString contient message quota', () {
      const e = SearchQuotaExceededException();
      expect(e.toString(), contains('Quota'));
    });
  });
}