import 'package:flutter/foundation.dart';

/// DeepLinkService — stub web (pas de deep links sur web/extension).
class DeepLinkService {
  void listen({required Function(String code) onReferralCode}) {
    debugPrint('[DeepLinkService] Web stub: deep links non disponibles');
  }

  void dispose() {}

  String generateReferralUrl(String code) =>
      'https://aironbot.app/referral?code=$code';

  Future<void> shareReferralLink(String code) async {
    debugPrint('[DeepLinkService] Web stub: share non disponible');
  }

  Future<void> openReferralUrl(String code) async {
    debugPrint('[DeepLinkService] Web stub: url_launcher non disponible');
  }

  Future<void> copyReferralLink(String code) async {
    debugPrint('[DeepLinkService] Web stub: clipboard non disponible');
  }
}