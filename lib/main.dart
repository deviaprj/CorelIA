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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase (non supporté sur Linux desktop — uniquement Android/iOS/Web)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Sur Linux desktop, Firebase n'est pas disponible → on continue sans
    debugPrint('[Firebase] Non disponible sur cette plateforme : $e');
  }

  // AdMob (mobile uniquement)
  if (!PlatformService.isExtension) {
    try {
      await AdService.init();
    } catch (e) {
      debugPrint('[AdMob] Non disponible sur cette plateforme : $e');
    }
  }

  // RevenueCat (mobile uniquement)
  if (PlatformService.isMobile) {
    final auth = FirebaseAuth.instance;
    await SubscriptionService().init(auth.currentUser?.uid ?? '');
  }

  runApp(const ProviderScope(child: AironBotApp()));
}

class AironBotApp extends ConsumerWidget {
  const AironBotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'AironBot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
