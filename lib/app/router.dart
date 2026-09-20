import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/firebase_providers.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/verify_email_screen.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/subscription/presentation/subscription_screen.dart';

/// Clé du Navigator racine (accès au contexte depuis les callbacks).
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Routes accessibles sans être connecté.
const _anonymousRoutes = {'/login', '/register'};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(authStateProvider, (_, __) => refresh.value++)
    ..listen(currentUserProvider, (_, __) => refresh.value++)
    ..onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/chat',
    refreshListenable: refresh,
    redirect: (context, state) {
      final user = ref.read(currentUserProvider);
      final path = state.matchedLocation;

      // Non connecté : uniquement les écrans d'authentification.
      if (user == null) {
        return _anonymousRoutes.contains(path) ? null : '/login';
      }

      // Compte e-mail/mot de passe non confirmé : on bloque l'accès tant que
      // le lien reçu par e-mail n'a pas été ouvert (l'historique est déjà
      // rattaché au compte).
      if (user.needsEmailVerification) {
        return path == '/verify-email' ? null : '/verify-email';
      }

      // Connecté et vérifié : les écrans d'authentification n'ont plus lieu
      // d'être.
      if (_anonymousRoutes.contains(path) || path == '/verify-email') {
        return '/chat';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
        path: '/verify-email',
        builder: (_, __) => const VerifyEmailScreen(),
      ),
      GoRoute(path: '/chat', builder: (_, __) => const ChatScreen()),
      GoRoute(
        path: '/subscription',
        builder: (_, __) => const SubscriptionScreen(),
      ),
    ],
  );
});
