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

  testWidgets('warm up ink sparkle shader (env artifact)', (tester) async {
    await warmUpInkSparkleShader(tester);
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

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(count, 0);
  });

  testWidgets('désactive l\'envoi pendant le chargement', (tester) async {
    var count = 0;
    await pumpInputBar(tester, onSend: (_) => count++, isLoading: true);

    await tester.enterText(find.byType(TextField), 'Bonjour');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(count, 0);
  });

  testWidgets('expose un bouton de recherche Internet', (tester) async {
    var toggled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InputBar(
            onSend: (_) {},
            onAttach: () {},
            searchEnabled: false,
            onToggleSearch: () => toggled = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.public_off));
    await tester.pump();

    expect(toggled, isTrue);
  });
}
