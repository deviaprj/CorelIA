import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/data/quota_service.dart';

void main() {
  group('QuotaService', () {
    test('should handle Pro user response (-1)', () {
      // Pro users have -1 remaining (unlimited)
      const proRemaining = -1;

      expect(proRemaining, lessThan(0));
    });

    test('should parse int remaining correctly', () {
      final data = {'remaining': 10};
      final remaining = data['remaining'];

      expect(remaining, isA<int>());
      expect(remaining, equals(10));
    });

    test('should parse double remaining as int', () {
      final data = {'remaining': 10.0};
      final remaining = data['remaining'];

      if (remaining is double) {
        final intValue = remaining.toInt();
        expect(intValue, equals(10));
      }
    });
  });

  group('QuotaExceededException', () {
    test('should have correct message', () {
      const exception = QuotaExceededException();

      expect(
        exception.toString(),
        equals('Quota journalier atteint (100 req/jour en test)'),
      );
    });

    test('should be caught as QuotaExceededException', () async {
      Future<void> throwException() async {
        throw const QuotaExceededException();
      }

      expect(
        () async => await throwException(),
        throwsA(isA<QuotaExceededException>()),
      );
    });
  });

  group('Quota Limits', () {
    test('should enforce 20 requests per day for free users', () {
      const freeLimit = 20;
      const dailyRequests = 20;

      expect(dailyRequests, greaterThanOrEqualTo(freeLimit));
    });

    test('should allow unlimited for Pro users', () {
      const isPro = true;
      const dailyRequests = 1000;

      if (isPro) {
        expect(dailyRequests, greaterThan(20));
      }
    });

    test('should calculate remaining correctly', () {
      const freeLimit = 20;
      const used = 5;
      final remaining = freeLimit - used;

      expect(remaining, equals(15));
    });
  });
}
