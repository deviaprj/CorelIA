import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'ad_service.dart';
import 'ad_reward_tracker.dart';
import '../../chat/data/search_quota_service.dart';
import '../../chat/data/voice_quota_service.dart';
import '../../chat/data/file_quota_service.dart';
import '../../monetization/credits/credit_service.dart';

/// Provider global pour AdRewardTracker.
final adRewardTrackerProvider = Provider<AdRewardTracker>((ref) => AdRewardTracker());

/// Type de quota epuise — determine le bonus et le message.
enum QuotaType {
  requests,
  searches,
  files,
  voice,
}

/// Donnees de bonus par type de quota.
class _QuotaBonus {
  final int amount;
  final String label;
  final String description;
  const _QuotaBonus(this.amount, this.label, this.description);
}

const _bonuses = {
  QuotaType.requests: _QuotaBonus(5, '+5 requetes', '5 demandes supplementaires'),
  QuotaType.searches: _QuotaBonus(2, '+2 recherches', '2 recherches web supplementaires'),
  QuotaType.files: _QuotaBonus(1, '+1 fichier', '1 envoi de fichier supplementaire'),
  QuotaType.voice: _QuotaBonus(5, '+5 vocaux', '5 interactions vocales supplementaires'),
};

/// Dialog affiche quand un quota est epuise.
/// Propose de regarder une ou plusieurs publicites recompensees
/// selon l'algorithme de frequence optimal (AdRewardTracker),
/// ou de passer en Pro.
class QuotaExceededDialog extends ConsumerStatefulWidget {
  const QuotaExceededDialog({
    super.key,
    required this.quotaType,
    this.onBonusGranted,
  });

  final QuotaType quotaType;
  final VoidCallback? onBonusGranted;

  @override
  ConsumerState<QuotaExceededDialog> createState() => _QuotaExceededDialogState();
}

class _QuotaExceededDialogState extends ConsumerState<QuotaExceededDialog> {
  bool _isLoading = false;
  bool _adFailed = false;
  String? _statusMessage;
  int _videosCompleted = 0;
  int _videosRequired = 1;

  @override
  void initState() {
    super.initState();
    _initTracker();
  }

  Future<void> _initTracker() async {
    final tracker = ref.read(adRewardTrackerProvider);
    final required = await tracker.getRequiredVideosForNextBonus();
    setState(() => _videosRequired = required);
  }

  @override
  Widget build(BuildContext context) {
    final bonus = _bonuses[widget.quotaType]!;
    final colorScheme = Theme.of(context).colorScheme;
    final tracker = ref.read(adRewardTrackerProvider);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colorScheme.error),
          const SizedBox(width: 8),
          const Text('Quota atteint'),
        ],
      ),
      content: FutureBuilder<int>(
        future: tracker.getRequiredVideosForNextBonus(),
        builder: (context, snap) {
          final required = snap.data ?? _videosRequired;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Votre quota journalier est epuise.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.play_circle_fill,
                        color: colorScheme.primary, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bonus.label,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(color: colorScheme.onPrimaryContainer),
                          ),
                          Text(
                            required == 1
                                ? 'Regardez une courte video pour obtenir ${bonus.description}'
                                : 'Regardez $required videos courtes pour obtenir ${bonus.description}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                ),
                          ),
                          if (_videosRequired > 1 && _videosCompleted > 0) ...[
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: _videosCompleted / _videosRequired,
                              backgroundColor: colorScheme.surface,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Video $_videosCompleted / $_videosRequired',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _statusMessage!,
                  style: TextStyle(
                    color: _adFailed ? colorScheme.error : colorScheme.primary,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_adFailed) ...[
                const SizedBox(height: 8),
                Text(
                  'La publicite n\'a pas pu etre chargee. Reessayez plus tard.',
                  style: TextStyle(color: colorScheme.error, fontSize: 12),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else ...[
          FilledButton.icon(
            onPressed: _videosCompleted >= _videosRequired ? null : _watchNextVideo,
            icon: Icon(
              _videosCompleted >= _videosRequired
                  ? Icons.check_circle
                  : Icons.play_circle_outline,
              size: 18,
            ),
            label: Text(_buttonLabel()),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
            ),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
              GoRouter.of(context).push('/paywall');
            },
            child: const Text('Passer Pro'),
          ),
        ],
      ],
    );
  }

  String _buttonLabel() {
    if (_videosCompleted >= _videosRequired) return 'Bonus accorde !';
    if (_videosRequired == 1) return 'Regarder la video';
    return 'Regarder la video ${_videosCompleted + 1} / $_videosRequired';
  }

  Future<void> _watchNextVideo() async {
    final tracker = ref.read(adRewardTrackerProvider);

    setState(() {
      _isLoading = true;
      _adFailed = false;
      _statusMessage = 'Chargement de la video...';
    });

    // Anti-spam : verifier le delai depuis la derniere video
    final canWatch = await tracker.canWatchVideo();
    if (!canWatch) {
      final remaining = await tracker.getSecondsUntilNextVideo();
      setState(() {
        _isLoading = false;
        _statusMessage = 'Attendez $remaining seconde${remaining > 1 ? 's' : ''} entre chaque video.';
      });
      return;
    }

    final earned = await AdService.showRewarded(
      loadAd: AdService.loadRewarded,
      onEarned: (_) {
        debugPrint('[QuotaDialog] Video visionnee avec succes.');
      },
      onError: (msg) {
        debugPrint('[QuotaDialog] Ad error: $msg');
      },
    );

    if (!mounted) return;

    if (!earned) {
      setState(() {
        _isLoading = false;
        _adFailed = true;
        _statusMessage = null;
      });
      return;
    }

    // Enregistrer la video comme visionnee
    await tracker.recordVideoWatched();
    final newCompleted = _videosCompleted + 1;

    if (!mounted) return;

    if (newCompleted >= _videosRequired) {
      // Toutes les videos requises ont ete visionnees : accorder le bonus
      _grantBonus();
    } else {
      // Encore des videos a regarder
      final remaining = await tracker.getRequiredVideosForNextBonus();
      setState(() {
        _isLoading = false;
        _videosCompleted = newCompleted;
        _videosRequired = remaining;
        _statusMessage = 'Video $newCompleted visionnee ! Encore ${remaining - newCompleted}.';
      });
    }
  }

  void _grantBonus() {
    widget.onBonusGranted?.call();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _videosCompleted = _videosRequired;
        _statusMessage = 'Bonus accorde ! Vous pouvez continuer.';
      });
      // Fermer le dialog apres un court delai pour que l'utilisateur voie le message
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) Navigator.of(context).pop(true);
      });
    }
  }
}

/// Affiche le dialog de quota depasse et retourne true si un bonus a ete accorde.
Future<bool> showQuotaExceededDialog(
  BuildContext context, {
  required QuotaType quotaType,
  VoidCallback? onBonusGranted,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => QuotaExceededDialog(
      quotaType: quotaType,
      onBonusGranted: onBonusGranted,
    ),
  ).then((value) => value ?? false);
}
