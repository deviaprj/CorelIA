import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/platform/platform_service.dart';
import 'core/platform/extension_bridge.dart';
import 'core/platform/extension_providers.dart';
import 'core/providers/app_providers.dart';
import 'features/monetization/ads/ad_service.dart';
import 'features/monetization/ads/consent_service.dart';
import 'features/monetization/subscription/subscription_service.dart';
import 'features/retention/data/streak_service.dart';
import 'features/retention/data/daily_question_service.dart';
import 'features/auth/data/user_profile_sync.dart';
import 'features/settings/data/preferences_sync_service.dart';
import 'firebase_options.dart';
import 'features/auth/data/mock_auth_repository.dart';
import 'features/chat/data/search_cache_service.dart';

// Global flag pour le mode demo local (sans Firebase)
// false par defaut : l'app tente Firebase normalement, fallback DEMO si echec
// Extension Chrome : toujours true (CSP bloque Google Sign-In, Firebase indisponible)
// Forcer true avec : --dart-define=DEMO_MODE=true
bool isDemoMode = const bool.fromEnvironment('DEMO_MODE', defaultValue: false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Capturer les erreurs Flutter et Dart pour le debug
  FlutterError.onError = (details) {
    debugPrint('[Flutter Error] ${details.exceptionAsString()}');
    debugPrint('[Flutter Error Stack] ${details.stack}');
    // Ne pas crasher l'app pour les erreurs de rendu
  };

  // Charger le cache de recherche depuis SharedPreferences
  await searchCache.loadFromPrefs();

  // Charger .env avant toute initialisation
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('[dotenv] .env charge avec succes');
  } catch (e) {
    debugPrint('[dotenv] .env introuvable ou illisible : $e');
  }

  // ── Extension Chrome : mode DEMO obligatoire ──────────────────────────────
  // Manifest V3 CSP bloque les scripts externes (Google Sign-In, Firebase Auth).
  // En extension, on utilise le mode démo avec auth mock et API directe.
  if (PlatformService.isExtension) {
    isDemoMode = true;
    debugPrint('[Extension] Mode DEMO — Firebase bloqué par CSP Manifest V3');
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
          'test@zentic.fr',
          'test1234',
        );
        debugPrint('[DEMO] Connexion compte de test reussie');
      } catch (_) {
        // Le compte n'existe pas encore : le creer
        try {
          await mockAuthRepository.registerWithEmail(
            'test@zentic.fr',
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

  // Extension bridge sera initialisé via extensionBridgeProvider dans ProviderScope.
  // Ne pas créer d'instance jetable ici — le provider gère le singleton.

  // RevenueCat (mobile uniquement)
  if (PlatformService.isMobile && !isDemoMode) {
    final auth = FirebaseAuth.instance;
    try {
      await SubscriptionService().init(auth.currentUser?.uid ?? '');
    } catch (e) {
      debugPrint('[RevenueCat] Initialisation échouée : $e');
    }
  }

  // Retention : streak check + daily notification init
  try {
    final shouldGrantBonus = await StreakService().checkAndUpdateStreak();
    if (shouldGrantBonus) {
      // Appliquer le bonus de +2 messages directement (evite import circulaire QuotaService)
      const bonusKey = 'quota_bonus_messages';
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(bonusKey) ?? 0;
      await prefs.setInt(bonusKey, current + 2);
      debugPrint('[Retention] Bonus streak +2 messages accorde (total bonus: ${current + 2})');
    }
    final dailyService = DailyQuestionService();
    await dailyService.init();
    final enabled = await dailyService.isEnabled();
    if (enabled) {
      await dailyService.scheduleDailyNotification();
    }
  } catch (e) {
    debugPrint('[Retention] Initialisation echouee : $e');
  }

  // Zone protégée pour capturer les erreurs asynchrones sans crasher l'app
  runZonedGuarded(
    () => runApp(ProviderScope(child: CorelyApp(isDemoMode: isDemoMode))),
    (error, stack) {
      debugPrint('[App Error] $error');
      try {
        debugPrint('[App Error Stack] $stack');
      } catch (e) {
        debugPrint('[App Error Stack] (unprintable: $e)');
      }
    },
  );
}

class CorelyApp extends ConsumerWidget {
  final bool isDemoMode;

  const CorelyApp({super.key, required this.isDemoMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);

    // ── Extension bridge : initialiser via le provider (singleton) ─────────
    if (PlatformService.isExtension) {
      final bridge = ref.read(extensionBridgeProvider);
      if (!bridge.isExtension) {
        debugPrint('[Extension] Bridge non détecté — fallback');
      }
    }

    // ── Sync multi-appareils : écouter les préférences distantes ──────────
    // Ce watch déclenche l'initialisation du stream Firestore et met à jour
    // les SharedPreferences locales quand les préférences changent à distance.
    if (!isDemoMode) {
      ref.listen(syncedPreferencesProvider, (_, next) {
        // Les mises à jour sont gérées dans PreferencesSyncService.mergeWithLocal()
      });
      // Écouter le profil utilisateur pour synchroniser le statut Pro
      ref.listen(userProfileProvider, (_, next) {});
    }

    // Afficher bandeau GDPR au premier lancement.
    // Attendre 2 frames pour que le Navigator soit monté dans l'arbre.
    // Utiliser rootNavigatorKey.currentContext pour obtenir un contexte
    // descendant du Navigator (le context de CorelyApp est au-dessus
    // du MaterialApp et n'a pas de Navigator ancêtre).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final navContext = rootNavigatorKey.currentContext;
          if (navContext != null && navContext.mounted) {
            ConsentBanner.showIfNeeded(navContext, ref);
          }
        } catch (e) {
          debugPrint('[ConsentBanner] Impossible d\'afficher le bandeau : $e');
        }
      });
    });

    return MaterialApp.router(
      title: 'Corely${isDemoMode ? " (DEMO)" : ""}',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
