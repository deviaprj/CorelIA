import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Exception levee quand les credits gratuits sont epuises.
class CreditsExhaustedException implements Exception {
  final String message;
  const CreditsExhaustedException(this.message);
  @override
  String toString() => 'CreditsExhaustedException: $message';
}

/// Service de credits gratuits — compteur local (SharedPreferences).
/// Les credits sont reinitialises chaque jour (midnight) ou apres achat Pro.
class CreditService {
  static const int _dailyFreeCredits = 10;
  static const String _prefsKeyCredits = 'daily_credits';
  static const String _prefsKeyDate = 'credits_date';

  /// Nombre de credits restants (calcule a la volee).
  Future<int> getRemainingCredits() async {
    final prefs = await SharedPreferences.getInstance();
    final storedDate = prefs.getString(_prefsKeyDate);
    final today = _todayString();

    if (storedDate != today) {
      // Nouveau jour : reinitialiser
      await prefs.setInt(_prefsKeyCredits, _dailyFreeCredits);
      await prefs.setString(_prefsKeyDate, today);
      return _dailyFreeCredits;
    }

    return prefs.getInt(_prefsKeyCredits) ?? _dailyFreeCredits;
  }

  /// Verifie et decremente un credit. Lance [CreditsExhaustedException] si 0.
  Future<int> decrement() async {
    final remaining = await getRemainingCredits();
    if (remaining <= 0) {
      throw const CreditsExhaustedException(
        'Vos credits gratuits sont epuises. Passez en Pro pour illimite.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final updated = remaining - 1;
    await prefs.setInt(_prefsKeyCredits, updated);
    debugPrint('[CreditService] Credits restants : $updated');
    return updated;
  }

  /// Ajoute des crédits bonus (après avoir regardé une publicité récompensée).
  Future<int> addBonus({int amount = 5}) async {
    final prefs = await SharedPreferences.getInstance();
    final remaining = await getRemainingCredits();
    final updated = remaining + amount;
    await prefs.setInt(_prefsKeyCredits, updated);
    debugPrint('[CreditService] Bonus +$amount → credits restants : $updated');
    return updated;
  }

  /// Reinitialise les credits (apres achat Pro ou reset admin).
  Future<void> reset({int amount = _dailyFreeCredits}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyCredits, amount);
    await prefs.setString(_prefsKeyDate, _todayString());
  }

  static String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
