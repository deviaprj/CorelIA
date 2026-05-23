import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gere la serie de jours consecutifs d'utilisation (streak).
///
/// Principe : l'utilisateur gagne un bonus de +2 messages apres 3 jours
/// consecutifs d'ouverture de l'application. La serie est reinitialisee
/// si l'application n'est pas ouverte pendant plus de 48h.
class StreakService {
  static const String _prefsKeyStreak = 'streak_days';
  static const String _prefsKeyLastOpen = 'streak_last_open';
  static const String _prefsKeyBonusGranted = 'streak_bonus_granted';
  static const int _streakThreshold = 3;
  static const int _bonusMessages = 2;
  static const int _resetHours = 48;

  /// Verifie et met a jour le streak lors de l'ouverture de l'app.
  /// Retourne true si un bonus de 2 messages doit etre accorde.
  Future<bool> checkAndUpdateStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final lastOpenStr = prefs.getString(_prefsKeyLastOpen);
    final now = DateTime.now();

    if (lastOpenStr == null) {
      // Premier lancement
      await _saveStreak(prefs, streak: 1, lastOpen: now, bonusGranted: false);
      return false;
    }

    final lastOpen = DateTime.parse(lastOpenStr);
    final diff = now.difference(lastOpen);

    if (diff.inHours > _resetHours) {
      // Streak rompu : plus de 48h sans ouverture
      await _saveStreak(prefs, streak: 1, lastOpen: now, bonusGranted: false);
      debugPrint('[StreakService] Streak rompu apres ${diff.inHours}h. Redemarrage a 1.');
      return false;
    }

    if (_isSameDay(lastOpen, now)) {
      // Deja ouvert aujourd'hui — pas de changement
      return false;
    }

    // Nouveau jour consecutif
    final currentStreak = (prefs.getInt(_prefsKeyStreak) ?? 0) + 1;
    final bonusAlreadyGranted = prefs.getBool(_prefsKeyBonusGranted) ?? false;

    // Verifier si le seuil de 3 jours est atteint et si le bonus n'a pas encore ete accorde pour cette serie
    final shouldGrantBonus = currentStreak >= _streakThreshold && !bonusAlreadyGranted;

    await _saveStreak(
      prefs,
      streak: currentStreak,
      lastOpen: now,
      bonusGranted: bonusAlreadyGranted || shouldGrantBonus,
    );

    debugPrint('[StreakService] Streak : $currentStreak jours. Bonus : $shouldGrantBonus');
    return shouldGrantBonus;
  }

  /// Retourne les donnees actuelles du streak.
  Future<StreakData> getStreakData() async {
    final prefs = await SharedPreferences.getInstance();
    final streak = prefs.getInt(_prefsKeyStreak) ?? 0;
    final bonusGranted = prefs.getBool(_prefsKeyBonusGranted) ?? false;
    return StreakData(streak: streak, bonusGranted: bonusGranted);
  }

  /// Texte d'encouragement pour l'UI.
  Future<String?> getStreakMessage() async {
    final data = await getStreakData();
    if (data.streak == 0) return null;
    if (data.streak < _streakThreshold) {
      final remaining = _streakThreshold - data.streak;
      return '$remaining jour${remaining > 1 ? 's' : ''} avant le bonus +$_bonusMessages messages !';
    }
    return 'Serie de $data.streak jours 🔥';
  }

  Future<void> _saveStreak(
    SharedPreferences prefs, {
    required int streak,
    required DateTime lastOpen,
    required bool bonusGranted,
  }) async {
    await prefs.setInt(_prefsKeyStreak, streak);
    await prefs.setString(_prefsKeyLastOpen, lastOpen.toIso8601String());
    await prefs.setBool(_prefsKeyBonusGranted, bonusGranted);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Reset manuel (debug ou achat Pro).
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyStreak);
    await prefs.remove(_prefsKeyLastOpen);
    await prefs.remove(_prefsKeyBonusGranted);
  }
}

class StreakData {
  final int streak;
  final bool bonusGranted;

  const StreakData({required this.streak, required this.bonusGranted});

  bool get isBonusEligible => streak >= StreakService._streakThreshold && !bonusGranted;
}
