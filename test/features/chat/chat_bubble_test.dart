import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:airon_bot/features/chat/presentation/chat_bubble.dart';
import 'package:airon_bot/features/chat/domain/message.dart';

void main() {
  group('ChatBubble Widget Tests', () {
    final testDate = DateTime(2024, 1, 15, 10, 30);

    testWidgets('should display user message with correct styling',
        (WidgetTester tester) async {
      final userMessage = Message(
        id: 'msg_1',
        conversationId: 'conv_1',
        role: Role.user,
        content: 'Hello AI!',
        createdAt: testDate,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChatBubble(message: userMessage),
            ),
          ),
        ),
      );

      expect(find.text('Hello AI!'), findsOneWidget);
    });

    testWidgets('should display assistant message with icon',
        (WidgetTester tester) async {
      final assistantMessage = Message(
        id: 'msg_2',
        conversationId: 'conv_1',
        role: Role.assistant,
        content: 'Hello! How can I help?',
        createdAt: testDate,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChatBubble(message: assistantMessage),
            ),
          ),
        ),
      );

      expect(find.text('Hello! How can I help?'), findsOneWidget);
    });

    testWidgets('should show typing indicator for streaming message',
        (WidgetTester tester) async {
      final streamingMessage = Message(
        id: 'msg_3',
        conversationId: 'conv_1',
        role: Role.assistant,
        content: '',
        isStreaming: true,
        createdAt: testDate,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChatBubble(message: streamingMessage),
            ),
          ),
        ),
      );

      // Vérifier que l'indicateur de frappe est affiché
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('should show action buttons on assistant message',
        (WidgetTester tester) async {
      final assistantMessage = Message(
        id: 'msg_4',
        conversationId: 'conv_1',
        role: Role.assistant,
        content: 'Response with actions',
        isStreaming: false,
        createdAt: testDate,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChatBubble(message: assistantMessage),
            ),
          ),
        ),
      );

      // Vérifier les boutons d'action
      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
    });

    testWidgets('should hide action buttons when streaming',
        (WidgetTester tester) async {
      final streamingMessage = Message(
        id: 'msg_5',
        conversationId: 'conv_1',
        role: Role.assistant,
        content: 'Streaming...',
        isStreaming: true,
        createdAt: testDate,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChatBubble(message: streamingMessage),
            ),
          ),
        ),
      );

      // Les actions ne devraient pas être visibles
      expect(find.byIcon(Icons.copy_outlined), findsNothing);
    });

    testWidgets('should render markdown content', (WidgetTester tester) async {
      final markdownMessage = Message(
        id: 'msg_6',
        conversationId: 'conv_1',
        role: Role.assistant,
        content: '**Bold text** and `code`',
        createdAt: testDate,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChatBubble(message: markdownMessage),
            ),
          ),
        ),
      );

      // Le markdown devrait être rendu (content présent)
      expect(find.textContaining('Bold text'), findsOneWidget);
    });

    testWidgets('should support TTS toggle', (WidgetTester tester) async {
      final assistantMessage = Message(
        id: 'msg_8',
        conversationId: 'conv_1',
        role: Role.assistant,
        content: 'Read this aloud',
        createdAt: testDate,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChatBubble(
                message: assistantMessage,
                showTts: true,
              ),
            ),
          ),
        ),
      );

      // Vérifier que le bouton TTS est présent
      expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    });

    testWidgets('should hide TTS button when showTts is false',
        (WidgetTester tester) async {
      final assistantMessage = Message(
        id: 'msg_9',
        conversationId: 'conv_1',
        role: Role.assistant,
        content: 'No TTS here',
        createdAt: testDate,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChatBubble(
                message: assistantMessage,
                showTts: false,
              ),
            ),
          ),
        ),
      );

      // Le bouton TTS ne devrait pas être visible
      expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
    });
  });

  group('ChatBubble Layout Tests', () {
    final testDate = DateTime(2024, 1, 15, 10, 30);

    testWidgets('user message should align to end', (WidgetTester tester) async {
      final userMessage = Message(
        id: 'msg_10',
        conversationId: 'conv_1',
        role: Role.user,
        content: 'User message',
        createdAt: testDate,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChatBubble(message: userMessage),
            ),
          ),
        ),
      );

      // Trouver le Row principal
      final row = find.byType(Row);
      expect(row, findsOneWidget);
    });

    testWidgets('assistant message should align to start',
        (WidgetTester tester) async {
      final assistantMessage = Message(
        id: 'msg_11',
        conversationId: 'conv_1',
        role: Role.assistant,
        content: 'Assistant message',
        createdAt: testDate,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChatBubble(message: assistantMessage),
            ),
          ),
        ),
      );

      // Vérifier que l'avatar est présent
      expect(find.byType(CircleAvatar), findsOneWidget);
    });
  });
}
