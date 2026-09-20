import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Mode démo : aucune dépendance Firebase / RevenueCat.
/// Activé par `--dart-define=DEMO_MODE=true` (désactivé par défaut).
bool isDemoMode = const bool.fromEnvironment('DEMO_MODE', defaultValue: false);

/// Vrai quand Firebase n'a pas pu s'initialiser dans ce build.
///
/// L'appli reste utilisable en local, mais **aucun compte réel ni historique en
/// ligne** n'est disponible : l'interface doit le dire clairement plutôt que de
/// laisser croire à une inscription réussie.
bool firebaseUnavailable = false;

/// Lecture d'une clé : priorité au `--dart-define` (compilé dans le binaire),
/// puis au fichier `.env` (facultatif, jamais embarqué en release).
String? _env(String key) {
  final fromDefine = _dartDefineValue(key);
  if (fromDefine != null && fromDefine.isNotEmpty) return fromDefine;
  if (!dotenv.isInitialized) return null;
  return dotenv.maybeGet(key);
}

String? _dartDefineValue(String key) => switch (key) {
      'DEEPSEEK_API_KEY' =>
        const String.fromEnvironment('DEEPSEEK_API_KEY', defaultValue: ''),
      'CLOUDFLARE_WORKER_URL' =>
        const String.fromEnvironment('CLOUDFLARE_WORKER_URL', defaultValue: ''),
      'CLIENT_API_KEY' =>
        const String.fromEnvironment('CLIENT_API_KEY', defaultValue: ''),
      'REVENUECAT_API_KEY_ANDROID' =>
        const String.fromEnvironment('REVENUECAT_API_KEY_ANDROID', defaultValue: ''),
      'REVENUECAT_API_KEY_IOS' =>
        const String.fromEnvironment('REVENUECAT_API_KEY_IOS', defaultValue: ''),
      _ => null,
    };

/// Configuration centralisée de CorelIA.
///
/// Toutes les valeurs ajustables (modèles, limites, clés, collections) vivent
/// ici : un seul point de vérité pour l'application mobile.
abstract class AppConfig {
  // ── Identité ───────────────────────────────────────────────────────────────
  static const appName = 'CorelIA';
  static const appVersion = '2.0.0';
  static const shareTagline = '— Généré par CorelIA';

  // ── Cloudflare Worker (passerelle IA) ──────────────────────────────────────
  // URL de base du Worker, ex. `https://api.zentic.fr`.
  static String get workerBaseUrl => _env('CLOUDFLARE_WORKER_URL') ?? '';

  /// Clé publique (soft gate) envoyée dans `X-API-Key` au Worker.
  static String get clientApiKey => _env('CLIENT_API_KEY') ?? '';

  /// Endpoint de chat streaming du Worker.
  static String get workerChatUrl {
    final base = workerBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    return base.isEmpty ? '' : '$base/chat';
  }

  static bool get isWorkerConfigured => workerBaseUrl.isNotEmpty;

  static const workerAutoModel = 'auto';
  static const workerTimeout = Duration(seconds: 120);

  // ── Fallback IA direct (développement, hors Worker) ────────────────────────
  static String get deepSeekApiKey => _env('DEEPSEEK_API_KEY') ?? '';

  static const deepSeekBaseUrl = 'https://api.deepseek.com/v1/chat/completions';

  static const deepSeekModel = 'deepseek-v4-flash';
  static const deepSeekProModel = 'deepseek-v4-pro';
  static const deepSeekReasonerModel = 'deepseek-reasoner';
  static const deepSeekVisionModel = 'deepseek-chat';

  /// Nombre de messages d'historique envoyés au modèle.
  static const maxContextMessages = 20;
  static const maxTokens = 4096;
  static const fullMaxTokens = 8192;

  // ── Pièces jointes ─────────────────────────────────────────────────────────
  /// Taille totale maximale par message (octets).
  static const maxAttachmentBytes = 5 * 1024 * 1024; // Free : 5 Mo
  static const fullMaxAttachmentBytes = 25 * 1024 * 1024; // Full : 25 Mo

  // ── Recherche web ──────────────────────────────────────────────────────────
  static const searchCacheTtlMinutes = 15;
  static const searchCacheMaxEntries = 100;
  static const searchResultsLimit = 5;
  static const searchRequestTimeout = Duration(seconds: 8);

  static const duckDuckGoHtmlEndpoint = 'https://html.duckduckgo.com/html/';
  static const duckDuckGoLiteEndpoint = 'https://lite.duckduckgo.com/lite/';
  static const duckDuckGoInstantAnswerEndpoint = 'https://api.duckduckgo.com/';

  // ── Abonnement (RevenueCat) ────────────────────────────────────────────────
  static String get revenueCatApiKeyAndroid =>
      _env('REVENUECAT_API_KEY_ANDROID') ?? '';
  static String get revenueCatApiKeyIos => _env('REVENUECAT_API_KEY_IOS') ?? '';

  /// Identifiant de l'entitlement qui déverrouille l'Agent IA Full.
  /// Doit correspondre à celui configuré dans le tableau de bord RevenueCat.
  static const entitlementFull = 'full';

  // ── Firestore ──────────────────────────────────────────────────────────────
  static const colUsers = 'users';
  static const colConversations = 'conversations';
  static const colMessages = 'messages';
}
