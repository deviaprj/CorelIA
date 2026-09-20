import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/user_role.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/data/user_profile_sync.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../chat/presentation/chat_notifier.dart';
import '../data/role_providers.dart';
import '../data/subscription_service.dart';
import '../domain/quota_policy.dart';

/// Écran de gestion du rôle et de l'abonnement.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  Offerings? _offerings;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    final service = ref.read(subscriptionServiceProvider);
    final userId = ref.read(currentUserProvider)?.uid;
    if (userId != null) await service.init(userId);
    final offerings = await service.getOfferings();
    if (mounted) setState(() => _offerings = offerings);
  }

  Future<void> _purchase() async {
    final userId = ref.read(currentUserProvider)?.uid;
    final package = _offerings?.current?.availablePackages.firstOrNull;
    if (userId == null || package == null) {
      _notify('Abonnement indisponible pour le moment.');
      return;
    }

    setState(() => _loading = true);
    final ok = await ref
        .read(subscriptionServiceProvider)
        .purchaseFull(package, userId: userId);
    if (!mounted) return;
    setState(() => _loading = false);

    if (ok) {
      await _onRoleChanged();
      _notify('Bienvenue dans l\'Agent IA Full !');
    } else {
      _notify('Achat annulé.');
    }
  }

  Future<void> _restore() async {
    final userId = ref.read(currentUserProvider)?.uid;
    if (userId == null) return;

    setState(() => _loading = true);
    final ok =
        await ref.read(subscriptionServiceProvider).restore(userId: userId);
    if (!mounted) return;
    setState(() => _loading = false);

    if (ok) {
      await _onRoleChanged();
      _notify('Abonnement restauré.');
    } else {
      _notify('Aucun abonnement trouvé.');
    }
  }

  /// Rafraîchit le rôle et débloque un éventuel message en attente.
  Future<void> _onRoleChanged() async {
    ref.invalidate(userProfileProvider);
    // Laisse le temps au flux Firestore de propager le nouveau rôle.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final chat = ref.read(chatNotifierProvider.notifier);
    await chat.refreshQuota();
    await chat.retryPendingMessage();
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(userRoleProvider);
    final policy = QuotaPolicies.forRole(role);
    final price = _offerings?.current?.availablePackages.firstOrNull
        ?.storeProduct.priceString;

    return Scaffold(
      appBar: AppBar(title: const Text('Mon abonnement')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _RoleCard(
            role: role,
            title: role.label,
            subtitle: policy.unlimited
                ? 'Requêtes illimitées et fonctionnalités avancées.'
                : '${policy.dailyRequests} requêtes par jour, '
                    'recherche Internet incluse.',
            highlighted: role.isFull,
          ),
          const SizedBox(height: 20),
          if (!role.isFull) ...[
            _PlanCard(
              title: UserRole.full.label,
              price: price,
              features: const [
                'Requêtes illimitées',
                'Recherche Internet illimitée',
                'Pièces jointes jusqu\'à 25 Mo',
                'Modèles IA premium (raisonnement, vision)',
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _purchase,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      price == null
                          ? 'Passer à l\'Agent IA Full'
                          : 'Passer à l\'Agent IA Full — $price',
                    ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loading ? null : _restore,
              child: const Text('Restaurer mes achats'),
            ),
          ] else
            Center(
              child: Text(
                'Merci ! Votre abonnement est actif.',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          const Divider(height: 40),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Se déconnecter'),
            onTap: () => ref.read(authNotifierProvider.notifier).signOut(),
          ),
          if (isDemoMode)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Mode démo : Firebase et paiement désactivés.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.title,
    required this.subtitle,
    required this.highlighted,
  });

  final UserRole role;
  final String title;
  final String subtitle;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.accent.withOpacity(0.15)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: highlighted
            ? Border.all(color: AppColors.primary, width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          Icon(
            highlighted ? Icons.workspace_premium : Icons.person_outline,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.features,
    this.price,
  });

  final String title;
  final List<String> features;
  final String? price;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.primary,
                ),
              ),
              if (price != null)
                Text(
                  price!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ...features.map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(feature)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
