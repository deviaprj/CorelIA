import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'referral_service.dart';

/// Service de deep links pour le parrainage.
///
/// Utilise `app_links` pour capturer les liens entrants (Android/iOS)
/// et `url_launcher` + `share_plus` pour générer et partager les liens.
class DeepLinkService {
  static const _baseReferralUrl = 'https://aironbot.app/referral';
  static const _referralScheme = 'aironbot://referral';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription? _linkSubscription;

  /// Initialise l'écoute des deep links entrants.
  void listen({required Function(String code) onReferralCode}) {
    // Écoute les liens entrants (cold start + warm start)
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri, onReferralCode);
    });

    // Vérifie s'il y a un lien initial au cold start
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleUri(uri, onReferralCode);
    });
  }

  void dispose() {
    _linkSubscription?.cancel();
  }

  void _handleUri(Uri uri, Function(String code) onReferralCode) {
    debugPrint('[DeepLink] Lien reçu : $uri');
    final code = _extractCode(uri);
    if (code != null && code.isNotEmpty) {
      debugPrint('[DeepLink] Code extrait : $code');
      onReferralCode(code);
    }
  }

  String? _extractCode(Uri uri) {
    // Schemes supportés : https://aironbot.app/referral?code=ABC123
    //                      aironbot://referral?code=ABC123
    if (uri.host == 'aironbot.app' && uri.path == '/referral') {
      return uri.queryParameters['code'];
    }
    if (uri.scheme == 'aironbot' && uri.host == 'referral') {
      return uri.queryParameters['code'];
    }
    return null;
  }

  /// Génère l'URL de parrainage pour un code donné.
  String generateReferralUrl(String code) {
    return '$_baseReferralUrl?code=$code';
  }

  /// Partage le lien de parrainage via les options natives du téléphone.
  Future<void> shareReferralLink(String code) async {
    final url = generateReferralUrl(code);
    final text = 'Rejoins AironBot avec mon code parrain : $code\n'
        'On gagne chacun +5 requêtes IA gratuites !\n'
        '$url';
    await Share.share(text);
  }

  /// Ouvre le lien de parrainage dans le navigateur (pour tests/debug).
  Future<void> openReferralUrl(String code) async {
    final url = generateReferralUrl(code);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Copie le lien dans le presse-papiers.
  Future<void> copyReferralLink(String code) async {
    final url = generateReferralUrl(code);
    await Clipboard.setData(ClipboardData(text: url));
  }
}
