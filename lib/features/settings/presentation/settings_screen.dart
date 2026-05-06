import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/secure_storage.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../monetization/subscription/subscription_service.dart';
import '../../referral/data/referral_service.dart';

// ── System prompt provider ──────────────────────────────────────────────────
const _systemPromptKey = 'corely_system_prompt';
const _defaultSystemPrompt =
    'Tu es Corely, un assistant IA conversationnel chaleureux et intelligent. '
    'Tu rédiges en français par défaut. Tu es direct, utile, et concis. '
    'Tu utilises le tutoiement par défaut. Tu ne dis JAMAIS "en tant que modèle de langage".';

final systemPromptProvider = StateNotifierProvider<SystemPromptNotifier, String>(
  (ref) => SystemPromptNotifier(),
);

class SystemPromptNotifier extends StateNotifier<String> {
  SystemPromptNotifier() : super(_defaultSystemPrompt);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_systemPromptKey);
    if (saved != null) state = saved;
  }

  Future<void> save(String prompt) async {
    state = prompt;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_systemPromptKey, prompt);
  }

  Future<void> reset() async {
    state = _defaultSystemPrompt;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_systemPromptKey);
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _systemPromptController;

  @override
  void initState() {
    super.initState();
    _systemPromptController = TextEditingController(text: ref.read(systemPromptProvider));
    // Charger le prompt système sauvegardé
    ref.read(systemPromptProvider.notifier).load().then((_) {
      if (mounted) {
        _systemPromptController.text = ref.read(systemPromptProvider);
      }
    });
  }

  @override
  void dispose() {
    _systemPromptController.dispose();
    super.dispose();
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
            title: Text(user?.displayName ?? user?.email ?? 'Anonyme' as String),
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

          // ── Prompt système ──────────────────────────────────────────────
          _SectionTitle('Prompt système'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Personnalisez le comportement de Corely. '
                  'Ce prompt est injecté au début de chaque conversation.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _systemPromptController,
                  maxLines: 8,
                  minLines: 6,
                  decoration: InputDecoration(
                    hintText: 'Décrivez comment Corely doit se comporter...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Charger un fichier .txt/.md
                    OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('Fichier'),
                      onPressed: _loadSystemPromptFromFile,
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        _systemPromptController.text = _defaultSystemPrompt;
                        ref.read(systemPromptProvider.notifier).reset();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Prompt réinitialisé')),
                        );
                      },
                      child: const Text('Réinitialiser'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final prompt = _systemPromptController.text.trim();
                        if (prompt.isEmpty) return;
                        ref.read(systemPromptProvider.notifier).save(prompt);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Prompt sauvegardé')),
                        );
                      },
                      child: const Text('Sauvegarder'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Parrainage ─────────────────────────────────────────────────
          _SectionTitle('Parrainage'),
          _ReferralSection(),

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
              'Corely v1.1.0',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _loadSystemPromptFromFile() async {
    // Utiliser le package file_picker ou un InputElement web
    // Pour l'instant, on utilise Clipboard comme fallback
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      _systemPromptController.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Collé depuis le presse-papier')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Presse-papier vide. Copiez le contenu d\'un fichier .txt ou .md puis appuyez sur Fichier.')),
      );
    }
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

class _ReferralSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ReferralSection> createState() => _ReferralSectionState();
}

class _ReferralSectionState extends ConsumerState<_ReferralSection> {
  final _codeController = TextEditingController();
  bool _applying = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _applyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _applying = true);
    try {
      final success = await ref
          .read(referralServiceProvider)
          .applyReferralCode(user.uid, code);
      if (!mounted) return;

      if (success) {
        _codeController.clear();
        ref.invalidate(hasReferrerProvider);
        ref.invalidate(referralCountProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Code parrain appliqué ! +5 requêtes bonus 🎉'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Code invalide ou déjà utilisé'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _shareCode(String code) {
    final text = 'Rejoins Corely avec mon code parrain : $code\n'
        'On gagne chacun +5 requêtes IA gratuites !\n'
        'https://aironbot.app';
    Share.share(text);
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copié dans le presse-papier')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final codeAsync = ref.watch(referralCodeProvider);
    final countAsync = ref.watch(referralCountProvider);
    final hasReferrerAsync = ref.watch(hasReferrerProvider);

    return Column(
      children: [
        codeAsync.when(
          data: (code) => code != null
              ? ListTile(
                  leading: const Icon(Icons.card_giftcard, color: Colors.green),
                  title: Text('Mon code : $code',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, letterSpacing: 2)),
                  subtitle: const Text('Partagez pour gagner +5 requêtes'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () => _copyCode(code),
                      ),
                      IconButton(
                        icon: const Icon(Icons.share),
                        onPressed: () => _shareCode(code),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
          loading: () => const ListTile(
            leading: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2)),
            title: Text('Chargement...'),
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),

        countAsync.when(
          data: (count) => ListTile(
            leading: const Icon(Icons.people_outline),
            title: Text('$count filleul${count > 1 ? 's' : ''} parrainé${count > 1 ? 's' : ''}'),
            subtitle: Text(count > 0
                ? 'Bonus total : +${count * 5} requêtes'
                : 'Invitez des amis pour gagner des bonus'),
          ),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),

        hasReferrerAsync.when(
          data: (hasReferrer) => hasReferrer
              ? const ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.green),
                  title: Text('Code parrain déjà appliqué ✓'),
                )
              : Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Code parrain',
                            hintText: 'Ex: A1B2C3D4',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _applying ? null : _applyCode,
                        child: _applying
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Appliquer'),
                      ),
                    ],
                  ),
                ),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}