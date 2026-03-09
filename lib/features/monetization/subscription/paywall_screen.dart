import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'subscription_service.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _loading = false;

  Future<void> _purchasePro(Package package) async {
    setState(() => _loading = true);
    try {
      final ok = await ref
          .read(subscriptionServiceProvider)
          .purchasePro(package);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bienvenue en Pro !')),
        );
        ref.invalidate(isProProvider);
        context.pop();
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
    final offAsync = ref.watch(
      FutureProvider<Offerings?>(
        (ref) => ref.read(subscriptionServiceProvider).getOfferings(),
      ),
    );

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
                  'AironBot Pro',
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
                  error: (_, __) => const Text(
                    'Erreur de chargement',
                    style: TextStyle(color: Colors.white70),
                  ),
                  data: (offerings) {
                    final pkg =
                        offerings?.current?.monthly;
                    if (pkg == null) {
                      return const Text(
                        'Offres non disponibles',
                        style:
                            TextStyle(color: Colors.white70),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
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
                                      'S\'abonner ${pkg.storeProduct.priceString}/mois',
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
