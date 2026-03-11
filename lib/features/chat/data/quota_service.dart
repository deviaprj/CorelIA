import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QuotaExceededException implements Exception {
  const QuotaExceededException();
  @override
  String toString() => 'Quota journalier atteint (20 req/jour)';
}

class QuotaService {
  /// Vérifie et décrémente le quota de l'utilisateur.
  /// Retourne le nombre de requêtes restantes, ou -1 si Pro (illimité).
  Future<int> checkAndDecrement() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('checkQuota');
      final result = await callable.call<Map<String, dynamic>>(
        <String, dynamic>{},
      );
      final data = result.data;
      final remaining = data['remaining'];
      if (remaining is int) return remaining;
      if (remaining is double) return remaining.toInt();
      return 0;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        throw const QuotaExceededException();
      }
      // Si la fonction n'est pas déployée ou autre erreur
      debugPrint('[QuotaService] FirebaseFunctionsException: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[QuotaService] Error: $e');
      rethrow;
    }
  }
}

final quotaServiceProvider = Provider<QuotaService>((ref) => QuotaService());
