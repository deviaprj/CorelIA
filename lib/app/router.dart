import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/firebase_providers.dart';
import '../core/providers/app_providers.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/chat/presentation/conversations_screen.dart';
import '../features/projects/presentation/projects_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/monetization/subscription/paywall_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final onboardingAsync = ref.watch(onboardingDoneProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final onboardingDone = onboardingAsync.valueOrNull ?? false;
      final path = state.matchedLocation;

      // Onboarding toujours en premier
      if (!onboardingDone && path != '/onboarding') return '/onboarding';

      // Auth
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
