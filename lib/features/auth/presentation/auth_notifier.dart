import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/firebase_auth_repository.dart';
import '../data/mock_auth_repository.dart';
import '../../../main.dart' show isDemoMode;

class AuthNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  // Helper pour obtenir le bon repository selon le mode
  dynamic get _repository {
    if (isDemoMode) return mockAuthRepository;
    return ref.read(authRepositoryProvider);
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repository.signInWithEmail(email, password),
    );
  }

  Future<void> registerWithEmail(
      String email, String password, String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repository.registerWithEmail(email, password, name),
    );
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repository.signInWithGoogle(),
    );
  }

  Future<void> signInAnonymously() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repository.signInAnonymously(),
    );
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repository.signOut(),
    );
  }

  Future<void> deleteAccount() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repository.deleteAccount(),
    );
  }
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, void>(AuthNotifier.new);
