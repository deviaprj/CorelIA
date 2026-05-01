import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider d'etat du consentement GDPR.
final gdprConsentProvider = StateNotifierProvider<GdprConsentNotifier, bool?>(
  (ref) => GdprConsentNotifier(),
);

class GdprConsentNotifier extends StateNotifier<bool?> {
  GdprConsentNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool('gdpr_ads_consent');
    state = stored;
  }

  Future<void> setConsent(bool accepted) async {
    state = accepted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gdpr_ads_consent', accepted);
  }
}

/// Bandeau de consentement GDPR pour AdMob.
/// Affiche une bottom sheet si le consentement n'a pas encore ete donne.
class ConsentBanner {
  static Future<void> showIfNeeded(BuildContext context, WidgetRef ref) async {
    final consent = ref.read(gdprConsentProvider);
    if (consent != null) return; // deja repondu

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Protection de vos donnees',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Nous utilisons des publicites personnalisees pour financer '
                "l'application. Acceptez-vous que Google AdMob collecte "
                'des donnees pour vous proposer des annonces adaptees ?',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        ref.read(gdprConsentProvider.notifier).setConsent(false);
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Refuser'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        ref.read(gdprConsentProvider.notifier).setConsent(true);
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Accepter'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
