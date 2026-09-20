import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/user_role.dart';

/// Gère l'abonnement « Agent IA Full » via RevenueCat et synchronise le rôle
/// dans Firestore (`users/{uid}.plan`).
class SubscriptionService {
  /// État partagé : le SDK RevenueCat est configuré une seule fois par process,
  /// quelle que soit l'instance utilisée (main.dart puis écran d'abonnement).
  static bool _configured = false;

  /// Initialise le SDK RevenueCat pour l'utilisateur connecté.
  Future<void> init(String userId) async {
    if (isDemoMode || userId.isEmpty) return;
    final apiKey = _apiKey;
    if (apiKey.isEmpty) {
      debugPrint('[RevenueCat] Clé absente — abonnement désactivé');
      return;
    }
    try {
      await Purchases.setLogLevel(LogLevel.info);
      await Purchases.configure(
        PurchasesConfiguration(apiKey)..appUserID = userId,
      );
      _configured = true;
    } catch (e) {
      debugPrint('[RevenueCat] Initialisation échouée : $e');
    }
  }

  /// Offres disponibles (null si RevenueCat n'est pas configuré).
  Future<Offerings?> getOfferings() async {
    if (!_configured) return null;
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      debugPrint('[RevenueCat] Offres indisponibles : $e');
      return null;
    }
  }

  /// Achète l'offre Full et met à jour le rôle.
  Future<bool> purchaseFull(Package package, {required String userId}) async {
    if (!_configured) return false;
    try {
      final info = await Purchases.purchasePackage(package);
      final role = _roleFrom(info);
      await _syncRole(userId, role);
      return role.isFull;
    } catch (e) {
      debugPrint('[RevenueCat] Achat annulé ou échoué : $e');
      return false;
    }
  }

  /// Restaure les achats existants.
  Future<bool> restore({required String userId}) async {
    if (!_configured) return false;
    try {
      final info = await Purchases.restorePurchases();
      final role = _roleFrom(info);
      await _syncRole(userId, role);
      return role.isFull;
    } catch (e) {
      debugPrint('[RevenueCat] Restauration échouée : $e');
      return false;
    }
  }

  static UserRole _roleFrom(CustomerInfo info) =>
      info.entitlements.active.containsKey(AppConfig.entitlementFull)
          ? UserRole.full
          : UserRole.free;

  Future<void> _syncRole(String userId, UserRole role) async {
    if (isDemoMode || userId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection(AppConfig.colUsers)
          .doc(userId)
          .set({'plan': role.id}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Firestore] Synchronisation du rôle échouée : $e');
    }
  }

  static String get _apiKey => switch (defaultTargetPlatform) {
        TargetPlatform.android => AppConfig.revenueCatApiKeyAndroid,
        TargetPlatform.iOS => AppConfig.revenueCatApiKeyIos,
        _ => '',
      };
}

final subscriptionServiceProvider =
    Provider<SubscriptionService>((ref) => SubscriptionService());
