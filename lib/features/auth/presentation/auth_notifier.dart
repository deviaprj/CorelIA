import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/firebase_auth_repository.dart';
import '../data/mock_auth_repository.dart';
import '../../../main.dart' show isDemoMode;

/// Auth notifier avec fallback automatique sur mock auth si Firebase echoue.
/// Garantit que les boutons login/inscription fonctionnent meme sans backend.
class AuthNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (isDemoMode) {
        await mockAuthRepository.signInWithEmail(email, password);
        return;
      }
      try {
        await ref.read(authRepositoryProvider).signInWithEmail(email, password);
      } catch (e) {
        debugPrint('[AuthNotifier] Firebase email echoue, fallback mock : $e');
        await mockAuthRepository.signInWithEmail(email, password);
      }
    });
  }

  Future<void> registerWithEmail(
      String email, String password, String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (isDemoMode) {
        await mockAuthRepository.registerWithEmail(email, password, name);
        return;
      }
      try {
        await ref.read(authRepositoryProvider).registerWithEmail(email, password, name);
      } catch (e) {
        debugPrint('[AuthNotifier] Firebase register echoue, fallback mock : $e');
        await mockAuthRepository.registerWithEmail(email, password, name);
      }
    });
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (isDemoMode) {
        await mockAuthRepository.signInWithGoogle();
        return;
      }
      try {
        await ref.read(authRepositoryProvider).signInWithGoogle();
      } catch (e) {
        debugPrint('[AuthNotifier] Firebase Google echoue, fallback mock : $e');
        await mockAuthRepository.signInWithGoogle();
      }
    });
  }

  Future<void> signInAnonymously() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (isDemoMode) {
        await mockAuthRepository.signInAnonymously();
        return;
      }
      try {
        await ref.read(authRepositoryProvider).signInAnonymously();
      } catch (e) {
        debugPrint('[AuthNotifier] Firebase anonyme echoue, fallback mock : $e');
        await mockAuthRepository.signInAnonymously();
      }
    });
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (isDemoMode) {
        await mockAuthRepository.signOut();
        return;
      }
      try {
        await ref.read(authRepositoryProvider).signOut();
      } catch (e) {
        debugPrint('[AuthNotifier] Firebase signOut echoue, fallback mock : $e');
        await mockAuthRepository.signOut();
      }
    });
  }

  Future<void> deleteAccount() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (isDemoMode) {
        await mockAuthRepository.deleteAccount();
        return;
      }
      try {
        await ref.read(authRepositoryProvider).deleteAccount();
      } catch (e) {
        debugPrint('[AuthNotifier] Firebase delete echoue, fallback mock : $e');
        await mockAuthRepository.deleteAccount();
      }
    });
  }
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, void>(AuthNotifier.new);
