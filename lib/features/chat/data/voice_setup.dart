import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// État de la voix du téléphone pour une langue donnée.
enum TtsReadiness {
  /// Moteur installé et voix disponible : rien à faire.
  ready,

  /// Aucun moteur de synthèse vocale sur l'appareil.
  noEngine,

  /// Le moteur est présent mais les données vocales de la langue manquent.
  missingLanguage,
}

/// Paquet Android de « Speech Services by Google ».
const googleTtsPackage = 'com.google.android.tts';

/// Page d'installation (Play Store, avec repli navigateur).
const googleTtsInstallUrls = [
  'market://details?id=$googleTtsPackage',
  'https://play.google.com/store/apps/details?id=$googleTtsPackage',
];

/// Canal natif vers `MainActivity` (ouverture des réglages vocaux).
const systemChannel = MethodChannel('com.corelia.corely/system');

/// Clé du drapeau « l'aide vocale a déjà été proposée ».
const voiceHintDismissedKey = 'voice_setup_hint_dismissed';

/// Interprète la réponse de `isLanguageAvailable`.
///
/// Selon le moteur : `bool`, `int` (1/0) ou chaîne. `null` = indéterminé.
bool? voiceAvailabilityFrom(dynamic result) {
  if (result is bool) return result;
  if (result is int) return result == 1;
  if (result is String) {
    final value = result.toLowerCase();
    if (value == 'true') return true;
    if (value == 'false') return false;
  }
  return null;
}

/// Texte d'aide présenté à l'utilisateur.
String voiceSetupMessage(TtsReadiness readiness) => switch (readiness) {
      TtsReadiness.ready =>
        'La voix est prête : aucune action nécessaire.',
      TtsReadiness.noEngine =>
        "Aucun moteur de synthèse vocale n'est installé sur cet appareil.",
      TtsReadiness.missingLanguage =>
        "Les données de la voix française ne sont pas encore téléchargées.",
    };

/// Vérifie la disponibilité d'une voix pour [language] (ex. `fr-FR`).
///
/// Ne bloque jamais la lecture : en cas de doute on considère la voix prête.
Future<TtsReadiness> checkTtsReadiness(
  String language, {
  FlutterTts? engine,
}) async {
  final tts = engine ?? FlutterTts();
  try {
    final engines = await tts.getEngines;
    if (engines is List && engines.isEmpty) return TtsReadiness.noEngine;

    final available = voiceAvailabilityFrom(
      await tts.isLanguageAvailable(language),
    );
    if (available == null || available) return TtsReadiness.ready;
    return TtsReadiness.missingLanguage;
  } catch (_) {
    return TtsReadiness.ready;
  }
}

/// Ouvre les réglages « Synthèse vocale » d'Android.
Future<bool> openSystemTtsSettings() async {
  try {
    return await systemChannel.invokeMethod<bool>('openTtsSettings') ?? false;
  } catch (_) {
    return false;
  }
}

/// Ouvre la fiche Play Store de « Speech Services by Google ».
Future<bool> openGoogleTtsInstallPage() async {
  for (final raw in googleTtsInstallUrls) {
    try {
      if (await launchUrl(Uri.parse(raw), mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {
      // Repli sur l'URL suivante.
    }
  }
  return false;
}

/// Vrai si l'aide à l'installation a déjà été proposée.
Future<bool> isVoiceHintDismissed() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(voiceHintDismissedKey) ?? false;
}

/// Mémorise que l'aide ne doit plus être proposée automatiquement.
Future<void> dismissVoiceHint() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(voiceHintDismissedKey, true);
}

/// Réautorise l'aide (depuis le menu « Améliorer la voix »).
Future<void> resetVoiceHint() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(voiceHintDismissedKey);
}
