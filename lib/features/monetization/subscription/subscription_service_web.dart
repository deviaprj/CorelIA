import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// SubscriptionService — stub web (pas de RevenueCat sur web).
class SubscriptionService {
  Future<void> init(String userId) async {}
  Future<dynamic> getOfferings() async => null;
  Future<bool> purchasePro(dynamic package) async => false;
  Future<bool> restorePurchases() async => false;
}

final subscriptionServiceProvider = Provider((_) => SubscriptionService());

final isProProvider = FutureProvider<bool>((ref) async => false);