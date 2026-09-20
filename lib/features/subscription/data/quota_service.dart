import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/user_role.dart';
import '../domain/quota_policy.dart';

/// Erreur levée lorsque le quota journalier du rôle est épuisé.
class QuotaExceededException implements Exception {
  const QuotaExceededException(this.role, this.dailyLimit);

  final UserRole role;
  final int dailyLimit;

  @override
  String toString() =>
      'Quota journalier atteint (${role.label} : $dailyLimit requêtes/jour).';
}

/// Compteur de requêtes journalier, dépendant du rôle.
///
/// 100 % local (SharedPreferences) : remis à zéro automatiquement chaque jour.
class QuotaService {
  static const String _countKey = 'quota_requests_count';
  static const String _dateKey = 'quota_requests_date';

  /// Requêtes restantes aujourd'hui (ou `null` si illimité).
  Future<int?> remaining(UserRole role) async {
    final policy = QuotaPolicies.forRole(role);
    if (policy.unlimited) return null;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_dateKey) != _today) {
      return policy.dailyRequests;
    }
    return prefs.getInt(_countKey) ?? policy.dailyRequests!;
  }

  /// Décrémente le quota. Lève [QuotaExceededException] si épuisé.
  /// Retourne le nombre de requêtes restantes (ou `null` si illimité).
  Future<int?> consume(UserRole role) async {
    final policy = QuotaPolicies.forRole(role);
    if (policy.unlimited) return null;

    final prefs = await SharedPreferences.getInstance();
    final limit = policy.dailyRequests!;

    var remaining = prefs.getString(_dateKey) == _today
        ? prefs.getInt(_countKey) ?? limit
        : limit;

    if (remaining <= 0) {
      throw QuotaExceededException(role, limit);
    }

    remaining -= 1;
    await prefs.setString(_dateKey, _today);
    await prefs.setInt(_countKey, remaining);
    debugPrint('[Quota] ${role.id} → $remaining requête(s) restante(s)');
    return remaining;
  }

  /// Réinitialise le compteur (après passage en Full ou pour les tests).
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_countKey);
    await prefs.remove(_dateKey);
  }

  static String get _today {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }
}

final quotaServiceProvider = Provider<QuotaService>((ref) => QuotaService());
