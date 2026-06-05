import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VoiceQuotaExceededException implements Exception {
  const VoiceQuotaExceededException();
  @override
  String toString() =>
      'Quota vocal journalier atteint. Passez en Pro !';
}

/// Service de quota local pour les interactions vocales.
/// 100% autonome — ne depend pas du backend.
class VoiceQuotaService {
  static const int freeVoicePerDay = 10;
  static const String _prefsKey = 'voice_count';
  static const String _prefsDateKey = 'voice_date';

  Future<void> checkAndDecrement() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    final storedDate = prefs.getString(_prefsDateKey);

    int count;
    if (storedDate != today) {
      count = freeVoicePerDay - 1;
      await prefs.setString(_prefsDateKey, today);
      await prefs.setInt(_prefsKey, count);
    } else {
      count = prefs.getInt(_prefsKey) ?? freeVoicePerDay;
      if (count <= 0) {
        throw const VoiceQuotaExceededException();
      }
      await prefs.setInt(_prefsKey, count - 1);
    }

    debugPrint('[VoiceQuota] Restants: ${count - 1}');
  }

  /// Ajoute des interactions vocales bonus (après publicité récompensée).
  Future<int> addBonus({int amount = 5}) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    final storedDate = prefs.getString(_prefsDateKey);
    int current;
    if (storedDate != today) {
      current = freeVoicePerDay;
      await prefs.setString(_prefsDateKey, today);
      await prefs.setInt(_prefsKey, current);
    } else {
      current = prefs.getInt(_prefsKey) ?? freeVoicePerDay;
    }
    final updated = current + amount;
    await prefs.setInt(_prefsKey, updated);
    debugPrint('[VoiceQuota] Bonus +$amount → voix restantes : $updated');
    return updated;
  }

  Future<int> getRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    final storedDate = prefs.getString(_prefsDateKey);
    if (storedDate != today) return freeVoicePerDay;
    return prefs.getInt(_prefsKey) ?? freeVoicePerDay;
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

final voiceQuotaServiceProvider =
    Provider<VoiceQuotaService>((ref) => VoiceQuotaService());