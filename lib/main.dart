import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/platform/platform_service.dart';
import 'core/providers/app_providers.dart';
import 'features/monetization/ads/ad_service.dart';
import 'features/monetization/ads/consent_service.dart';
import 'features/monetization/subscription/subscription_service.dart';
import 'firebase_options.dart';
import 'features/auth/data/mock_auth_repository.dart';

// Global flag pour le mode demo local (sans Firebase)
// true par defaut pour le developpement : auth mock + IA reelle (DeepSeek via .env)
// Forcer false avec : --dart-define=DEMO_MODE=false
bool isDemoMode = const bool.fromEnvironment('DEMO_MODE', defaultValue: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Charger .env avant toute initialisation
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('[dotenv] .env charge avec succes');
  } catch (e) {
    debugPrint('[dotenv] .env introuvable ou illisible : $e');
  }

  // ── Firebase : tenter, fallback DEMO si indisponible ────────────────────
  if (!isDemoMode) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('[Firebase] Initialise avec succes');
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app') {
        try {
          // Verifier que Firebase est vraiment fonctionnel
          FirebaseAuth.instance.currentUser;
          debugPrint('[Firebase] Deja initialise, fonctionnel');
        } catch (_) {
          debugPrint('[Firebase] Deja initialise mais dysfonctionnel — fallback DEMO');
          isDemoMode = true;
        }
      } else {
        debugPrint('[Firebase] Indisponible : $e');
        isDemoMode = true;
      }
    } catch (e) {
      debugPrint('[Firebase] Indisponible : $e');
      isDemoMode = true;
    }
  }

  // ── Mode DEMO / fallback : auth mock + compte de test ─────────────────────
  if (isDemoMode) {
    debugPrint('[DEMO MODE] Auth mock active');
    await mockAuthRepository.initialize();
    if (mockAuthRepository.currentUser == null) {
      // Compte de test automatique pour acces immediat au chat
      try {
        await mockAuthRepository.signInWithEmail(
          'test@aironbot.app',
          'test1234',
        );
        debugPrint('[DEMO] Connexion compte de test reussie');
      } catch (_) {
        // Le compte n'existe pas encore : le creer
        try {
          await mockAuthRepository.registerWithEmail(
            'test@aironbot.app',
            'test1234',
            'Utilisateur Test',
          );
          debugPrint('[DEMO] Compte de test cree et connecte');
        } catch (e2) {
          // En dernier recours : anonyme
          await mockAuthRepository.signInAnonymously();
          debugPrint('[DEMO] Connexion anonyme de secours : $e2');
        }
      }
    }
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

    // Afficher bandeau GDPR au premier lancement
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ConsentBanner.showIfNeeded(context, ref);
    });

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
