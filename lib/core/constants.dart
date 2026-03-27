import 'package:flutter/foundation.dart';

/// Constantes globales de l'application.
/// Les valeurs sensibles sont injectées via --dart-define-from-file=.env
abstract class AppConstants {
  // ── IA ──────────────────────────────────────────────────────────────────────
  static const deepSeekApiKey = String.fromEnvironment('DEEPSEEK_API_KEY');
  static const openRouterApiKey = String.fromEnvironment('OPENROUTER_API_KEY');
  static const ollamaApiKey = String.fromEnvironment('OLLAMA_API_KEY', defaultValue: '');

  static const deepSeekBaseUrl = 'https://api.deepseek.com/v1/chat/completions';
  static const openRouterBaseUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const ollamaBaseUrl = 'https://ollama.com';

  static const deepSeekModel = 'deepseek-chat';
  static const mistralModel = 'mistralai/mistral-large-2407';
  static const groqModel = 'meta-llama/llama-3.3-70b-instruct';
  static const ollamaModel = 'kimi-k2.5:cloud';

  // ── Quotas ──────────────────────────────────────────────────────────────────
  static const freeRequestsPerDay = 20;
  static const maxContextMessages = 20;
  static const maxTokens = 4096;
  static const proMaxTokens = 8192;

  // ── AdMob ───────────────────────────────────────────────────────────────────
  static const admobAppIdAndroid = String.fromEnvironment('ADMOB_APP_ID_ANDROID',
      defaultValue: 'ca-app-pub-3940256099942544~3347511713');
  static const admobAppIdIos = String.fromEnvironment('ADMOB_APP_ID_IOS',
      defaultValue: 'ca-app-pub-3940256099942544~1458002511');

  // IDs bannière (test par défaut)
  static String get admobBannerId {
    if (kDebugMode) {
      return defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/6300978111'
          : 'ca-app-pub-3940256099942544/2934735716';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? const String.fromEnvironment('ADMOB_BANNER_ID_ANDROID')
        : const String.fromEnvironment('ADMOB_BANNER_ID_IOS');
  }

  // IDs interstitiel (test par défaut)
  static String get admobInterstitialId {
    if (kDebugMode) {
      return defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? const String.fromEnvironment('ADMOB_INTERSTITIAL_ID_ANDROID')
        : const String.fromEnvironment('ADMOB_INTERSTITIAL_ID_IOS');
  }

  // IDs rewarded (test par défaut)
  static String get admobRewardedId {
    if (kDebugMode) {
      return defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/5224354917'
          : 'ca-app-pub-3940256099942544/1712485313';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? const String.fromEnvironment('ADMOB_REWARDED_ID_ANDROID')
        : const String.fromEnvironment('ADMOB_REWARDED_ID_IOS');
  }

  // ── RevenueCat ──────────────────────────────────────────────────────────────
  static const revenueCatApiKeyAndroid = String.fromEnvironment('REVENUECAT_API_KEY_ANDROID');
  static const revenueCatApiKeyIos = String.fromEnvironment('REVENUECAT_API_KEY_IOS');

  static const entitlementPro = 'pro';
  static const offeringDefault = 'default';

  // ── Stripe ──────────────────────────────────────────────────────────────────
  static const stripePublicKey = String.fromEnvironment('STRIPE_PUBLIC_KEY');
  static const stripeCheckoutBaseUrl = 'https://aironbot.app/checkout';

  // ── App ─────────────────────────────────────────────────────────────────────
  static const appName = 'AironBot';
  static const appWebUrl = 'https://aironbot.app';
  static const shareTagline = '— Généré par AironBot\nhttps://aironbot.app';

  // ── Firestore collections ───────────────────────────────────────────────────
  static const colUsers = 'users';
  static const colConversations = 'conversations';
  static const colMessages = 'messages';
  static const colProjects = 'projects';
  static const colReferrals = 'referrals';
}
