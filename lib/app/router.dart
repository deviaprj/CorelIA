import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../core/providers/firebase_providers.dart';
import '../features/auth/data/mock_auth_repository.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/chat/presentation/chat_screen.dart';

/// Clé du Navigator racine (accès au contexte depuis les callbacks).
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/chat',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = _isLoggedIn(ref);
      final path = state.matchedLocation;

      if (!loggedIn && path != '/login') return '/login';
      if (loggedIn && path == '/login') return '/chat';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/chat', builder: (_, __) => const ChatScreen()),
    ],
  );
});

bool _isLoggedIn(Ref ref) {
  if (isDemoMode) return mockAuthRepository.currentUser != null;
  return ref.read(authStateProvider).valueOrNull != null;
}
