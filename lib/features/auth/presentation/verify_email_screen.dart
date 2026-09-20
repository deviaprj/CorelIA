import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/firebase_providers.dart';
import '../domain/auth_error_text.dart';
import 'auth_notifier.dart';

/// Attente de confirmation de l'adresse e-mail.
///
/// Le compte existe déjà (l'historique est donc rattaché et synchronisé), mais
/// l'accès au chat reste bloqué tant que l'adresse n'est pas confirmée.
class VerifyEmailScreen extends ConsumerWidget {
  const VerifyEmailScreen({super.key});

  Future<void> _checkVerification(BuildContext context, WidgetRef ref) async {
    await ref.read(authNotifierProvider.notifier).refreshVerificationStatus();
    if (!context.mounted) return;

    final stillPending =
        ref.read(currentUserProvider)?.needsEmailVerification ?? false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          stillPending
              ? 'Adresse pas encore confirmée. Ouvre le lien reçu par e-mail.'
              : 'Adresse confirmée, bienvenue !',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final isLoading = ref.watch(authNotifierProvider).isLoading;

    ref.listen(authNotifierProvider, (_, next) {
      final error = next.error;
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.mark_email_unread_outlined,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Confirme ton adresse e-mail',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Un lien de confirmation a été envoyé à '
                    '${user?.email ?? 'ton adresse'}. Ouvre-le, puis reviens '
                    'ici : ton compte et ton historique sont déjà créés.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: isLoading ? null : () => _checkVerification(context, ref),
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('J\'ai confirmé mon adresse'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: isLoading
                        ? null
                        : () => ref
                            .read(authNotifierProvider.notifier)
                            .resendVerificationEmail(),
                    child: const Text('Renvoyer l\'e-mail'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () =>
                            ref.read(authNotifierProvider.notifier).signOut(),
                    child: const Text('Utiliser un autre compte'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
