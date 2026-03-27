import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/platform/platform_service.dart';
import 'core/providers/app_providers.dart';
import 'features/monetization/ads/ad_service.dart';
import 'features/monetization/subscription/subscription_service.dart';
import 'firebase_options.dart';
import 'features/auth/data/mock_auth_repository.dart';

// Global flag pour le mode demo local (sans Firebase)
bool isDemoMode = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase (non supporté sur Linux desktop — uniquement Android/iOS/Web)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    isDemoMode = false;
  } catch (e) {
    // Sur Linux desktop, Firebase n'est pas disponible → mode DEMO activé
    debugPrint('[Firebase] Non disponible sur cette plateforme : $e');
    debugPrint('[DEMO MODE] Activation du mode de test local sans Firebase');
    isDemoMode = true;
  }

  // Initialiser le mock auth en mode DEMO
  if (isDemoMode) {
    await mockAuthRepository.initialize();
  }

  // AdMob (mobile uniquement)
  if (!PlatformService.isExtension && !isDemoMode) {
    try {
      await AdService.init();
    } catch (e) {
      debugPrint('[AdMob] Non disponible sur cette plateforme : $e');
    }
  }

  // RevenueCat (mobile uniquement)
  if (PlatformService.isMobile && !isDemoMode) {
    final auth = FirebaseAuth.instance;
    try {
      await SubscriptionService().init(auth.currentUser?.uid ?? '');
    } catch (e) {
      debugPrint('[RevenueCat] Initialisation échouée : $e');
    }
  }

  runApp(ProviderScope(child: AironBotApp(isDemoMode: isDemoMode)));
}

class AironBotApp extends ConsumerWidget {
  final bool isDemoMode;

  const AironBotApp({super.key, required this.isDemoMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'AironBot${isDemoMode ? " (DEMO)" : ""}',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
