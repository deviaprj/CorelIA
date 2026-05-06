import 'package:flutter/material.dart';
import 'ad_service.dart';
import '../../chat/data/search_quota_service.dart';
import '../../chat/data/voice_quota_service.dart';
import '../../chat/data/file_quota_service.dart';
import '../../monetization/credits/credit_service.dart';

/// Type de quota épuisé — détermine le bonus et le message.
enum QuotaType {
  requests,
  searches,
  files,
  voice,
}

/// Données de bonus par type de quota.
class _QuotaBonus {
  final int amount;
  final String label;
  final String description;
  const _QuotaBonus(this.amount, this.label, this.description);
}

const _bonuses = {
  QuotaType.requests: _QuotaBonus(5, '+5 requêtes', '5 demandes supplémentaires'),
  QuotaType.searches: _QuotaBonus(2, '+2 recherches', '2 recherches web supplémentaires'),
  QuotaType.files: _QuotaBonus(1, '+1 fichier', '1 envoi de fichier supplémentaire'),
  QuotaType.voice: _QuotaBonus(5, '+5 vocaux', '5 interactions vocales supplémentaires'),
};

/// Dialog affiché quand un quota est épuisé.
/// Propose de regarder une publicité récompensée pour obtenir un bonus,
/// ou de passer en Pro.
class QuotaExceededDialog extends StatefulWidget {
  const QuotaExceededDialog({
    super.key,
    required this.quotaType,
    this.onBonusGranted,
  });

  final QuotaType quotaType;
  final VoidCallback? onBonusGranted;

  @override
  State<QuotaExceededDialog> createState() => _QuotaExceededDialogState();
}

class _QuotaExceededDialogState extends State<QuotaExceededDialog> {
  bool _isLoading = false;
  bool _adFailed = false;

  @override
  Widget build(BuildContext context) {
    final bonus = _bonuses[widget.quotaType]!;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colorScheme.error),
          const SizedBox(width: 8),
          const Text('Quota atteint'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Votre quota journalier est épuisé.',
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
                        'Regardez une courte vidéo pour obtenir ${bonus.description}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_adFailed) ...[
            const SizedBox(height: 12),
            Text(
              'La publicité n\'a pas pu être chargée. Réessayez plus tard.',
              style: TextStyle(color: colorScheme.error, fontSize: 12),
            ),
          ],
        ],
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
            onPressed: _watchAd,
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: Text('Regarder la vidéo'),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
            ),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/paywall');
            },
            child: const Text('Passer Pro'),
          ),
        ],
      ],
    );
  }

  Future<void> _watchAd() async {
    setState(() {
      _isLoading = true;
      _adFailed = false;
    });

    final earned = await AdService.showRewarded(
      loadAd: AdService.loadRewarded,
      onEarned: (_) {
        _grantBonus();
      },
    );

    if (!mounted) return;

    if (!earned) {
      setState(() {
        _isLoading = false;
        _adFailed = true;
      });
    }
  }

  void _grantBonus() {
    widget.onBonusGranted?.call();
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }
}

/// Affiche le dialog de quota dépassé et retourne true si un bonus a été accordé.
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