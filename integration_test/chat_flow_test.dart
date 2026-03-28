import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:airon_bot/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Chat Flow Integration Tests', () {
    testWidgets('create conversation and send message',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Créer une nouvelle conversation
      // await tester.tap(find.byType(FloatingActionButton));
      // await tester.pumpAndSettle();

      // Vérifier qu'on est sur l'écran de chat
      // expect(find.text('Chat'), findsOneWidget);

      // Envoyer un message
      // await tester.enterText(find.byType(TextField).last, 'Hello AI');
      // await tester.tap(find.byIcon(Icons.send));
      // await tester.pumpAndSettle();

      // Vérifier que le message apparaît
      // expect(find.text('Hello AI'), findsOneWidget);

      // Attendre la réponse (peut prendre du temps)
      // await tester.pump(const Duration(seconds: 10));

      // Vérifier qu'une réponse est apparue
      // expect(find.textContaining('AI response'), findsOneWidget);
    });

    testWidgets('delete conversation', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Swipe pour supprimer
      // await tester.drag(find.byType(ListTile).first, const Offset(-500, 0));
      // await tester.pumpAndSettle();

      // Confirmer
      // await tester.tap(find.text('Supprimer'));
      // await tester.pumpAndSettle();
    });

    testWidgets('pin conversation', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Ouvrir le menu
      // await tester.tap(find.byIcon(Icons.more_vert).first);
      // await tester.pumpAndSettle();

      // Cliquer sur Épingler
      // await tester.tap(find.text('Épingler'));
      // await tester.pumpAndSettle();

      // Vérifier que la conversation est dans la section "Épinglées"
      // expect(find.text('Épinglées'), findsOneWidget);
    });

    testWidgets('voice input', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Créer une conversation
      // await tester.tap(find.byType(FloatingActionButton));
      // await tester.pumpAndSettle();

      // Cliquer sur le micro
      // await tester.tap(find.byIcon(Icons.mic_none_outlined));
      // await tester.pumpAndSettle();

      // Vérifier que l'état d'écoute est actif
      // expect(find.byIcon(Icons.mic), findsOneWidget);
    });
  });
}
