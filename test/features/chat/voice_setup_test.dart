import 'package:corel_ia/features/chat/data/voice_setup.dart';
import 'package:corel_ia/features/chat/presentation/voice_setup_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openDialog(WidgetTester tester, TtsReadiness readiness) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showVoiceSetupDialog(ctx, readiness: readiness),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
  }

  group('voiceAvailabilityFrom', () {
    test('interprète un booléen', () {
      expect(voiceAvailabilityFrom(true), isTrue);
      expect(voiceAvailabilityFrom(false), isFalse);
    });

    test('interprète un entier', () {
      expect(voiceAvailabilityFrom(1), isTrue);
      expect(voiceAvailabilityFrom(0), isFalse);
      expect(voiceAvailabilityFrom(2), isFalse);
    });

    test('interprète une chaîne', () {
      expect(voiceAvailabilityFrom('true'), isTrue);
      expect(voiceAvailabilityFrom('FALSE'), isFalse);
    });

    test('renvoie null si indéterminé', () {
      expect(voiceAvailabilityFrom(null), isNull);
      expect(voiceAvailabilityFrom(1.5), isNull);
      expect(voiceAvailabilityFrom('peut-être'), isNull);
    });
  });

  group('voiceSetupMessage', () {
    test('décrit chaque état', () {
      expect(voiceSetupMessage(TtsReadiness.ready), contains('prête'));
      expect(
        voiceSetupMessage(TtsReadiness.noEngine),
        contains('Aucun moteur'),
      );
      expect(
        voiceSetupMessage(TtsReadiness.missingLanguage),
        contains('française'),
      );
    });
  });

  group('cibles d\'installation', () {
    test('propose le Play Store puis le navigateur', () {
      expect(googleTtsInstallUrls, hasLength(2));
      expect(googleTtsInstallUrls.first, startsWith('market://details?id='));
      expect(googleTtsInstallUrls.last, startsWith('https://play.google.com/'));
    });

    test('cible bien Speech Services by Google', () {
      expect(googleTtsPackage, 'com.google.android.tts');
      for (final url in googleTtsInstallUrls) {
        expect(url, contains(googleTtsPackage));
      }
    });

    test('utilise un canal natif dédié aux réglages vocaux', () {
      expect(systemChannel.name, 'com.corelia.corely/system');
    });
  });

  group('showVoiceSetupDialog', () {
    testWidgets('sans moteur : propose l\'installation', (tester) async {
      await openDialog(tester, TtsReadiness.noEngine);

      expect(find.text('Améliorer la voix de lecture'), findsOneWidget);
      expect(find.textContaining('Aucun moteur'), findsOneWidget);
      expect(find.text('Installer'), findsOneWidget);
      expect(find.text('Paramètres vocaux'), findsOneWidget);
    });

    testWidgets('voix manquante : propose le téléchargement, pas l\'installation',
        (tester) async {
      await openDialog(tester, TtsReadiness.missingLanguage);

      expect(
        find.text(voiceSetupMessage(TtsReadiness.missingLanguage)),
        findsOneWidget,
      );
      expect(find.text('Télécharger la voix'), findsOneWidget);
      expect(find.text('Installer'), findsNothing);
    });

    testWidgets('« Plus tard » ferme la boîte et mémorise le choix',
        (tester) async {
      await openDialog(tester, TtsReadiness.noEngine);

      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();

      expect(find.text('Améliorer la voix de lecture'), findsNothing);
      expect(await isVoiceHintDismissed(), isTrue);
    });

    testWidgets('aucune boîte si la voix est prête', (tester) async {
      await openDialog(tester, TtsReadiness.ready);
      expect(find.text('Améliorer la voix de lecture'), findsNothing);
    });
  });
}
