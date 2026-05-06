import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchQuotaExceededException implements Exception {
  const SearchQuotaExceededException();
  @override
  String toString() =>
      'Quota recherches web journalier atteint. Passez en Pro !';
}

/// Service de quota local pour les recherches web.
/// 100% autonome — ne depend pas du backend.
class SearchQuotaService {
  static const int freeSearchesPerDay = 5;
  static const String _prefsKey = 'search_count';
  static const String _prefsDateKey = 'search_date';

  Future<void> checkAndDecrement() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    final storedDate = prefs.getString(_prefsDateKey);

    int count;
    if (storedDate != today) {
      count = freeSearchesPerDay - 1;
      await prefs.setString(_prefsDateKey, today);
      await prefs.setInt(_prefsKey, count);
    } else {
      count = prefs.getInt(_prefsKey) ?? freeSearchesPerDay;
      if (count <= 0) {
        throw const SearchQuotaExceededException();
      }
      await prefs.setInt(_prefsKey, count - 1);
    }

    debugPrint('[SearchQuota] Restants: ${count - 1}');
  }

  /// Ajoute des recherches bonus (après publicité récompensée).
  Future<int> addBonus({int amount = 2}) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    final storedDate = prefs.getString(_prefsDateKey);
    int current;
    if (storedDate != today) {
      current = freeSearchesPerDay;
      await prefs.setString(_prefsDateKey, today);
      await prefs.setInt(_prefsKey, current);
    } else {
      current = prefs.getInt(_prefsKey) ?? freeSearchesPerDay;
    }
    final updated = current + amount;
    await prefs.setInt(_prefsKey, updated);
    debugPrint('[SearchQuota] Bonus +$amount → recherches restantes : $updated');
    return updated;
  }

  Future<int> getRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    final storedDate = prefs.getString(_prefsDateKey);
    if (storedDate != today) return freeSearchesPerDay;
    return prefs.getInt(_prefsKey) ?? freeSearchesPerDay;
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

final searchQuotaServiceProvider =
    Provider<SearchQuotaService>((ref) => SearchQuotaService());