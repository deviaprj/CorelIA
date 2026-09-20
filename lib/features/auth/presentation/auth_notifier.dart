import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers/firebase_providers.dart';
import '../data/auth_repository.dart';
import '../data/mock_auth_repository.dart';

/// Authentification avec repli automatique sur le mock si Firebase échoue,
/// afin que les boutons de connexion restent fonctionnels hors ligne.
class AuthNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Exécute [firebaseAction], ou [demoAction] en mode démo / si Firebase échoue.
  Future<void> _run(
    Future<void> Function() firebaseAction,
    Future<void> Function() demoAction,
  ) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (isDemoMode) {
        await demoAction();
      } else {
        try {
          await firebaseAction();
        } catch (e) {
          debugPrint('[AuthNotifier] Firebase indisponible, repli démo : $e');
          isDemoMode = true;
          await demoAction();
        }
      }
      ref.invalidate(authStateProvider);
    });
  }

  Future<void> signInWithEmail(String email, String password) => _run(
        () => ref.read(authRepositoryProvider).signInWithEmail(email, password),
        () => mockAuthRepository.signInWithEmail(email, password),
      );

  Future<void> registerWithEmail(String email, String password, String name) =>
      _run(
        () => ref
            .read(authRepositoryProvider)
            .registerWithEmail(email, password, name),
        () => mockAuthRepository.registerWithEmail(email, password, name),
      );

  Future<void> signInWithGoogle() => _run(
        () => ref.read(authRepositoryProvider).signInWithGoogle(),
        () => mockAuthRepository.signInWithGoogle(),
      );

  Future<void> signInAnonymously() => _run(
        () => ref.read(authRepositoryProvider).signInAnonymously(),
        () => mockAuthRepository.signInAnonymously(),
      );

  Future<void> signOut() => _run(
        () => ref.read(authRepositoryProvider).signOut(),
        () => mockAuthRepository.signOut(),
      );

  Future<void> deleteAccount() => _run(
        () => ref.read(authRepositoryProvider).deleteAccount(),
        () => mockAuthRepository.deleteAccount(),
      );
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, void>(AuthNotifier.new);
