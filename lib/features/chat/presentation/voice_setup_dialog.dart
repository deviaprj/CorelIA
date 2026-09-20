import 'package:flutter/material.dart';

import '../data/voice_setup.dart';

/// Action choisie dans la boîte de dialogue d'amélioration de la voix.
enum _VoiceSetupAction { install, settings, later }

/// Propose d'installer une meilleure voix lorsque celle-ci est incomplète.
///
/// L'aide n'est plus reproposée automatiquement ensuite : elle reste
/// accessible via le menu « Améliorer la voix ».
Future<void> showVoiceSetupDialog(
  BuildContext context, {
  required TtsReadiness readiness,
}) async {
  if (readiness == TtsReadiness.ready) return;

  final missingEngine = readiness == TtsReadiness.noEngine;

  final action = await showDialog<_VoiceSetupAction>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Améliorer la voix de lecture'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(voiceSetupMessage(readiness)),
          const SizedBox(height: 12),
          const Text(
            '1. Installer « Speech Services by Google »\n'
            '2. Ouvrir les paramètres vocaux et télécharger la voix française\n\n'
            'La lecture fonctionne déjà avec la voix actuelle.',
            style: TextStyle(height: 1.4),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, _VoiceSetupAction.later),
          child: const Text('Plus tard'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, _VoiceSetupAction.settings),
          child: Text(
            missingEngine ? 'Paramètres vocaux' : 'Télécharger la voix',
          ),
        ),
        if (missingEngine)
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _VoiceSetupAction.install),
            child: const Text('Installer'),
          ),
      ],
    ),
  );

  await dismissVoiceHint();

  switch (action) {
    case _VoiceSetupAction.install:
      await openGoogleTtsInstallPage();
    case _VoiceSetupAction.settings:
      await openSystemTtsSettings();
    case _VoiceSetupAction.later:
    case null:
      break;
  }
}

/// Vérifie la voix puis propose l'aide si nécessaire (une seule fois).
///
/// [force] ignore le drapeau « déjà proposé » (entrée de menu dédiée).
Future<void> suggestVoiceSetupIfNeeded(
  BuildContext context, {
  required String language,
  bool force = false,
}) async {
  if (!force && await isVoiceHintDismissed()) return;

  final readiness = await checkTtsReadiness(language);
  if (!context.mounted) return;

  if (readiness == TtsReadiness.ready) {
    if (force) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La voix de lecture est déjà optimale.')),
      );
    }
    return;
  }

  await showVoiceSetupDialog(context, readiness: readiness);
}
