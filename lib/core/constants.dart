import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Lecture sécurisée d'une variable d'environnement.
/// 1. Priorité : --dart-define (compilé dans le binaire, fonctionne dans chrome-extension://)
/// 2. Fallback : dotenv (.env file, peut échouer dans chrome-extension://)
String? _env(String key) {
  // --dart-define a priorité (toujours disponible, même sans .env)
  final dartDefine = _dartDefineValue(key);
  if (dartDefine != null && dartDefine.isNotEmpty) return dartDefine;
  // Fallback dotenv
  if (!dotenv.isInitialized) return null;
  return dotenv.maybeGet(key);
}

/// Map des clés vers leurs valeurs --dart-define (const au compile time)
String? _dartDefineValue(String key) => switch (key) {
  'DEEPSEEK_API_KEY' => const String.fromEnvironment('DEEPSEEK_API_KEY', defaultValue: ''),
  'OPENROUTER_API_KEY' => const String.fromEnvironment('OPENROUTER_API_KEY', defaultValue: ''),
  'BACKEND_URL' => const String.fromEnvironment('BACKEND_URL', defaultValue: ''),
  'ADMOB_APP_ID_ANDROID' => const String.fromEnvironment('ADMOB_APP_ID_ANDROID', defaultValue: ''),
  'ADMOB_APP_ID_IOS' => const String.fromEnvironment('ADMOB_APP_ID_IOS', defaultValue: ''),
  'ADMOB_BANNER_ID_ANDROID' => const String.fromEnvironment('ADMOB_BANNER_ID_ANDROID', defaultValue: ''),
  'ADMOB_BANNER_ID_IOS' => const String.fromEnvironment('ADMOB_BANNER_ID_IOS', defaultValue: ''),
  'ADMOB_INTERSTITIAL_ID_ANDROID' => const String.fromEnvironment('ADMOB_INTERSTITIAL_ID_ANDROID', defaultValue: ''),
  'ADMOB_INTERSTITIAL_ID_IOS' => const String.fromEnvironment('ADMOB_INTERSTITIAL_ID_IOS', defaultValue: ''),
  'ADMOB_REWARDED_ID_ANDROID' => const String.fromEnvironment('ADMOB_REWARDED_ID_ANDROID', defaultValue: ''),
  'ADMOB_REWARDED_ID_IOS' => const String.fromEnvironment('ADMOB_REWARDED_ID_IOS', defaultValue: ''),
  'REVENUECAT_API_KEY_ANDROID' => const String.fromEnvironment('REVENUECAT_API_KEY_ANDROID', defaultValue: ''),
  'REVENUECAT_API_KEY_IOS' => const String.fromEnvironment('REVENUECAT_API_KEY_IOS', defaultValue: ''),
  'STRIPE_PUBLIC_KEY' => const String.fromEnvironment('STRIPE_PUBLIC_KEY', defaultValue: ''),
  'SERPAPI_API_KEY' => const String.fromEnvironment('SERPAPI_API_KEY', defaultValue: ''),
  'OPENWEATHERMAP_API_KEY' => const String.fromEnvironment('OPENWEATHERMAP_API_KEY', defaultValue: ''),
  _ => null,
};

/// Constantes globales de l'application.
/// Les valeurs sensibles sont lues depuis .env a l'execution
/// (embarque dans l'APK) ou via --dart-define pour les builds CI.
abstract class AppConstants {
  // ── IA ──────────────────────────────────────────────────────────────────────
  static String get deepSeekApiKey => _env('DEEPSEEK_API_KEY') ?? '';
  static String get openRouterApiKey => _env('OPENROUTER_API_KEY') ?? '';
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
  static String get admobAppIdAndroid => _env('ADMOB_APP_ID_ANDROID') ??
      (kDebugMode ? 'ca-app-pub-3940256099942544~3347511713' : '');
  static String get admobAppIdIos => _env('ADMOB_APP_ID_IOS') ??
      (kDebugMode ? 'ca-app-pub-3940256099942544~1458002511' : '');

  // IDs bannière (test par défaut)
  static String get admobBannerId {
    if (kDebugMode) {
      return defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/6300978111'
          : 'ca-app-pub-3940256099942544/2934735716';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? (_env('ADMOB_BANNER_ID_ANDROID') ?? '')
        : (_env('ADMOB_BANNER_ID_IOS') ?? '');
  }

  // IDs interstitiel (test par défaut)
  static String get admobInterstitialId {
    if (kDebugMode) {
      return defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? (_env('ADMOB_INTERSTITIAL_ID_ANDROID') ?? '')
        : (_env('ADMOB_INTERSTITIAL_ID_IOS') ?? '');
  }

  // IDs rewarded (test par défaut)
  static String get admobRewardedId {
    if (kDebugMode) {
      return defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/5224354917'
          : 'ca-app-pub-3940256099942544/1712485313';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? (_env('ADMOB_REWARDED_ID_ANDROID') ?? '')
        : (_env('ADMOB_REWARDED_ID_IOS') ?? '');
  }

  // ── RevenueCat ──────────────────────────────────────────────────────────────
  static String get revenueCatApiKeyAndroid => _env('REVENUECAT_API_KEY_ANDROID') ?? '';
  static String get revenueCatApiKeyIos => _env('REVENUECAT_API_KEY_IOS') ?? '';

  static const entitlementPro = 'pro';
  static const offeringDefault = 'default';

  // ── Stripe ──────────────────────────────────────────────────────────────────
  static String get stripePublicKey => _env('STRIPE_PUBLIC_KEY') ??
      (kDebugMode ? 'pk_test_fallback' : '');
  static const stripeCheckoutBaseUrl = 'https://aironbot.app/checkout';

  // ── Search APIs ───────────────────────────────────────────────────────────────
  static String? get serpApiKey => _env('SERPAPI_API_KEY');
  static String? get openWeatherApiKey => _env('OPENWEATHERMAP_API_KEY');

  // ── App ─────────────────────────────────────────────────────────────────────
  static const appName = 'Corely';
  static const appVersion = '1.1.0';
  static const appWebUrl = 'https://aironbot.app';
  static const shareTagline = '— Genere par Corely\nhttps://aironbot.app';

  // ── Backend ─────────────────────────────────────────────────────────────────
  static String get backendBaseUrl => _env('BACKEND_URL') ?? 'https://api.aironbot.app';

  // ── Firestore collections ───────────────────────────────────────────────────
  static const colUsers = 'users';
  static const colConversations = 'conversations';
  static const colMessages = 'messages';
  static const colProjects = 'projects';
  static const colReferrals = 'referrals';
}