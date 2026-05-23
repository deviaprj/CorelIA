import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../core/constants.dart';
import '../../../core/platform/platform_service.dart';

class AdService {
  AdService._();

  static bool get _adsEnabled =>
      PlatformService.isMobile;

  // ── Initialisation ────────────────────────────────────────────────────────
  static Future<void> init() async {
    if (!_adsEnabled) return;
    await MobileAds.instance.initialize();
  }

  // ── Bannière ──────────────────────────────────────────────────────────────
  static BannerAd createBanner({
    required BannerAdListener listener,
  }) {
    return BannerAd(
      adUnitId: AppConstants.admobBannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: listener,
    );
  }

  // ── Interstitiel ──────────────────────────────────────────────────────────
  static Future<InterstitialAd?> loadInterstitial() async {
    if (!_adsEnabled) return null;
    InterstitialAd? ad;
    await InterstitialAd.load(
      adUnitId: AppConstants.admobInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (a) => ad = a,
        onAdFailedToLoad: (_) {},
      ),
    );
    return ad;
  }

  // ── Récompensé ────────────────────────────────────────────────────────────
  static Future<RewardedAd?> loadRewarded() async {
    if (!_adsEnabled) return null;

    final adUnitId = AppConstants.admobRewardedId;
    if (adUnitId.isEmpty) {
      debugPrint('[AdService] admobRewardedId is empty — using test unit ID');
    }

    // Retry x3 avec backoff exponentiel
    for (var attempt = 1; attempt <= 3; attempt++) {
      RewardedAd? ad;
      LoadAdError? lastError;

      final completer = Completer<void>();
      await RewardedAd.load(
        adUnitId: adUnitId.isNotEmpty ? adUnitId : 'ca-app-pub-3940256099942544/5224354917',
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (a) {
            ad = a;
            completer.complete();
          },
          onAdFailedToLoad: (err) {
            lastError = err;
            completer.complete();
          },
        ),
      );
      await completer.future.timeout(const Duration(seconds: 10), onTimeout: () {});

      if (ad != null) {
        debugPrint('[AdService] Rewarded ad loaded on attempt $attempt');
        return ad;
      }

      debugPrint('[AdService] Rewarded ad load failed (attempt $attempt): ${lastError?.message ?? "timeout"}');
      if (attempt < 3) {
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
    return null;
  }

  static Future<bool> showRewarded({
    required Future<RewardedAd?> Function() loadAd,
    required void Function(dynamic) onEarned,
    void Function(String)? onError,
  }) async {
    if (!_adsEnabled) {
      onError?.call('Publicités non disponibles sur cette plateforme');
      return false;
    }
    final ad = await loadAd();
    if (ad == null) {
      onError?.call('Impossible de charger la vidéo. Vérifiez votre connexion.');
      return false;
    }
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        debugPrint('[AdService] Rewarded ad showed');
      },
      onAdDismissedFullScreenContent: (a) {
        debugPrint('[AdService] Rewarded ad dismissed');
        a.dispose();
      },
      onAdFailedToShowFullScreenContent: (a, err) {
        debugPrint('[AdService] Rewarded ad failed to show: ${err.message}');
        a.dispose();
        onError?.call('Erreur lors de l\'affichage de la vidéo.');
      },
    );
    ad.show(onUserEarnedReward: (_, reward) {
      debugPrint('[AdService] Reward earned: ${reward.amount} ${reward.type}');
      onEarned(reward);
    });
    return true;
  }
}
