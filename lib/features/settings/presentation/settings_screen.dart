import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/cofely_theme.dart';
import '../../../core/language/language_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/secure_storage.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../monetization/subscription/subscription_service.dart';
import '../../referral/data/referral_service.dart';
import '../../retention/data/retention_providers.dart';
import '../../retention/data/streak_service.dart';
import '../../monetization/data/consent_data_service.dart';
import '../../monetization/data/anonymized_insight_service.dart';

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
      // AppBar Cofely : logo « C » dégradé en leading, couleurs du thème
      appBar: AppBar(
        title: const Text('Paramètres'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: CofelyTokens.avatarGradient,
              ),
              child: const Center(
                child: Text(
                  'C',
                  style: TextStyle(
                    color: CofelyTokens.onPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Langue'),
            trailing: DropdownButton<AppLanguage>(
              value: ref.watch(languageProvider),
              underline: const SizedBox.shrink(),
              onChanged: (lang) {
                if (lang != null) {
                  ref.read(languageProvider.notifier).setLanguage(lang);
                }
              },
              items: AppLanguage.values
                  .map((l) => DropdownMenuItem(
                        value: l,
                        child: Text(l.displayName),
                      ))
                  .toList(),
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
                  autofocus: false,
                  keyboardType: TextInputType.multiline,
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

          // ── Statistiques & Rétention ─────────────────────────────────────
          _SectionTitle('Statistiques'),
          _StatsSection(),
          _StreakSection(),

          _SectionTitle('Rétention'),
          _DailyQuestionToggle(),

          // ── Données et confidentialité ─────────────────────────────────────
          _SectionTitle('Données et confidentialité'),
          _DataConsentTile(),
          _DataExportTile(),
          _DataDeleteTile(),

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
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'json', 'yaml', 'yml'],
        withData: true,
        withReadStream: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          final text = String.fromCharCodes(file.bytes!);
          _systemPromptController.text = text;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Chargé : ${file.name} (${text.length} caractères)')),
            );
          }
        } else {
          // Fallback : clipboard pour les plateformes sans accès direct
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          final text = data?.text;
          if (text != null && text.isNotEmpty) {
            _systemPromptController.text = text;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Collé depuis le presse-papier')),
              );
            }
          }
        }
      }
    } catch (e) {
      // Fallback clipboard si file_picker échoue (ex: plateforme non supportée)
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text;
        if (text != null && text.isNotEmpty) {
          _systemPromptController.text = text;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Collé depuis le presse-papier')),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aucun fichier sélectionné et presse-papier vide.')),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impossible de charger le fichier.')),
          );
        }
      }
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
        'https://zentic.fr';
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

class _StatsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(usageStatsProvider);

    return statsAsync.when(
      data: (stats) {
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Messages envoyes'),
              trailing: Text(
                '${stats.totalMessages}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Temps economise'),
              trailing: Text(
                stats.timeSavedFormatted,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Jours d\'utilisation'),
              trailing: Text(
                '${stats.daysUsed}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                stats.motivationMessage,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
          ],
        );
      },
      loading: () => const ListTile(
        leading: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Chargement des statistiques...'),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _StreakSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streakAsync = ref.watch(streakDataProvider);

    return streakAsync.when(
      data: (data) {
        if (data.streak == 0) return const SizedBox.shrink();
        final bool bonusActive = data.streak >= StreakService.streakThreshold && data.bonusGranted;
        final String subtitle = bonusActive
            ? 'Bonus +2 messages actif'
            : data.streak < StreakService.streakThreshold
                ? '${StreakService.streakThreshold - data.streak} jour${(StreakService.streakThreshold - data.streak) > 1 ? 's' : ''} avant le bonus'
                : 'Serie en cours';
        return ListTile(
          leading: Icon(
            Icons.local_fire_department,
            color: bonusActive ? Colors.orange : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          title: Text('Serie de ${data.streak} jour${data.streak > 1 ? 's' : ''}'),
          subtitle: Text(subtitle),
          trailing: bonusActive
              ? Chip(
                  label: const Text('+2'),
                  backgroundColor: Colors.orange.shade100,
                  labelStyle: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold),
                )
              : null,
        );
      },
      loading: () => const ListTile(
        leading: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        title: Text('Chargement du streak...'),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _DailyQuestionToggle extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DailyQuestionToggle> createState() =>
      _DailyQuestionToggleState();
}

class _DailyQuestionToggleState extends ConsumerState<_DailyQuestionToggle> {
  bool? _enabled;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final service = ref.read(dailyQuestionServiceProvider);
    final enabled = await service.isEnabled();
    setState(() => _enabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.notifications_active_outlined),
      title: const Text('Question du jour'),
      subtitle: const Text('Notification a 9h00 avec une question tendance'),
      trailing: _enabled == null
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Switch(
              value: _enabled!,
              onChanged: _loading ? null : _toggle,
            ),
    );
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _loading = true;
      _enabled = value;
    });

    final service = ref.read(dailyQuestionServiceProvider);
    try {
      await service.setEnabled(value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value
                ? 'Notification quotidienne activee'
                : 'Notification quotidienne desactivee'),
          ),
        );
      }
    } catch (e) {
      debugPrint('[DailyQuestion] Toggle error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de la configuration. Reessayez.'),
          ),
        );
        setState(() => _enabled = !value);
      }
    } finally {
      setState(() => _loading = false);
    }
  }
}

// ── Données et confidentialité ──────────────────────────────────────────────

class _DataConsentTile extends StatefulWidget {
  @override
  State<_DataConsentTile> createState() => _DataConsentTileState();
}

class _DataConsentTileState extends State<_DataConsentTile> {
  final _consent = ConsentDataService();
  DataConsentLevel? _level;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final level = await _consent.getConsentLevel();
    if (mounted) setState(() {
      _level = level;
      _loading = false;
    });
  }

  String _levelLabel(DataConsentLevel level) {
    switch (level) {
      case DataConsentLevel.none:
        return 'Desactive';
      case DataConsentLevel.insights:
        return 'Niveau 1 : Insights anonymises (+5 messages/jour)';
      case DataConsentLevel.full:
        return 'Niveau 2 : Full (+10 messages/jour, -20% Pro)';
    }
  }

  String _levelSubtitle(DataConsentLevel level) {
    switch (level) {
      case DataConsentLevel.none:
        return 'Aucune donnee n\'est partagee.';
      case DataConsentLevel.insights:
        return 'Tendances et usages agreges, sans donnee personnelle.';
      case DataConsentLevel.full:
        return 'Personnalisation + insights agreges. Donnees pseudonymisees.';
    }
  }

  Future<void> _openDialog() async {
    final chosen = await showDialog<DataConsentLevel>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Partage de donnees'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: DataConsentLevel.values.map((lvl) {
              return RadioListTile<DataConsentLevel>(
                title: Text(_levelLabel(lvl)),
                subtitle: Text(_levelSubtitle(lvl)),
                value: lvl,
                groupValue: _level,
                onChanged: (v) => Navigator.of(ctx).pop(v),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
          ],
        );
      },
    );

    if (chosen != null && chosen != _level) {
      setState(() => _loading = true);
      await _consent.setConsentLevel(chosen);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Consentement mis a jour : ${_levelLabel(chosen)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.privacy_tip_outlined),
      title: const Text('Partage de donnees anonymisees'),
      subtitle: _loading || _level == null
          ? const Text('Chargement...')
          : Text(_levelSubtitle(_level!)),
      trailing: _loading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right),
      onTap: _loading ? null : _openDialog,
    );
  }
}

class _DataExportTile extends StatefulWidget {
  @override
  State<_DataExportTile> createState() => _DataExportTileState();
}

class _DataExportTileState extends State<_DataExportTile> {
  final _insightService = AnonymizedInsightService(ConsentDataService());
  Map<String, int>? _counters;
  int? _pendingCount;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final counters = await _insightService.getCounters();
    final pending = await _insightService.getPendingInsights();
    if (mounted) setState(() {
      _counters = counters;
      _pendingCount = pending.length;
      _loading = false;
    });
  }

  Future<void> _openDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Exporter mes donnees'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Insights en attente d\'export :'),
                const SizedBox(height: 8),
                Text('${_pendingCount ?? 0} evenements'),
                const SizedBox(height: 16),
                const Text('Compteurs par categorie :'),
                const SizedBox(height: 8),
                if (_counters != null && _counters!.isNotEmpty)
                  ..._counters!.entries.map((e) => Text('${e.key}: ${e.value}'))
                else
                  const Text('Aucun evenement enregistre.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Fermer'),
            ),
            if ((_pendingCount ?? 0) > 0)
              TextButton(
                onPressed: () async {
                  await _insightService.markExported();
                  await _load();
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('File locale videe.')),
                    );
                  }
                },
                child: const Text('Vider la file locale'),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.download_outlined),
      title: const Text('Exporter mes donnees'),
      subtitle: const Text('Voir et exporter les insights anonymises locaux'),
      trailing: _loading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right),
      onTap: _loading ? null : _openDialog,
    );
  }
}

class _DataDeleteTile extends StatelessWidget {
  final _consent = ConsentDataService();
  final _insightService = AnonymizedInsightService(ConsentDataService());

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
      title: Text('Supprimer mes donnees locales', style: TextStyle(color: Theme.of(context).colorScheme.error)),
      subtitle: const Text('Revoque le consentement et efface les insights stockes'),
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirmer la suppression'),
            content: const Text(
                'Cela supprimera toutes les donnees locales (consentement, insights, compteurs). '
                'Les donnees deja exportees et anonymisees ne peuvent pas etre retirees.'
                '\n\nContinuer ?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
              TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Supprimer')),
            ],
          ),
        );

        if (confirm == true) {
          await _consent.revoke();
          await _insightService.markExported();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Donnees locales supprimees. Consentement revoque.')),
            );
          }
        }
      },
    );
  }
}