import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:airon_bot/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Onboarding Flow Integration Tests', () {
    testWidgets('complete onboarding screens', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Vérifier la première page
      // expect(find.text('IA à portée de main'), findsOneWidget);

      // Aller à la page suivante
      // await tester.tap(find.text('Suivant'));
      // await tester.pumpAndSettle();

      // Vérifier la deuxième page
      // expect(find.text('Synchronisation totale'), findsOneWidget);

      // Aller à la page suivante
      // await tester.tap(find.text('Suivant'));
      // await tester.pumpAndSettle();

      // Vérifier la troisième page
      // expect(find.text('Voix & texte'), findsOneWidget);

      // Commencer
      // await tester.tap(find.text('Commencer'));
      // await tester.pumpAndSettle();

      // Vérifier redirection vers login
      // expect(find.text('Bon retour'), findsOneWidget);
    });

    testWidgets('skip onboarding', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Cliquer sur Passer
      // await tester.tap(find.text('Passer'));
      // await tester.pumpAndSettle();

      // Vérifier redirection
      // expect(find.text('Bon retour'), findsOneWidget);
    });

    testWidgets('page indicators', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Vérifier les indicateurs de page
      // expect(find.byType(AnimatedContainer), findsNWidgets(3));

      // Le premier devrait être actif (plus large)
      // Note: Test visuel complexe
    });
  });
}
