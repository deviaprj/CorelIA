import 'package:corel_ia/core/api/ai_client.dart';
import 'package:corel_ia/core/api/cloudflare_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CloudflareWorkerClient', () {
    test('isConfigured reflète la présence de l\'URL du Worker', () {
      expect(
        const CloudflareWorkerClient(chatUrl: '', apiKey: '').isConfigured,
        isFalse,
      );
      expect(
        const CloudflareWorkerClient(
          chatUrl: 'https://api.zentic.fr/chat',
          apiKey: 'cle',
        ).isConfigured,
        isTrue,
      );
    });

    test('lève une erreur explicite quand le Worker n\'est pas configuré', () {
      const client = CloudflareWorkerClient(chatUrl: '', apiKey: '');
      expectLater(
        client.streamChat(messages: const []),
        emitsError(isA<AiException>()),
      );
    });

    test('formatAiError conserve le message Worker', () {
      const error = AiException('Worker Cloudflare non configuré');
      expect(formatAiError(error), contains('Worker'));
    });
  });
}
