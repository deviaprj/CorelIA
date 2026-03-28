import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/core/platform/platform_service.dart';

void main() {
  group('PlatformService', () {
    test('isMobile returns bool', () {
      expect(PlatformService.isMobile, isA<bool>());
    });

    test('isExtension returns bool', () {
      expect(PlatformService.isExtension, isA<bool>());
    });

    test('current returns an AppPlatform', () {
      expect(PlatformService.current, isA<AppPlatform>());
    });

    test('current returns a valid platform', () {
      final platform = PlatformService.current;
      expect(
        AppPlatform.values.contains(platform),
        isTrue,
      );
    });
  });
}
