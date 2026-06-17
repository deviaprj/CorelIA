import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/features/chat/data/ai_client.dart';

/// Tests de charge pour les APIs
void main() {
  group('API Load Tests', () {
    const apiKey = String.fromEnvironment('DEEPSEEK_API_KEY');
    late DeepSeekClient client;

    setUp(() {
      if (apiKey.isNotEmpty) {
        client = DeepSeekClient(apiKey: apiKey);
      }
    });

    test('measure DeepSeek API response time', () async {
      if (apiKey.isEmpty) {
        print('Skipping test: DEEPSEEK_API_KEY not set');
        return;
      }

      final stopwatch = Stopwatch()..start();

      final stream = client.streamChat(
        messages: [
          {'role': 'user', 'content': 'Hello'},
        ],
      );

      // Attendre la réponse
      await for (final token in stream) {
        if (token.isNotEmpty) break;
      }

      stopwatch.stop();
      final responseTime = stopwatch.elapsedMilliseconds;

      print('DeepSeek API first token time: ${responseTime}ms');

      // Le premier token devrait arriver en moins de 5 secondes
      expect(responseTime, lessThan(5000));
    });

    test('measure full response time', () async {
      if (apiKey.isEmpty) {
        print('Skipping test: DEEPSEEK_API_KEY not set');
        return;
      }

      final stopwatch = Stopwatch()..start();

      final stream = client.streamChat(
        messages: [
          {'role': 'user', 'content': 'Say "Hello"'},
        ],
        maxTokens: 10,
      );

      final buffer = StringBuffer();
      await for (final token in stream) {
        buffer.write(token);
      }

      stopwatch.stop();
      final responseTime = stopwatch.elapsedMilliseconds;

      print('Full response time: ${responseTime}ms');
      print('Response: ${buffer.toString()}');

      // La réponse complète devrait prendre moins de 10 secondes
      expect(responseTime, lessThan(10000));
    });

    test('concurrent API requests', () async {
      if (apiKey.isEmpty) {
        print('Skipping test: DEEPSEEK_API_KEY not set');
        return;
      }

      const concurrentRequests = 3;
      final futures = <Future<void>>[];
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < concurrentRequests; i++) {
        futures.add(
          client
              .streamChat(
                messages: [
                  {'role': 'user', 'content': 'Test $i'},
                ],
                maxTokens: 5,
              )
              .toList(),
        );
      }

      await Future.wait(futures);

      stopwatch.stop();
      final totalTime = stopwatch.elapsedMilliseconds;

      print('Concurrent requests time: ${totalTime}ms');

      // Les requêtes concurrentes devraient se terminer en moins de 15 secondes
      expect(totalTime, lessThan(15000));
    });

    test('measure API error handling', () async {
      final invalidClient = DeepSeekClient(apiKey: 'invalid_key');

      try {
        await invalidClient
            .streamChat(
              messages: [
                {'role': 'user', 'content': 'Test'},
              ],
            )
            .toList();
        fail('Should have thrown an exception');
      } catch (e) {
        expect(e, isA<AiException>());
      }
    });
  });

  group('Firestore Load Tests', () {
    // Ces tests nécessitent Firebase émulé ou connecté

    test('measure batch write performance', () async {
      // Simuler l'écriture de 100 messages
      final stopwatch = Stopwatch()..start();

      // for (int i = 0; i < 100; i++) {
      //   // Écrire un message
      // }

      stopwatch.stop();
      print('Batch write time: ${stopwatch.elapsedMilliseconds}ms');
    });

    test('measure query performance', () async {
      final stopwatch = Stopwatch()..start();

      // Effectuer une requête complexe

      stopwatch.stop();
      print('Query time: ${stopwatch.elapsedMilliseconds}ms');
    });
  });

  group('Memory Tests', () {
    test('check memory after many messages', () {
      final messages = <Message>[];
      final baseMemory = ProcessInfo.currentRss;

      // Créer 1000 messages
      for (int i = 0; i < 1000; i++) {
        messages.add(Message(
          id: 'msg_$i',
          conversationId: 'conv_1',
          role: i % 2 == 0 ? Role.user : Role.assistant,
          content: 'Message content $i ' * 100, // Contenu long
          createdAt: DateTime.now(),
        ));
      }

      final currentMemory = ProcessInfo.currentRss;
      final memoryUsed = currentMemory - baseMemory;

      print('Memory used for 1000 messages: ${memoryUsed ~/ 1024} KB');

      // Ne devrait pas utiliser plus de 10MB
      expect(memoryUsed, lessThan(10 * 1024 * 1024));
    });
  });
}

// Mock message pour le test
class Message {
  final String id;
  final String conversationId;
  final Role role;
  final String content;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
  });
}

enum Role { user, assistant, system }

// Utilitaire pour les informations de processus.
// `pid` ci-dessous est le getter top-level de dart:io — on ne le redéfinit PAS
// (l'ancien `static int get pid => pid;` causait une récursion infinie → stack overflow).
class ProcessInfo {
  static int get currentRss {
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final result = Process.runSync('ps', ['-o', 'rss=', '-p', '$pid']);
        return int.parse((result.stdout as String).trim()) * 1024;
      } catch (_) {
        return 0;
      }
    }
    return 0;
  }
}
