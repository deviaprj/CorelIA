import 'package:flutter/material.dart';

/// AdService — stub web (pas de SDK AdMob sur web).
class AdService {
  AdService._();

  static Future<void> init() async {}

  static dynamic createBanner({required dynamic listener}) => null;

  static Future<dynamic> loadInterstitial() async => null;

  static Future<dynamic> loadRewarded() async => null;

  static Future<bool> showRewarded({
    required Future<dynamic> Function() loadAd,
    required void Function(dynamic) onEarned,
  }) async => false;
}

/// Widget bannière publicitaire — stub web (rien à afficher).
class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({super.key});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}