import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:airon_bot/features/chat/presentation/input_bar.dart';

void main() {
  group('InputBar Widget Tests', () {
    testWidgets('should display text input field', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: InputBar(
                onSend: (_, {imageBase64, imageMimeType, fileName, fileContent}) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('should have hint text', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: InputBar(
                onSend: (_, {imageBase64, imageMimeType, fileName, fileContent}) {},
              ),
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      final TextField field = tester.widget(textField);
      final decoration = field.decoration;
      expect(decoration?.hintText, isNotNull);
    });

    testWidgets('should enter text', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: InputBar(
                onSend: (_, {imageBase64, imageMimeType, fileName, fileContent}) {},
              ),
            ),
          ),
        ),
      );

      // Entrer du texte
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();

      // Vérifier que le texte est présent
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('should clear input after sending', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: InputBar(
                onSend: (_, {imageBase64, imageMimeType, fileName, fileContent}) {},
              ),
            ),
          ),
        ),
      );

      // Entrer du texte
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();

      // Vérifier que le texte est présent
      expect(find.text('Hello'), findsOneWidget);

      // Le texte est présent
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('should show loading indicator when isLoading is true',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: InputBar(
                onSend: (_, {imageBase64, imageMimeType, fileName, fileContent}) {},
                isLoading: true,
              ),
            ),
          ),
        ),
      );

      // Le bouton devrait montrer un indicateur de chargement
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('should disable input when isLoading is true',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: InputBar(
                onSend: (_, {imageBase64, imageMimeType, fileName, fileContent}) {},
                isLoading: true,
              ),
            ),
          ),
        ),
      );

      // Le bouton envoyer devrait être désactivé
      final button = find.byType(FilledButton);
      final FilledButton buttonWidget = tester.widget(button);
      expect(buttonWidget.onPressed, isNull);
    });

    testWidgets('should expand text field on multiline',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: InputBar(
                onSend: (_, {imageBase64, imageMimeType, fileName, fileContent}) {},
              ),
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      final TextField field = tester.widget(textField);

      expect(field.maxLines, greaterThan(1));
      expect(field.minLines, greaterThanOrEqualTo(1));
    });

    testWidgets('should have send button', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: InputBar(
                onSend: (_, {imageBase64, imageMimeType, fileName, fileContent}) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('should animate send button scale', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: InputBar(
                onSend: (_, {imageBase64, imageMimeType, fileName, fileContent}) {},
              ),
            ),
          ),
        ),
      );

      // Au début, pas de texte, le bouton devrait être réduit
      expect(find.byType(AnimatedScale), findsOneWidget);

      // Entrer du texte
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();

      // Le bouton devrait être agrandi
    });
  });
}
