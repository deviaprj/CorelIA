import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Constantes globales de l'application.
/// Les valeurs sensibles sont lues depuis .env a l'execution
/// (embarque dans l'APK) ou via --dart-define pour les builds CI.
abstract class AppConstants {
  // ── IA ──────────────────────────────────────────────────────────────────────
  static String get deepSeekApiKey => dotenv.get('DEEPSEEK_API_KEY', fallback: '');
  static String get openRouterApiKey => dotenv.get('OPENROUTER_API_KEY', fallback: '');
  static const deepSeekBaseUrl = 'https://api.deepseek.com/v1/chat/completions';
  static const openRouterBaseUrl = 'https://openrouter.ai/api/v1/chat/completions';

  static const deepSeekModel = 'deepseek-v4-flash';
  static const deepSeekVisionModel = 'deepseek-chat';
  static const mistralModel = 'mistralai/mistral-large-2407';
  static const groqModel = 'meta-llama/llama-3.3-70b-instruct';
  static const visionModel = 'openai/gpt-4o-mini';

  // ── Quotas ──────────────────────────────────────────────────────────────────
  static const freeRequestsPerDay = 20;
  static const maxContextMessages = 20;
  static const maxTokens = 4096;
  static const proMaxTokens = 8192;

  // ── AdMob ───────────────────────────────────────────────────────────────────
  static String get admobAppIdAndroid => dotenv.get('ADMOB_APP_ID_ANDROID',
      fallback: 'ca-app-pub-3940256099942544~3347511713');
  static String get admobAppIdIos => dotenv.get('ADMOB_APP_ID_IOS',
      fallback: 'ca-app-pub-3940256099942544~1458002511');

  // IDs bannière (test par défaut)
  static String get admobBannerId {
    if (kDebugMode) {
      return defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/6300978111'
          : 'ca-app-pub-3940256099942544/2934735716';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? dotenv.get('ADMOB_BANNER_ID_ANDROID', fallback: '')
        : dotenv.get('ADMOB_BANNER_ID_IOS', fallback: '');
  }

  // IDs interstitiel (test par défaut)
  static String get admobInterstitialId {
    if (kDebugMode) {
      return defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? dotenv.get('ADMOB_INTERSTITIAL_ID_ANDROID', fallback: '')
        : dotenv.get('ADMOB_INTERSTITIAL_ID_IOS', fallback: '');
  }

  // IDs rewarded (test par défaut)
  static String get admobRewardedId {
    if (kDebugMode) {
      return defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/5224354917'
          : 'ca-app-pub-3940256099942544/1712485313';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? dotenv.get('ADMOB_REWARDED_ID_ANDROID', fallback: '')
        : dotenv.get('ADMOB_REWARDED_ID_IOS', fallback: '');
  }

  // ── RevenueCat ──────────────────────────────────────────────────────────────
  static String get revenueCatApiKeyAndroid => dotenv.get('REVENUECAT_API_KEY_ANDROID', fallback: '');
  static String get revenueCatApiKeyIos => dotenv.get('REVENUECAT_API_KEY_IOS', fallback: '');

  static const entitlementPro = 'pro';
  static const offeringDefault = 'default';

  // ── Stripe ──────────────────────────────────────────────────────────────────
  static String get stripePublicKey => dotenv.get('STRIPE_PUBLIC_KEY', fallback: '');
  static const stripeCheckoutBaseUrl = 'https://aironbot.app/checkout';

  // ── App ─────────────────────────────────────────────────────────────────────
  static const appName = 'AironBot';
  static const appVersion = '1.1.0';
  static const appWebUrl = 'https://aironbot.app';
  static const shareTagline = '— Genere par AironBot\nhttps://aironbot.app';

  // ── Backend ─────────────────────────────────────────────────────────────────
  static String get backendBaseUrl => dotenv.get('BACKEND_URL', fallback: 'https://api.aironbot.app');

  // ── Firestore collections ───────────────────────────────────────────────────
  static const colUsers = 'users';
  static const colConversations = 'conversations';
  static const colMessages = 'messages';
  static const colProjects = 'projects';
  static const colReferrals = 'referrals';
}
