import 'package:shared_preferences/shared_preferences.dart';

/// Timestamp de dernière édition locale des préférences synchronisées.
///
/// Utilisé par `PreferencesSyncService.mergeWithLocal` pour résoudre les
/// conflits multi-appareils en last-write-wins (LWW).
///
/// Ce fichier est volontairement un « leaf » (aucune dépendance Firebase ni
/// `main.dart`) afin d'éviter tout cycle d'import avec les Notifiers de
/// préférences (`app_providers.dart`, `settings_screen.dart`) qui doivent
/// appeler [markUpdated] à chaque édition locale.
class LocalPrefTimestamp {
  static const String key = 'prefs_local_updated_at';

  /// Horodate la dernière édition locale à maintenant.
  /// À appeler après chaque modification LOCALE d'une préférence synchronisée
  /// (systemPrompt / theme / ttsSpeed).
  static Future<void> markUpdated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, DateTime.now().toUtc().toIso8601String());
  }

  /// Lit le timestamp de dernière édition locale (null si jamais édité).
  static DateTime? read(SharedPreferences prefs) {
    final iso = prefs.getString(key);
    return iso == null ? null : DateTime.tryParse(iso);
  }

  /// Écrit un timestamp donné (après une fusion remportée par le remote, pour
  /// aligner le repère local et éviter de re-fusionner le même doc).
  static Future<void> write(SharedPreferences prefs, DateTime t) async {
    await prefs.setString(key, t.toUtc().toIso8601String());
  }
}