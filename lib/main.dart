import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'features/auth/data/mock_auth_repository.dart';
import 'firebase_options.dart';

Future<void> main() async {
  // Toute l'initialisation vit dans la même zone que `runApp` : sinon Flutter
  // signale un « Zone mismatch » et la gestion des erreurs devient imprévisible.
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        debugPrint('[Flutter Error] ${details.exceptionAsString()}');
      };

      // `.env` est facultatif : en release les clés arrivent via --dart-define.
      try {
        await dotenv.load(fileName: '.env');
      } catch (_) {
        debugPrint('[dotenv] .env non embarqué (attendu en release)');
      }

      // Firebase porte les comptes et l'historique en ligne. S'il manque dans ce
      // build, on continue en local — mais l'interface doit l'annoncer, sinon
      // l'utilisateur croit s'être inscrit alors que rien n'est enregistré.
      if (!isDemoMode) {
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        } catch (e) {
          debugPrint('[Firebase] Indisponible : $e');
          firebaseUnavailable = true;
          isDemoMode = true;
        }
      }

      // Mode démo : connexion automatique pour un accès immédiat au chat.
      if (isDemoMode) {
        await mockAuthRepository.initialize();
        if (mockAuthRepository.currentUser == null) {
          try {
            await mockAuthRepository.signInWithEmail(
              'demo@corelia.app',
              'demo1234',
            );
          } catch (_) {
            await mockAuthRepository.signInAnonymously();
          }
        }
      }

      runApp(const ProviderScope(child: CoreliaApp()));
    },
    (error, stack) => debugPrint('[App Error] $error\n$stack'),
  );
}
