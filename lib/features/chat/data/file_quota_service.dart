import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FileQuotaExceededException implements Exception {
  const FileQuotaExceededException();
  @override
  String toString() => 'Quota fichiers journalier atteint (2/jour). Passez en Pro !';
}

/// Service de quota local pour les uploads de fichiers.
/// 100% autonome — ne depend pas du backend.
class FileQuotaService {
  static const int freeUploadsPerDay = 2;
  static const String _prefsKey = 'file_upload_count';
  static const String _prefsDateKey = 'file_upload_date';

  Future<void> checkAndDecrement() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    final storedDate = prefs.getString(_prefsDateKey);

    int count;
    if (storedDate != today) {
      count = freeUploadsPerDay - 1;
      await prefs.setString(_prefsDateKey, today);
      await prefs.setInt(_prefsKey, count);
    } else {
      count = prefs.getInt(_prefsKey) ?? freeUploadsPerDay;
      if (count <= 0) {
        throw const FileQuotaExceededException();
      }
      await prefs.setInt(_prefsKey, count - 1);
    }

    debugPrint('[FileQuota] Restants: ${count - 1}');
  }

  Future<int> getRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    final storedDate = prefs.getString(_prefsDateKey);
    if (storedDate != today) return freeUploadsPerDay;
    return prefs.getInt(_prefsKey) ?? freeUploadsPerDay;
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

final fileQuotaServiceProvider = Provider<FileQuotaService>((ref) => FileQuotaService());
