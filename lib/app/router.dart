import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/firebase_providers.dart';
import '../core/providers/app_providers.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/data/mock_auth_repository.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/chat/presentation/conversations_screen.dart';
import '../features/projects/presentation/projects_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/monetization/subscription/paywall_screen.dart';
import '../../main.dart' show isDemoMode;

/// Clé globale du Navigator pour accéder au contexte depuis les callbacks.
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, __) => notifier.value++);
  ref.listen(onboardingDoneProvider, (_, __) => notifier.value++);
  ref.onDispose(() => notifier.dispose());

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final onboardingAsync = ref.read(onboardingDoneProvider);
      final hasError = authState.hasError;
      // Mode DEMO: utiliser directement le mock auth pour éviter le flash login
      final isLoggedIn = isDemoMode
          ? (mockAuthRepository.currentUser != null)
          : (hasError ? false : (authState.valueOrNull != null));
      final onboardingDone = onboardingAsync.valueOrNull ?? false;
      final path = state.matchedLocation;

      // Onboarding toujours en premier
      if (!onboardingDone && path != '/onboarding') return '/onboarding';

      // Auth - si erreur Firebase, rediriger vers login quand même
      if (!isLoggedIn && path != '/login' && path != '/onboarding') {
        return '/login';
      }
      if (isLoggedIn && path == '/login') return '/chats';

      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/chats', builder: (_, __) => const ConversationsScreen()),
      GoRoute(
        path: '/chat/:id',
        builder: (_, state) => ChatScreen(conversationId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/projects', builder: (_, __) => const ProjectsScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/paywall', builder: (_, __) => const PaywallScreen()),
      // Raccourci racine
      GoRoute(
        path: '/',
        redirect: (_, __) => '/chats',
      ),
    ],
  );
});