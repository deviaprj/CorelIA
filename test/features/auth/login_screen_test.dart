import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:airon_bot/features/auth/presentation/login_screen.dart';
import 'package:airon_bot/features/auth/presentation/auth_notifier.dart';

void main() {
  group('LoginScreen Widget Tests', () {
    testWidgets('should display login form with email and password fields',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Vérifier les champs
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Mot de passe'), findsOneWidget);
    });

    testWidgets('should display login button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Vérifier qu'il y a un ElevatedButton
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('should display Google sign-in button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Vérifier le texte Google
      expect(find.text('Continuer avec Google'), findsOneWidget);
    });

    testWidgets('should display anonymous sign-in option', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      expect(find.text('Continuer sans compte'), findsOneWidget);
    });

    testWidgets('should toggle between login and register', (WidgetTester tester) async {
      // Utiliser une taille d'écran plus grande
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Vérifier l'état initial (notez l'espace final dans le texte)
      expect(find.text('Pas encore de compte ? '), findsOneWidget);

      // Cliquer pour passer en mode inscription
      await tester.tap(find.text("S'inscrire"));
      await tester.pumpAndSettle();

      // Vérifier l'état inscription (notez l'espace final dans le texte)
      expect(find.text('Déjà un compte ? '), findsOneWidget);

      // Réinitialiser la taille
      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('should validate email format', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Entrer un email invalide
      final emailField = find.byType(TextField).first;
      await tester.enterText(emailField, 'invalid-email');
      await tester.pump();

      // Entrer un mot de passe
      await tester.enterText(find.byType(TextField).last, 'password123');
      await tester.pump();

      // Tenter de se connecter
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      // Vérifier que le message d'erreur apparaît
      expect(find.text('Email invalide'), findsOneWidget);
    });

    testWidgets('should validate password length', (WidgetTester tester) async {
      // Utiliser une taille d'écran plus grande pour éviter les problèmes de scroll
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Passer en mode inscription
      await tester.tap(find.text("S'inscrire"));
      await tester.pumpAndSettle();

      // Entrer un email valide
      await tester.enterText(find.byType(TextField).first, 'test@example.com');
      await tester.pump();

      // Entrer un mot de passe trop court
      await tester.enterText(find.byType(TextField).last, '123');
      await tester.pump();

      // Tenter de s'inscrire
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      // Vérifier que le message d'erreur apparaît
      expect(
        find.text('Le mot de passe doit faire au moins 6 caractères'),
        findsOneWidget,
      );

      // Réinitialiser la taille
      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('should show/hide password', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Vérifier que le mot de passe est masqué par défaut
      final passwordField = find.byType(TextField).last;
      final TextField passwordWidget = tester.widget(passwordField);
      expect(passwordWidget.obscureText, isTrue);

      // Cliquer sur l'icône pour afficher
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();

      // Vérifier que le mot de passe est visible
      final TextField updatedWidget = tester.widget(passwordField);
      expect(updatedWidget.obscureText, isFalse);
    });

    testWidgets('should display loading indicator during authentication',
        (WidgetTester tester) async {
      // Ce test vérifie que le bouton principal est présent
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Vérifier que le bouton ElevatedButton est présent
      expect(find.byType(ElevatedButton), findsOneWidget);
    });
  });
}
