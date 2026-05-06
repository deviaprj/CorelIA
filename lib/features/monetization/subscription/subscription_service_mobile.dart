import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../../core/constants.dart';
import '../../../core/platform/platform_service.dart';
import '../../../core/providers/firebase_providers.dart';

class SubscriptionService {
  Future<void> init(String userId) async {
    if (PlatformService.isExtension) return;

    final key = PlatformService.current == AppPlatform.mobileAndroid
        ? AppConstants.revenueCatApiKeyAndroid
        : AppConstants.revenueCatApiKeyIos;

    await Purchases.setLogLevel(LogLevel.debug);
    final config = PurchasesConfiguration(key)..appUserID = userId;
    await Purchases.configure(config);
  }

  Future<Offerings?> getOfferings() async {
    try {
      return await Purchases.getOfferings();
    } catch (_) {
      return null;
    }
  }

  Future<bool> purchasePro(Package package) async {
    try {
      final info = await Purchases.purchasePackage(package);
      return _isPro(info);
    } on PurchasesErrorCode catch (_) {
      return false;
    }
  }

  Future<bool> restorePurchases() async {
    try {
      final info = await Purchases.restorePurchases();
      return _isPro(info);
    } catch (_) {
      return false;
    }
  }

  static bool _isPro(CustomerInfo info) =>
      info.entitlements.active.containsKey('pro');
}

// ── Providers ─────────────────────────────────────────────────────────────────
final subscriptionServiceProvider = Provider((_) => SubscriptionService());

final isProProvider = FutureProvider<bool>((ref) async {
  // Mode debug/test : forcer Pro SEULEMENT si la variable d'env DEBUG_FORCE_PRO est définie
  // Ne JAMAIS activer par défaut en debug pour éviter les bypass de sécurité
  const debugForcePro = bool.fromEnvironment('DEBUG_FORCE_PRO', defaultValue: false);
  if (!kReleaseMode && debugForcePro) {
    debugPrint('[Debug] Mode Pro activé via DEBUG_FORCE_PRO');
    return true;
  }

  if (PlatformService.isExtension) {
    // Extension : lire le plan depuis Firestore
    final user = ref.watch(currentUserProvider);
    if (user == null) return false;
    try {
      final doc = await ref.watch(firestoreProvider)
          .collection(AppConstants.colUsers)
          .doc(user.uid as String)
          .get();
      final data = doc.data();
      return data?['plan'] == 'pro';
    } catch (_) {
      return false;
    }
  }
  try {
    final info = await Purchases.getCustomerInfo();
    return SubscriptionService._isPro(info);
  } catch (_) {
    return false;
  }
});
