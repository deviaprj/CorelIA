import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/secure_storage.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../monetization/subscription/subscription_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  bool _apiKeyVisible = false;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final storage = ref.read(secureStorageProvider);
    final key = await storage.read(StorageKeys.apiKeyDeepSeek);
    if (key != null && mounted) {
      _apiKeyController.text = key;
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveApiKey() async {
    final storage = ref.read(secureStorageProvider);
    await storage.write(StorageKeys.apiKeyDeepSeek, _apiKeyController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clé API sauvegardée')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final user = ref.watch(currentUserProvider);
    final isPro = ref.watch(isProProvider).valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        children: [
          // ── Compte ──────────────────────────────────────────────────────
          _SectionTitle('Compte'),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(user?.displayName ?? user?.email ?? 'Anonyme'),
            subtitle: Text(
                isPro ? '✨ Plan Pro actif' : 'Plan Gratuit · 20 req/jour'),
          ),
          if (!isPro)
            ListTile(
              leading: const Icon(Icons.workspace_premium,
                  color: Colors.amber),
              title: const Text('Passer en Pro'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/paywall'),
            ),

          // ── Apparence ────────────────────────────────────────────────────
          _SectionTitle('Apparence'),
          ListTile(
            leading: const Icon(Icons.nights_stay_outlined),
            title: const Text('Thème sombre'),
            trailing: Switch(
              value: themeMode == ThemeMode.dark,
              onChanged: (v) {
                ref.read(themeModeProvider.notifier).setTheme(
                      v ? ThemeMode.dark : ThemeMode.light,
                    );
              },
            ),
          ),

          // ── Clé API perso ────────────────────────────────────────────────
          _SectionTitle('Clé API DeepSeek (optionnel)'),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _apiKeyController,
              obscureText: !_apiKeyVisible,
              decoration: InputDecoration(
                labelText: 'sk-...',
                helperText: 'Utilisez votre propre quota',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_apiKeyVisible
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setState(
                          () => _apiKeyVisible = !_apiKeyVisible),
                    ),
                    IconButton(
                      icon: const Icon(Icons.save_outlined),
                      onPressed: _saveApiKey,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Déconnexion / Suppression ────────────────────────────────────
          _SectionTitle('Danger zone'),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Se déconnecter'),
            onTap: () async {
              await ref.read(authNotifierProvider.notifier).signOut();
              if (context.mounted) context.go('/login');
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_forever,
                color: Theme.of(context).colorScheme.error),
            title: Text(
              'Supprimer mon compte',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => _confirmDeleteAccount(context),
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              'AironBot v1.0.0',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le compte ?'),
        content: const Text(
            'Cette action est irréversible. Toutes vos données seront effacées.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await ref.read(authNotifierProvider.notifier).deleteAccount();
      if (context.mounted) context.go('/login');
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1,
            ),
      ),
    );
  }
}
