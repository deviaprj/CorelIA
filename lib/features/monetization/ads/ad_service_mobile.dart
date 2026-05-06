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
    RewardedAd? ad;
    await RewardedAd.load(
      adUnitId: AppConstants.admobRewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (a) => ad = a,
        onAdFailedToLoad: (_) {},
      ),
    );
    return ad;
  }

  static Future<bool> showRewarded({
    required Future<RewardedAd?> Function() loadAd,
    required void Function(dynamic) onEarned,
  }) async {
    if (!_adsEnabled) return false;
    final ad = await loadAd();
    if (ad == null) return false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) => a.dispose(),
      onAdFailedToShowFullScreenContent: (a, _) => a.dispose(),
    );
    ad.show(onUserEarnedReward: (_, reward) => onEarned(reward));
    return true;
  }
}
