
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Niveau de consentement pour la collecte de donnees.
enum DataConsentLevel {
  none,      // Pas de consentement
  insights,  // Niveau 1 : donnees agrégées anonymisées uniquement
  full,      // Niveau 2 : personnalisation + insights (pseudonymisé)
}

/// Service de gestion du consentement RGPD pour la collecte de donnees.
///
/// Deux niveaux distincts du consentement AdMob :
/// - Niveau 1 (Insights) : +5 messages/jour
/// - Niveau 2 (Full) : +10 messages/jour + 20% reduction Pro
///
/// Le consentement est révocable à tout moment depuis les paramètres.
class ConsentDataService {
  static const String _prefsKeyLevel = 'data_consent_level';
  static const String _prefsKeyGivenAt = 'data_consent_given_at';
  static const String _prefsKeyVersion = 'data_consent_version';

  static const int _currentVersion = 1;

  /// Retourne le niveau de consentement actuel.
  Future<DataConsentLevel> getConsentLevel() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyLevel);
    if (raw == null) return DataConsentLevel.none;
    return DataConsentLevel.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => DataConsentLevel.none,
    );
  }

  /// Definit le niveau de consentement.
  Future<void> setConsentLevel(DataConsentLevel level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyLevel, level.name);
    await prefs.setString(_prefsKeyGivenAt, DateTime.now().toIso8601String());
    await prefs.setInt(_prefsKeyVersion, _currentVersion);
    debugPrint('[ConsentData] Level set to: $level');
  }

  /// Revoke complet du consentement (RGPD).
  Future<void> revoke() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyLevel);
    await prefs.remove(_prefsKeyGivenAt);
    await prefs.remove(_prefsKeyVersion);
    debugPrint('[ConsentData] Revoked');
  }

  /// True si l'utilisateur a consenti au moins au niveau 1.
  Future<bool> hasConsented() async {
    final level = await getConsentLevel();
    return level != DataConsentLevel.none;
  }

  /// True si l'utilisateur a consenti au niveau 2 (full).
  Future<bool> hasFullConsent() async {
    final level = await getConsentLevel();
    return level == DataConsentLevel.full;
  }

  /// Retourne la date de consentement (ou null).
  Future<DateTime?> getConsentDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyGivenAt);
    if (raw == null) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  /// Bonus messages/jour accordes selon le niveau.
  Future<int> getDailyMessageBonus() async {
    final level = await getConsentLevel();
    switch (level) {
      case DataConsentLevel.none:
        return 0;
      case DataConsentLevel.insights:
        return 5;
      case DataConsentLevel.full:
        return 10;
    }
  }

  /// Reduction Pro selon le niveau (0.0 - 1.0).
  Future<double> getProDiscount() async {
    final level = await getConsentLevel();
    switch (level) {
      case DataConsentLevel.none:
        return 0.0;
      case DataConsentLevel.insights:
        return 0.0;
      case DataConsentLevel.full:
        return 0.20; // 20% off
    }
  }

  /// Reset complet (debug).
  Future<void> reset() async {
    await revoke();
  }
}
