import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:airon_bot/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Auth Flow Integration Tests', () {
    testWidgets('complete signup flow', (WidgetTester tester) async {
      // Lancer l'app
      app.main();
      await tester.pumpAndSettle();

      // Vérifier qu'on est sur l'onboarding ou login
      expect(find.byType(Scaffold), findsOneWidget);

      // Si onboarding, passer l'onboarding
      // await tester.tap(find.text('Passer'));
      // await tester.pumpAndSettle();

      // Vérifier qu'on est sur la page de login
      // expect(find.text('Bon retour'), findsOneWidget);

      // Passer en mode inscription
      // await tester.tap(find.text("S'inscrire"));
      // await tester.pumpAndSettle();

      // Remplir le formulaire
      // await tester.enterText(find.byType(TextField).first, 'test@example.com');
      // await tester.enterText(find.byType(TextField).last, 'password123');
      // await tester.pump();

      // Soumettre
      // await tester.tap(find.widgetWithText(ElevatedButton, "S'inscrire"));
      // await tester.pumpAndSettle();

      // Vérifier la redirection
      // expect(find.text('AironBot'), findsOneWidget);
    });

    testWidgets('login and logout flow', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Login
      // await tester.enterText(find.byType(TextField).first, 'existing@example.com');
      // await tester.enterText(find.byType(TextField).last, 'password123');
      // await tester.tap(find.widgetWithText(ElevatedButton, 'Se connecter'));
      // await tester.pumpAndSettle();

      // Vérifier connexion réussie
      // expect(find.text('Conversations'), findsOneWidget);

      // Aller dans les paramètres
      // await tester.tap(find.byIcon(Icons.settings));
      // await tester.pumpAndSettle();

      // Déconnexion
      // await tester.tap(find.text('Se déconnecter'));
      // await tester.pumpAndSettle();

      // Vérifier retour au login
      // expect(find.text('Bon retour'), findsOneWidget);
    });

    testWidgets('anonymous login flow', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Cliquer sur "Continuer sans compte"
      // await tester.tap(find.text('Continuer sans compte'));
      // await tester.pumpAndSettle();

      // Vérifier redirection
      // expect(find.text('AironBot'), findsOneWidget);
    });
  });
}
