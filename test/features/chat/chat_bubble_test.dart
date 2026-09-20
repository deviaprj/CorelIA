import 'package:corel_ia/core/models/attachment.dart';
import 'package:corel_ia/core/models/message.dart';
import 'package:corel_ia/features/chat/presentation/chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/widget_test_shaders.dart';

void main() {
  Message message({
    Role role = Role.user,
    String content = 'Bonjour',
    List<Attachment> attachments = const [],
    List<String>? sources,
  }) =>
      Message(
        id: 'm1',
        conversationId: 'c1',
        role: role,
        content: content,
        createdAt: DateTime(2026, 9, 20),
        attachments: attachments,
        searchSources: sources,
      );

  Future<void> pumpBubble(WidgetTester tester, Message msg) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ChatBubble(message: msg))),
    );
  }

  testWidgets('warm up ink sparkle shader (env artifact)', (tester) async {
    await warmUpInkSparkleShader(tester);
  });

  testWidgets('affiche le message utilisateur', (tester) async {
    await pumpBubble(tester, message(content: 'Salut CorelIA'));
    expect(find.text('Salut CorelIA'), findsOneWidget);
  });

  testWidgets('affiche une réponse assistant en markdown', (tester) async {
    await pumpBubble(
      tester,
      message(role: Role.assistant, content: 'Voici **ma** réponse.'),
    );
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.textContaining('réponse'), findsOneWidget);
  });

  testWidgets('affiche les sources de recherche', (tester) async {
    await pumpBubble(
      tester,
      message(
        role: Role.assistant,
        content: 'Réponse sourcée.',
        sources: const ['Exemple|https://example.com'],
      ),
    );
    expect(find.byType(ActionChip), findsOneWidget);
    expect(find.textContaining('Exemple'), findsOneWidget);
  });

  testWidgets('affiche une pièce jointe image', (tester) async {
    await pumpBubble(
      tester,
      message(
        content: 'Regarde cette image',
        attachments: const [
          Attachment(
            type: AttachmentType.image,
            name: 'photo.jpg',
            mimeType: 'image/jpeg',
            sizeBytes: 4,
            imageBase64: 'AAAA',
          ),
        ],
      ),
    );
    expect(find.byType(Image), findsOneWidget);
  });
}
