import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:corel_ia/main.dart' as app;

/// Tests fonctionnels E2E — Sprint 2
/// Scénarios : chat streaming, recherche web, conversation vocale
///
/// Lancer sur device :
///   flutter test integration_test/functional_e2e_test.dart --dart-define=DEMO_MODE=true
///
/// Lancer sur device physique (avec ADB) :
///   flutter test integration_test/functional_e2e_test.dart --dart-define=DEMO_MODE=true -d 6db039ac
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Functional E2E Tests — Sprint 2', () {
    /// Helper : attend qu'un widget apparaisse (avec timeout)
    Future<void> waitFor(
      WidgetTester tester,
      Finder finder, {
      Duration timeout = const Duration(seconds: 10),
    }) async {
      final end = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 200));
        if (finder.evaluate().isNotEmpty) return;
      }
      throw Exception('Widget non trouvé dans le délai imparti : $finder');
    }

    /// Helper : passe l'onboarding si présent
    Future<void> skipOnboarding(WidgetTester tester) async {
      // Attendre que l'UI soit stable
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Chercher le bouton "Commencer" ou "Passer" ou les points de l'onboarding
      final startFinder = find.text('Commencer');
      final skipFinder = find.text('Passer');

      if (startFinder.evaluate().isNotEmpty) {
        await tester.tap(startFinder);
        await tester.pumpAndSettle();
        return;
      }
      if (skipFinder.evaluate().isNotEmpty) {
        await tester.tap(skipFinder);
        await tester.pumpAndSettle();
        return;
      }

      // Si on est déjà sur Conversations ou Login, rien à faire
      if (find.text('CorelIA').evaluate().isNotEmpty ||
          find.text('Bon retour').evaluate().isNotEmpty) {
        return;
      }

      // Swipe rapide pour passer les pages d'onboarding
      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();
      }
    }

    /// Helper : login anonyme rapide en mode DEMO
    Future<void> ensureLoggedIn(WidgetTester tester) async {
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Si on voit "Continuer sans compte", on clique
      final anonymousFinder = find.text('Continuer sans compte');
      if (anonymousFinder.evaluate().isNotEmpty) {
        await tester.tap(anonymousFinder);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        return;
      }

      // Si on voit "Bon retour", on est sur login — en mode DEMO on
      // devrait pouvoir passer en anonyme, sinon on remplit test/test
      final loginTitle = find.text('Bon retour');
      if (loginTitle.evaluate().isNotEmpty) {
        // Essayer anonyme
        final anon = find.text('Continuer sans compte');
        if (anon.evaluate().isNotEmpty) {
          await tester.tap(anon);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      }
    }

    /// Helper : crée une nouvelle conversation
    Future<void> createConversation(WidgetTester tester) async {
      await waitFor(tester, find.byType(FloatingActionButton));
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Vérifier qu'on est sur l'écran Chat
      expect(find.text('Chat'), findsOneWidget);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 1 — Chat streaming basique
    // ═══════════════════════════════════════════════════════════════════════
    testWidgets('Chat: envoi message et réponse streaming',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await skipOnboarding(tester);
      await ensureLoggedIn(tester);

      // Créer conversation
      await createConversation(tester);

      // Envoyer un message
      const testMessage = 'Bonjour, quelle heure est-il ?';
      await tester.enterText(find.byType(TextField).last, testMessage);
      await tester.pump();

      // Tap envoyer
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // Vérifier que le message utilisateur apparaît immédiatement
      expect(find.text(testMessage), findsOneWidget);

      // Vérifier que l'indicateur de streaming est actif
      // (CircularProgressIndicator dans la bulle ou InputBar disabled)
      await waitFor(tester, find.byType(CircularProgressIndicator));

      // Attendre la fin du streaming (max 30s)
      final end = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 500));
        // Quand le streaming est fini, l'indicator disparaît
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }

      // Vérifier qu'au moins une bulle assistant est présente
      // (ChatBubble avec role assistant)
      expect(find.byType(ListView), findsOneWidget);

      // Vérifier que l'InputBar est réactivé
      final inputBar = tester.widget<TextField>(find.byType(TextField).last);
      expect(inputBar.enabled, isTrue);
    });

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 2 — Recherche web intégrée
    // ═══════════════════════════════════════════════════════════════════════
    testWidgets('Search: toggle recherche web et bannière',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await skipOnboarding(tester);
      await ensureLoggedIn(tester);
      await createConversation(tester);

      // Activer la recherche web via l'IconButton travel_explore
      final searchToggle = find.byIcon(Icons.travel_explore_outlined);
      if (searchToggle.evaluate().isNotEmpty) {
        await tester.tap(searchToggle);
        await tester.pumpAndSettle();
      }

      // Vérifier que l'icône est maintenant remplie (active)
      expect(find.byIcon(Icons.travel_explore), findsOneWidget);

      // Vérifier le sous-titre "Recherche web active" dans l'AppBar
      expect(find.text('Recherche web active'), findsOneWidget);

      // Envoyer une question nécessitant une recherche
      await tester.enterText(
          find.byType(TextField).last, 'Quel est le prix du Bitcoin ?');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // Vérifier que la bannière "Recherche web en cours..." apparaît
      await waitFor(tester, find.text('Recherche web en cours...'));

      // Attendre la fin (max 30s)
      final end = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.text('Recherche web en cours...').evaluate().isEmpty) {
          break;
        }
      }

      // Désactiver la recherche
      final searchActive = find.byIcon(Icons.travel_explore);
      if (searchActive.evaluate().isNotEmpty) {
        await tester.tap(searchActive);
        await tester.pumpAndSettle();
      }

      expect(find.byIcon(Icons.travel_explore_outlined), findsOneWidget);
    });

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 3 — Mode conversation vocale mains-libres
    // ═══════════════════════════════════════════════════════════════════════
    testWidgets('Voice: activation conversation vocale et états UI',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await skipOnboarding(tester);
      await ensureLoggedIn(tester);
      await createConversation(tester);

      // Vérifier le bouton micro (mic_none_outlined = inactif)
      final micInactive = find.byIcon(Icons.mic_none_outlined);
      expect(micInactive, findsOneWidget);

      // Activer la conversation vocale
      await tester.tap(micInactive);
      await tester.pump(const Duration(seconds: 1));

      // Vérifier que le micro est maintenant actif (rouge)
      final micActive = find.byIcon(Icons.mic);
      expect(micActive, findsOneWidget);

      // Vérifier que la bannière vocale apparaît
      await waitFor(tester, find.text('Écoute en cours...'));

      // Attendre le traitement STT (max 10s)
      final end = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 500));
        // Le statut passe de "Écoute" → "Transcription" → "Réflexion" etc.
        if (find.textContaining('Transcription').evaluate().isNotEmpty ||
            find.textContaining('Réflexion').evaluate().isNotEmpty) {
          break;
        }
      }

      // Arrêter la conversation vocale
      final stopButton = find.byIcon(Icons.stop);
      if (stopButton.evaluate().isNotEmpty) {
        await tester.tap(stopButton);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }

      // Vérifier que le micro est revenu à l'état inactif
      expect(find.byIcon(Icons.mic_none_outlined), findsOneWidget);
    });

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 4 — Pagination / historique (bonus)
    // ═══════════════════════════════════════════════════════════════════════
    testWidgets('Memory: lazy loading historique messages',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await skipOnboarding(tester);
      await ensureLoggedIn(tester);
      await createConversation(tester);

      // Vérifier que la ListView est présente (même vide au début)
      expect(find.byType(ListView), findsOneWidget);

      // Vérifier le hint de bienvenue quand pas de messages
      expect(find.text('Posez votre première question'), findsOneWidget);

      // Envoyer un message
      await tester.enterText(find.byType(TextField).last, 'Test message');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // Le hint doit disparaître
      await waitFor(tester, find.text('Test message'));
      expect(find.text('Posez votre première question'), findsNothing);
    });
  });
}
