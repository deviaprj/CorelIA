import 'package:corel_ia/features/chat/presentation/input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/widget_test_shaders.dart';

void main() {
  Future<void> pumpInputBar(
    WidgetTester tester, {
    required ValueChanged<String> onSend,
    bool isLoading = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InputBar(
            onSend: onSend,
            onAttach: () {},
            isLoading: isLoading,
          ),
        ),
      ),
    );
  }

  Rect composerRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('input-composer')));

  Rect fieldRect(WidgetTester tester) => tester.getRect(find.byType(TextField));

  Rect sendRect(WidgetTester tester) =>
      tester.getRect(find.byType(FilledButton));

  testWidgets('warm up ink sparkle shader (env artifact)', (tester) async {
    await warmUpInkSparkleShader(tester);
  });

  testWidgets('la zone de saisie occupe toute la largeur', (tester) async {
    await pumpInputBar(tester, onSend: (_) {});

    expect(composerRect(tester).width, greaterThan(700));
    expect(composerRect(tester).left, lessThan(12));
  });

  testWidgets('au repos : pièce jointe, champ et envoi sur une seule ligne',
      (tester) async {
    await pumpInputBar(tester, onSend: (_) {});

    final composer = composerRect(tester);
    final field = fieldRect(tester);
    final send = sendRect(tester);

    // Le bouton d'envoi chevauche verticalement le champ : même ligne.
    expect(send.top, lessThan(field.bottom));
    expect(send.bottom, greaterThan(field.top));

    // Les boutons sont bien à l'intérieur du bloc.
    expect(send.right, lessThanOrEqualTo(composer.right));
    expect(send.left, greaterThanOrEqualTo(composer.left));
    expect(
      tester.getRect(find.byIcon(Icons.attach_file)).left,
      greaterThanOrEqualTo(composer.left),
    );
  });

  testWidgets('au focus : le bloc gagne une ligne, les boutons passent en bas',
      (tester) async {
    await pumpInputBar(tester, onSend: (_) {});
    final collapsedHeight = composerRect(tester).height;

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    final composer = composerRect(tester);
    final field = fieldRect(tester);
    final send = sendRect(tester);

    expect(composer.height, greaterThan(collapsedHeight));
    // Le curseur (le champ) est sur la ligne du haut, les boutons en dessous.
    expect(field.top, lessThan(send.top));
    expect(send.top, greaterThanOrEqualTo(field.bottom - 1));
    // Le bouton de pièce jointe reste à gauche, sur la ligne du bas.
    final attach = tester.getRect(find.byIcon(Icons.attach_file));
    expect((attach.center.dy - send.center.dy).abs(), lessThan(4));
    expect(attach.left, lessThan(send.left));
  });

  testWidgets('le texte est conservé lors du passage à deux lignes',
      (tester) async {
    await pumpInputBar(tester, onSend: (_) {});

    await tester.enterText(find.byType(TextField), 'Bonjour');
    await tester.pump();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text('Bonjour'), findsOneWidget);
  });

  testWidgets('envoie le texte saisi', (tester) async {
    String? sent;
    await pumpInputBar(tester, onSend: (text) => sent = text);

    await tester.enterText(find.byType(TextField), 'Bonjour CorelIA');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(sent, 'Bonjour CorelIA');
    expect(find.text('Bonjour CorelIA'), findsNothing);
  });

  testWidgets('n\'envoie rien quand le champ est vide', (tester) async {
    var count = 0;
    await pumpInputBar(tester, onSend: (_) => count++);

    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();

    expect(count, 0);
  });

  testWidgets('désactive l\'envoi pendant le chargement', (tester) async {
    var count = 0;
    await pumpInputBar(tester, onSend: (_) => count++, isLoading: true);

    await tester.enterText(find.byType(TextField), 'Bonjour');
    await tester.pump();
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();

    expect(count, 0);
  });
}
