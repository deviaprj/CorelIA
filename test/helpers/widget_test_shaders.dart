// Workaround pour `flutter test` (Flutter 3.41.9 stable, linux-x64) :
// le binding de test ne bundle pas le shader framework compilé
// `shaders/ink_sparkle.frag` dans son asset store natif.
// `ui.FragmentProgram.fromAsset` (appelé par
// `_InkSparkleFactory.initializeShader()` dans ink_sparkle.dart) lève alors
// `Exception: Asset 'shaders/ink_sparkle.frag' not found`. Comme ce
// `.then(...)` n'a pas de `.catchError`, l'erreur async non gérée fait échouer
// le test.
//
// `_initCalled` (ink_sparkle.dart:454) garde le tout à un seul appel par
// process : le PREMIER test qui tappe un `InkWell` déclenche l'erreur et
// échoue ; les taps suivants du même process ne re-déclenchent plus (le
// drapeau reste à true).
//
// Ce n'est PAS un bug applicatif — la prod embarque le shader via le build.
// C'est un artifact d'environnement de test.
//
// `warmUpInkSparkleShader(tester)` déclenche une fois cet appel dans une zone
// `runZonedGuarded` qui avale l'erreur, ce qui passe `_initCalled` à true
// sans faire échouer le test. À appeler comme PREMIER `testWidgets` de chaque
// fichier de test widget qui tappe un `InkWell` (boutons Material,
// IconButtons, ListTiles, etc.) :
//
//   testWidgets('warm up ink sparkle shader (env artifact)', (tester) async {
//     await warmUpInkSparkleShader(tester);
//   });
//
// NB : chaque fichier de test s'exécute dans son propre isolate Dart → le
// drapeau `_initCalled` est propre à chaque fichier → un warm-up par fichier.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Déclenche une fois le chargement du shader ink_sparkle dans une zone
/// guarded qui avale l'erreur d'environnement, pour que les tests suivants
/// (qui tappe un InkWell) ne échouent pas sur l'asset shader absent du
/// binding de test.
Future<void> warmUpInkSparkleShader(WidgetTester tester) async {
  await runZonedGuarded(
    () async {
      // InkWell HITTABLE (enfant Text dans une SizedBox dimensionnée) — le
      // tap doit atterrir sur l'InkWell pour qu'InkSparkle soit créé →
      // initializeShader appelé → _initCalled passe à true. Un enfant
      // SizedBox() (0×0) n'est pas hittable, le tap rate l'InkWell et le
      // shader n'est jamais déclenché.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 80,
              height: 80,
              child: InkWell(
                onTap: () {},
                child: const Center(child: Text('X')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('X'));
      await tester.pump();
      await tester.pump();
    },
    (Object error, StackTrace stack) {
      // Attendu : « Asset 'shaders/ink_sparkle.frag' not found » — avalé.
    },
  );
}
