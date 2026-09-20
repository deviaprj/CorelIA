import 'package:corel_ia/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig', () {
    test('expose l\'identité de l\'application', () {
      expect(AppConfig.appName, 'CorelIA');
      expect(AppConfig.appVersion, isNotEmpty);
    });

    test('centralise les limites de contexte et de tokens', () {
      expect(AppConfig.maxContextMessages, 20);
      expect(AppConfig.maxTokens, 4096);
      expect(AppConfig.fullMaxTokens, greaterThanOrEqualTo(AppConfig.maxTokens));
    });

    test('déclare les collections Firestore', () {
      expect(AppConfig.colUsers, 'users');
      expect(AppConfig.colConversations, 'conversations');
      expect(AppConfig.colMessages, 'messages');
    });

    test('déclare l\'entitlement de l\'abonnement Full', () {
      expect(AppConfig.entitlementFull, isNotEmpty);
    });

    test('utilise des endpoints de recherche HTTPS', () {
      expect(AppConfig.duckDuckGoHtmlEndpoint, startsWith('https://'));
      expect(AppConfig.duckDuckGoLiteEndpoint, startsWith('https://'));
    });
  });
}
