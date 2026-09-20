import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers/firebase_providers.dart';
import '../data/auth_repository.dart';
import '../data/mock_auth_repository.dart';
import '../data/user_profile_sync.dart';

/// Authentification de l'utilisateur.
///
/// Les erreurs remontent telles quelles à l'interface : un mot de passe erroné,
/// un e-mail déjà utilisé ou un réseau coupé ne doivent **jamais** être
/// transformés en session locale factice. C'est précisément ce repli silencieux
/// qui empêchait de rattacher l'historique à un vrai compte.
class AuthNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Exécute l'action distante, ou l'équivalent simulé en mode démo.
  Future<void> _run(
    Future<void> Function(AuthRepository repository) online,
    Future<void> Function() offline,
  ) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (isDemoMode) {
        await offline();
      } else {
        await online(ref.read(authRepositoryProvider));
      }
      ref.invalidate(authStateProvider);
      ref.invalidate(userProfileProvider);
    });
  }

  Future<void> signInWithEmail(String email, String password) => _run(
        (repository) => repository.signInWithEmail(email, password),
        () => mockAuthRepository.signInWithEmail(email, password),
      );

  Future<void> register(RegistrationData data) => _run(
        (repository) => repository.registerWithEmail(data),
        () => mockAuthRepository.registerWithEmail(data),
      );

  Future<void> signInWithGoogle() => _run(
        (repository) => repository.signInWithGoogle(),
        () => mockAuthRepository.signInWithGoogle(),
      );

  Future<void> signInAnonymously() => _run(
        (repository) => repository.signInAnonymously(),
        () => mockAuthRepository.signInAnonymously(),
      );

  /// Renvoie l'e-mail de confirmation de l'adresse.
  Future<void> resendVerificationEmail() => _run(
        (repository) => repository.sendEmailVerification(),
        () => mockAuthRepository.sendEmailVerification(),
      );

  /// Recharge le compte puis rafraîchit l'état d'authentification — à appeler
  /// quand l'utilisateur déclare avoir cliqué sur le lien reçu.
  Future<void> refreshVerificationStatus() async {
    if (isDemoMode) return;
    await ref.read(authRepositoryProvider).reloadCurrentUser();
    ref.invalidate(authStateProvider);
  }

  Future<void> signOut() => _run(
        (repository) => repository.signOut(),
        () => mockAuthRepository.signOut(),
      );

  Future<void> deleteAccount() => _run(
        (repository) => repository.deleteAccount(),
        () => mockAuthRepository.deleteAccount(),
      );
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, void>(AuthNotifier.new);
