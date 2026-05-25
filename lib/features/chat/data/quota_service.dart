import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../main.dart' show isDemoMode;

class QuotaExceededException implements Exception {
  const QuotaExceededException();
  @override
  String toString() => 'Quota journalier atteint (100 req/jour en test)';
}

class QuotaService {
  static const String _prefsKeyBonus = 'quota_bonus_messages';

  /// Ajoute des requêtes bonus (ex: streak +2 messages, vidéo récompensée +5).
  Future<int> addBonus({int amount = 2}) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_prefsKeyBonus) ?? 0;
    final updated = current + amount;
    await prefs.setInt(_prefsKeyBonus, updated);
    debugPrint('[QuotaService] Bonus +$amount → bonus restants : $updated');
    return updated;
  }

  /// Vérifie et décrémente le quota de l'utilisateur.
  /// Retourne le nombre de requêtes restantes, ou -1 si Pro (illimité).
  Future<int> checkAndDecrement() async {
    // En mode DEMO, quota illimité (100 req/jour pour les tests)
    if (isDemoMode) {
      return 100;
    }

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('checkQuota');
      final result = await callable.call<Map<String, dynamic>>(
        <String, dynamic>{},
      );
      final data = result.data;
      final remaining = data['remaining'];
      int serverRemaining = 0;
      if (remaining is int) {
        serverRemaining = remaining;
      } else if (remaining is double) {
        serverRemaining = remaining.toInt();
      }

      final prefs = await SharedPreferences.getInstance();
      final localBonus = prefs.getInt(_prefsKeyBonus) ?? 0;
      return serverRemaining + localBonus;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        // Server quota exhausted — check local bonus
        final prefs = await SharedPreferences.getInstance();
        final localBonus = prefs.getInt(_prefsKeyBonus) ?? 0;
        if (localBonus > 0) {
          await prefs.setInt(_prefsKeyBonus, localBonus - 1);
          debugPrint('[QuotaService] Utilise bonus local → reste ${localBonus - 1}');
          return localBonus - 1;
        }
        throw const QuotaExceededException();
      }
      debugPrint('[QuotaService] FirebaseFunctionsException: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[QuotaService] Error: $e');
      rethrow;
    }
  }

  /// Retourne le total restant (serveur + bonus local).
  /// Note: nécessite un appel serveur pour la partie serveur.
  Future<int> getRemaining() async {
    if (isDemoMode) return 100;
    final prefs = await SharedPreferences.getInstance();
    final localBonus = prefs.getInt(_prefsKeyBonus) ?? 0;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('checkQuota');
      final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{});
      final data = result.data;
      final remaining = data['remaining'];
      int serverRemaining = 0;
      if (remaining is int) serverRemaining = remaining;
      if (remaining is double) serverRemaining = remaining.toInt();
      return serverRemaining + localBonus;
    } catch (e) {
      debugPrint('[QuotaService] getRemaining error: $e');
      return localBonus;
    }
  }
}

final quotaServiceProvider = Provider<QuotaService>((ref) => QuotaService());
