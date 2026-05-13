import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/data/user_profile_sync.dart';
import '../../../main.dart' show isDemoMode;

/// SubscriptionService — stub web (pas de RevenueCat sur web).
class SubscriptionService {
  Future<void> init(String userId) async {}
  Future<dynamic> getOfferings() async => null;
  Future<bool> purchasePro(dynamic package) async => false;
  Future<bool> restorePurchases() async => false;
}

final subscriptionServiceProvider = Provider((_) => SubscriptionService());

/// Sur web/extension, le statut Pro est lu depuis Firestore en temps réel.
/// En mode DEMO (extension Chrome ou Firebase indisponible), retourne false.
final isProProvider = FutureProvider<bool>((ref) async {
  // Mode DEMO : pas de Firestore, pas de Pro
  if (isDemoMode) return false;

  // Mode debug : forcer Pro si DEBUG_FORCE_PRO
  const debugForcePro = bool.fromEnvironment('DEBUG_FORCE_PRO', defaultValue: false);
  if (!kReleaseMode && debugForcePro) {
    debugPrint('[Debug] Mode Pro active via DEBUG_FORCE_PRO');
    return true;
  }

  // Priorité : écoute temps réel via userProfileProvider
  final syncPro = ref.read(isProSyncProvider);
  if (syncPro) return true;

  final user = ref.watch(currentUserProvider);
  if (user == null) return false;

  try {
    final doc = await ref.watch(firestoreProvider)
        .collection(AppConstants.colUsers)
        .doc(user.uid as String)
        .get();
    final data = doc.data();
    return data?['plan'] == 'pro';
  } catch (e) {
    debugPrint('[isPro] Firestore indisponible : $e');
    return false;
  }
});