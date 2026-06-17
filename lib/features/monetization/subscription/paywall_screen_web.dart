import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants.dart';
import '../../../core/platform/platform_service.dart';

/// Paywall screen — web / extension Chrome.
///
/// Sur mobile, le barrel `paywall_screen.dart` sélectionne
/// `paywall_screen_mobile.dart` (RevenueCat). Cette version web/extension
/// propose le checkout Stripe (ou la redirection vers corely.app).
class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExtension = PlatformService.isExtension;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6C63FF), Color(0xFF1A1A2E)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => context.pop(),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Icon(Icons.workspace_premium, size: 72, color: Colors.amber),
              const SizedBox(height: 16),
              const Text(
                'Corely Pro',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Débloquez des fonctionnalités avancées :',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              const SizedBox(height: 12),
              _featureRow('Modèles premium (Mistral Large, DeepSeek Pro)'),
              _featureRow('Requêtes illimitées'),
              _featureRow('Fichiers volumineux (50 MB)'),
              _featureRow('Génération d\'images IA'),
              _featureRow('Recherche vols & hôtels'),
              _featureRow('Mémoire agent persistante'),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: ElevatedButton(
                  onPressed: () => _openStripeCheckout(context, plan: 'monthly'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'S\'abonner via le site',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isExtension
                    ? 'Gérez votre abonnement sur corely.app'
                    : 'Paiement sécurisé via Stripe',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const Spacer(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.amber, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// Ouvre l'URL de checkout Stripe (mensuel par défaut).
  /// Fallback vers la page checkout du site si URL Stripe non configurée.
  Future<void> _openStripeCheckout(BuildContext context, {String plan = 'monthly'}) async {
    final url = plan == 'yearly'
        ? AppConstants.stripeCheckoutYearlyUrl
        : AppConstants.stripeCheckoutMonthlyUrl;
    final target = url.isNotEmpty ? url : '${AppConstants.appWebUrl}/checkout?plan=$plan';
    final uri = Uri.parse(target);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (kDebugMode) {
      debugPrint('[Paywall] Impossible d\'ouvrir l\'URL de checkout : $target');
    }
  }
}