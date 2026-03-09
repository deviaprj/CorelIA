import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QuotaExceededException implements Exception {
  const QuotaExceededException();
  @override
  String toString() => 'Quota journalier atteint (20 req/jour)';
}

class QuotaService {
  Future<int> checkAndDecrement() async {
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('checkQuota');
      final result = await callable.call<Map<Object?, Object?>>(<String, dynamic>{});
      return (result.data['remaining'] as int?) ?? 0;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        throw const QuotaExceededException();
      }
      rethrow;
    }
  }
}

final quotaServiceProvider = Provider<QuotaService>((ref) => QuotaService());
