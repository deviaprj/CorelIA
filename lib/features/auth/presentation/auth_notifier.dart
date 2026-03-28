import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/firebase_auth_repository.dart';
import '../data/mock_auth_repository.dart';
import '../../../main.dart' show isDemoMode;

class AuthNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (isDemoMode) {
        await mockAuthRepository.signInWithEmail(email, password);
      } else {
        await ref.read(authRepositoryProvider).signInWithEmail(email, password);
      }
    });
  }

  Future<void> registerWithEmail(
      String email, String password, String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (isDemoMode) {
        await mockAuthRepository.registerWithEmail(email, password, name);
      } else {
        await ref.read(authRepositoryProvider).registerWithEmail(email, password, name);
      }
    });
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (isDemoMode) {
        await mockAuthRepository.signInWithGoogle();
      } else {
        await ref.read(authRepositoryProvider).signInWithGoogle();
      }
    });
  }

  Future<void> signInAnonymously() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (isDemoMode) {
        await mockAuthRepository.signInAnonymously();
      } else {
        await ref.read(authRepositoryProvider).signInAnonymously();
      }
    });
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (isDemoMode) {
        await mockAuthRepository.signOut();
      } else {
        await ref.read(authRepositoryProvider).signOut();
      }
    });
  }

  Future<void> deleteAccount() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (isDemoMode) {
        await mockAuthRepository.deleteAccount();
      } else {
        await ref.read(authRepositoryProvider).deleteAccount();
      }
    });
  }
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, void>(AuthNotifier.new);
