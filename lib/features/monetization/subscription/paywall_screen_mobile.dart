import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'subscription_service.dart';

final _offeringsProvider = FutureProvider<Offerings?>((ref) {
  return ref.read(subscriptionServiceProvider).getOfferings();
});

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _loading = false;

  Future<void> _purchasePro(Package? package, {String? stripeUrl}) async {
    setState(() => _loading = true);
    try {
      if (package != null) {
        final ok = await ref
            .read(subscriptionServiceProvider)
            .purchasePro(package);
        if (ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bienvenue en Pro !')),
          );
          ref.invalidate(isProProvider);
          context.pop();
          return;
        }
      }
      // Fallback : ouvrir Stripe URL si RevenueCat echoue ou n'est pas configure
      if (stripeUrl != null && mounted) {
        final uri = Uri.parse(stripeUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Redirection vers la page de paiement...')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _loading = true);
    try {
      final ok = await ref
          .read(subscriptionServiceProvider)
          .restorePurchases();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? 'Abonnement Pro restauré !'
                : 'Aucun achat trouvé.'),
          ),
        );
        if (ok) {
          ref.invalidate(isProProvider);
          context.pop();
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offAsync = ref.watch(_offeringsProvider);

    return Scaffold(
      body: Stack(
        children: [
          // Fond dégradé
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF6C63FF), Color(0xFF1A1A2E)],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white),
                        onPressed: () => context.pop(),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Icon(Icons.workspace_premium,
                    size: 72, color: Colors.amber),
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
                _FeatureList(),
                const Spacer(),
                offAsync.when(
                  loading: () =>
                      const CircularProgressIndicator(color: Colors.white),
                  error: (_, __) => _buildPricingFallback(),
                  data: (offerings) {
                    // Récupérer le package mensuel ou annuel
                    Package? pkg = offerings?.current?.monthly;
                    pkg ??= offerings?.current?.annual;
                    pkg ??= offerings?.current?.availablePackages.firstOrNull;

                    if (pkg == null) {
                      return _buildPricingFallback();
                    }

                    final isAnnual = pkg.packageType == PackageType.annual;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          // Badge économie pour annuel
                          if (isAnnual)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Économisez 17%',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _loading
                                  ? null
                                  : () => _purchasePro(pkg),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: _loading
                                  ? const CircularProgressIndicator()
                                  : Text(
                                      'S\'abonner ${pkg.storeProduct.priceString}${isAnnual ? '/an' : '/mois'}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _loading ? null : _restore,
                            child: const Text(
                              'Restaurer mes achats',
                              style: TextStyle(color: Colors.white60),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Affiche les tarifs par defaut quand RevenueCat n'est pas configure.
  Widget _buildPricingFallback() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const Text(
            'Corely Pro',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          // Option mensuelle
          _PricingCard(
            title: 'Mensuel',
            price: '4,99 €',
            period: '/mois',
            onTap: _loading
                ? null
                : () => _purchasePro(null,
                      stripeUrl:
                          'https://buy.stripe.com/test_corely_monthly',
                    ),
          ),
          const SizedBox(height: 12),
          // Option annuelle
          _PricingCard(
            title: 'Annuel',
            price: '49,99 €',
            period: '/an',
            badge: 'Économisez 17%',
            onTap: _loading
                ? null
                : () => _purchasePro(null,
                      stripeUrl:
                          'https://buy.stripe.com/test_corely_yearly',
                    ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _loading ? null : _restore,
            child: const Text(
              'Restaurer mes achats',
              style: TextStyle(color: Colors.white60),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Paiement sécurisé via Stripe ou App Store',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  final String title;
  final String price;
  final String period;
  final String? badge;
  final VoidCallback? onTap;

  const _PricingCard({
    required this.title,
    required this.price,
    required this.period,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (badge != null)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  Text(
                    price,
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    period,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios,
                  color: Colors.white38, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final features = [
      ('Requêtes illimitées', Icons.all_inclusive),
      ('Contexte 128k tokens', Icons.memory),
      ('Modèles Pro (Mistral, Llama)', Icons.auto_awesome),
      ('Sans publicité', Icons.block),
      ('Support prioritaire', Icons.support_agent),
    ];
    return Column(
      children: features
          .map(
            (f) => Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 40, vertical: 6),
              child: Row(
                children: [
                  Icon(f.$2, color: Colors.amber, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    f.$1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
