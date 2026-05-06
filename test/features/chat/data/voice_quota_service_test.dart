import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/data/voice_quota_service.dart';

void main() {
  group('VoiceQuotaService', () {
    test('freeVoicePerDay est 10', () {
      expect(VoiceQuotaService.freeVoicePerDay, 10);
    });

    test('VoiceQuotaExceededException est bien formée', () {
      const exception = VoiceQuotaExceededException();
      expect(exception.toString(), contains('vocal'));
    });
  });

  group('VoiceQuotaExceededException', () {
    test('toString contient message quota', () {
      const e = VoiceQuotaExceededException();
      expect(e.toString(), contains('Quota'));
    });
  });
}