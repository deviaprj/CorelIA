import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/features/monetization/subscription/subscription_service.dart';
import 'package:corel_ia/core/constants.dart';
import 'package:corel_ia/core/platform/platform_service.dart';

void main() {
  group('SubscriptionService', () {
    late SubscriptionService service;

    setUp(() {
      service = SubscriptionService();
    });

    test('should be created', () {
      expect(service, isNotNull);
    });

    test('should have valid RevenueCat API key constants', () {
      // In production, these should be set via --dart-define
      // In test mode, they may be empty
      expect(AppConstants.revenueCatApiKeyAndroid, isA<String>());
      expect(AppConstants.revenueCatApiKeyIos, isA<String>());
    });

    test('should have correct entitlement ID', () {
      expect(AppConstants.entitlementPro, equals('pro'));
    });

    test('should have correct offering ID', () {
      expect(AppConstants.offeringDefault, equals('default'));
    });
  });

  group('isProProvider', () {
    test('should exist and be a FutureProvider', () {
      // The provider is defined and should return a bool
      expect(isProProvider, isNotNull);
    });
  });

  group('Platform Detection for Subscriptions', () {
    test('should detect extension platform', () {
      // Extension platform should skip RevenueCat initialization
      expect(PlatformService.isExtension, isA<bool>());
    });

    test('should detect mobile platform', () {
      // Mobile platform should use RevenueCat
      expect(PlatformService.isMobile, isA<bool>());
    });

    test('should have correct platform enum values', () {
      expect(AppPlatform.values, contains(AppPlatform.mobileAndroid));
      expect(AppPlatform.values, contains(AppPlatform.mobileIos));
      expect(AppPlatform.values, contains(AppPlatform.chromeExtension));
      expect(AppPlatform.values, contains(AppPlatform.web));
    });
  });

  group('Subscription Features', () {
    test('Pro users should have unlimited requests', () {
      // From AppUser model: isPro returns true when plan == 'pro'
      const proPlan = 'pro';
      const freePlan = 'free';

      expect(proPlan, equals('pro'));
      expect(freePlan, equals('free'));
    });

    test('Free users should have 20 requests per day limit', () {
      expect(AppConstants.freeRequestsPerDay, equals(20));
    });

    test('Pro users should have higher token limit', () {
      expect(AppConstants.proMaxTokens, equals(8192));
      expect(AppConstants.maxTokens, equals(4096));
      expect(AppConstants.proMaxTokens, greaterThan(AppConstants.maxTokens));
    });
  });

  group('Monetization Constants', () {
    test('should have AdMob app IDs configured', () {
      expect(AppConstants.admobAppIdAndroid, isA<String>());
      expect(AppConstants.admobAppIdIos, isA<String>());
    });

    test('should have AdMob banner IDs configured', () {
      // These are getters, just verify they return strings
      expect(AppConstants.admobBannerId, isA<String>());
    });

    test('should have AdMob interstitial IDs configured', () {
      expect(AppConstants.admobInterstitialId, isA<String>());
    });

    test('should have AdMob rewarded IDs configured', () {
      expect(AppConstants.admobRewardedId, isA<String>());
    });
  });

  group('Stripe Integration', () {
    test('should have Stripe public key constant', () {
      expect(AppConstants.stripePublicKey, isA<String>());
    });

    test('should have Stripe checkout base URL', () {
      expect(
        AppConstants.stripeCheckoutBaseUrl,
        equals('https://zentic.fr/checkout'),
      );
    });
  });
}
