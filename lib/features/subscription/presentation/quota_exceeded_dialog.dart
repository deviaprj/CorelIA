import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/user_role.dart';

/// Affiche le blocage de quota et incite au passage en Agent IA Full.
///
/// Retourne `true` si l'utilisateur choisit de découvrir l'offre Full.
Future<bool> showQuotaExceededDialog(
  BuildContext context, {
  required UserRole role,
  required int dailyLimit,
  VoidCallback? onUpgrade,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.hourglass_bottom, color: Theme.of(ctx).colorScheme.error),
          const SizedBox(width: 8),
          const Text('Quota atteint'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Vous avez utilisé vos $dailyLimit requêtes journalières "
            'de l\'${role.label}.',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Agent IA Full',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Requêtes illimitées et fonctionnalités avancées.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Plus tard'),
        ),
        if (onUpgrade != null)
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop(true);
              onUpgrade();
            },
            child: const Text('Passer à l\'Agent IA Full'),
          ),
      ],
    ),
  );
  return result ?? false;
}
