import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/core/constants.dart';

void main() {
  group('AppConstants', () {
    test('should have correct free requests per day', () {
      expect(AppConstants.freeRequestsPerDay, equals(20));
    });

    test('should have correct max context messages', () {
      expect(AppConstants.maxContextMessages, equals(20));
    });

    test('should have correct max tokens', () {
      expect(AppConstants.maxTokens, equals(4096));
    });

    test('should have correct pro max tokens', () {
      expect(AppConstants.proMaxTokens, equals(8192));
    });

    test('should have correct collection names', () {
      expect(AppConstants.colUsers, equals('users'));
      expect(AppConstants.colConversations, equals('conversations'));
      expect(AppConstants.colMessages, equals('messages'));
      expect(AppConstants.colProjects, equals('projects'));
      expect(AppConstants.colReferrals, equals('referrals'));
    });

    test('should have correct model names', () {
      expect(AppConstants.deepSeekModel, equals('deepseek-v4-flash'));
      expect(AppConstants.mistralModel, equals('mistralai/mistral-large-2407'));
      expect(AppConstants.deepseekR1Free, equals('deepseek/deepseek-r1:free'));
    });

    test('should have correct API URLs', () {
      expect(
        AppConstants.deepSeekBaseUrl,
        equals('https://api.deepseek.com/v1/chat/completions'),
      );
      expect(
        AppConstants.openRouterBaseUrl,
        equals('https://openrouter.ai/api/v1/chat/completions'),
      );
    });

    test('should have correct share tagline', () {
      expect(
        AppConstants.shareTagline,
        contains('Genere par Corely'),
      );
    });

    test('should have correct entitlement and offering names', () {
      expect(AppConstants.entitlementPro, equals('pro'));
      expect(AppConstants.offeringDefault, equals('default'));
    });
  });

  group('AdMob IDs (Debug Mode)', () {
    test('should return test banner ID in debug mode', () {
      if (kDebugMode) {
        final bannerId = AppConstants.admobBannerId;
        expect(bannerId, startsWith('ca-app-pub-3940256099942544'));
      }
    });

    test('should return test interstitial ID in debug mode', () {
      if (kDebugMode) {
        final id = AppConstants.admobInterstitialId;
        expect(id, startsWith('ca-app-pub-3940256099942544'));
      }
    });

    test('should return test rewarded ID in debug mode', () {
      if (kDebugMode) {
        final id = AppConstants.admobRewardedId;
        expect(id, startsWith('ca-app-pub-3940256099942544'));
      }
    });
  });
}
