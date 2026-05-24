import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/data/model_router.dart';

void main() {
  group('ModelRouter', () {
    group('classifyTask with attachmentTypes', () {
      test('image attachments route to vision', () {
        expect(
          ModelRouter.classifyTask('hello', attachmentTypes: ['image']),
          TaskType.vision,
        );
      });

      test('pdf attachment routes to document', () {
        expect(
          ModelRouter.classifyTask('analyse', attachmentTypes: ['pdf']),
          TaskType.document,
        );
      });

      test('docx attachment routes to document', () {
        expect(
          ModelRouter.classifyTask('doc', attachmentTypes: ['document']),
          TaskType.document,
        );
      });

      test('xlsx attachment routes to document', () {
        expect(
          ModelRouter.classifyTask('data', attachmentTypes: ['spreadsheet']),
          TaskType.document,
        );
      });

      test('pptx attachment routes to document', () {
        expect(
          ModelRouter.classifyTask('slides', attachmentTypes: ['presentation']),
          TaskType.document,
        );
      });

      test('txt attachment routes to longFile', () {
        expect(
          ModelRouter.classifyTask('notes', attachmentTypes: ['text']),
          TaskType.longFile,
        );
      });

      test('mixed image + pdf prefers vision', () {
        expect(
          ModelRouter.classifyTask('mixed', attachmentTypes: ['pdf', 'image']),
          TaskType.vision,
        );
      });

      test('multiple text files route to longFile', () {
        expect(
          ModelRouter.classifyTask('files', attachmentTypes: ['text', 'text']),
          TaskType.longFile,
        );
      });

      test('empty attachmentTypes falls back to text classification', () {
        expect(
          ModelRouter.classifyTask('write a function', attachmentTypes: []),
          TaskType.code,
        );
      });

      test('null attachmentTypes falls back to text classification', () {
        expect(
          ModelRouter.classifyTask('raisonner sur ce sujet', attachmentTypes: null),
          TaskType.reasoning,
        );
      });
    });

    group('resolveModel', () {
      test('returns a model for each task type', () {
        for (final task in TaskType.values) {
          final entry = ModelRouter.resolveModel(task);
          expect(entry, isNotNull, reason: 'No model resolved for $task');
        }
      });

      test('vocal task resolves to trinity', () {
        final entry = ModelRouter.resolveModel(TaskType.vocal);
        expect(entry?.modelId, equals('arcee/trinity'));
      });

      test('vocalFast task resolves to ring', () {
        final entry = ModelRouter.resolveModel(TaskType.vocalFast);
        expect(entry?.modelId, equals('neversleep/ring-2.6-1t'));
      });

      test('vision task resolves to gemini-flash', () {
        final entry = ModelRouter.resolveModel(TaskType.vision);
        expect(entry?.modelId, equals('google/gemini-flash-1.5'));
      });
    });

    group('RateLimitTracker', () {
      test('isCoolingDown returns false initially', () {
        final tracker = RateLimitTracker();
        expect(tracker.isCoolingDown('test'), isFalse);
      });

      test('setCooldown and isCoolingDown work', () {
        final tracker = RateLimitTracker();
        tracker.setCooldown('test', duration: const Duration(seconds: 2));
        expect(tracker.isCoolingDown('test'), isTrue);
      });

      test('remainingSeconds returns positive during cooldown', () {
        final tracker = RateLimitTracker();
        tracker.setCooldown('test', duration: const Duration(minutes: 5));
        expect(tracker.remainingSeconds('test'), greaterThan(0));
      });
    });

    group('classifyTaskEnhanced', () {
      test('detects document generation prompts', () {
        expect(
          ModelRouter.classifyTaskEnhanced('Genere un document complet sur le climat'),
          TaskType.document,
        );
        expect(
          ModelRouter.classifyTaskEnhanced('Rédige un rapport détaillé'),
          TaskType.document,
        );
      });

      test('detects extraction prompts', () {
        expect(
          ModelRouter.classifyTaskEnhanced('Nettoie et structure le texte extrait suivant'),
          TaskType.document,
        );
      });

      test('detects multi-step actions', () {
        expect(
          ModelRouter.classifyTaskEnhanced('Trouve un vol, réserve un hôtel et planifie un itinéraire'),
          TaskType.document,
        );
      });

      test('detects deep reasoning prompts', () {
        expect(
          ModelRouter.classifyTaskEnhanced('Prouve que la somme des angles est 180°'),
          TaskType.reasoning,
        );
        expect(
          ModelRouter.classifyTaskEnhanced('Démonstration du théorème de Pythagore'),
          TaskType.reasoning,
        );
      });

      test('falls back to general for simple queries', () {
        expect(
          ModelRouter.classifyTaskEnhanced('Bonjour, comment ça va ?'),
          TaskType.general,
        );
      });

      test('preserves attachment-based routing', () {
        expect(
          ModelRouter.classifyTaskEnhanced('hello', attachmentTypes: ['image']),
          TaskType.vision,
        );
        expect(
          ModelRouter.classifyTaskEnhanced('analyse', attachmentTypes: ['pdf']),
          TaskType.document,
        );
      });
    });

    group('resolveParams', () {
      test('reasoning uses thinking=true', () {
        final p = ModelRouter.resolveParams(TaskType.reasoning);
        expect(p.enableThinking, isTrue);
        expect(p.temperature, 0.7);
        expect(p.maxTokens, 4096);
      });

      test('document uses thinking=false', () {
        final p = ModelRouter.resolveParams(TaskType.document);
        expect(p.enableThinking, isFalse);
        expect(p.temperature, 0.7);
        expect(p.maxTokens, 4096);
      });

      test('general uses default params', () {
        final p = ModelRouter.resolveParams(TaskType.general);
        expect(p.enableThinking, isFalse);
        expect(p.temperature, 0.7);
        expect(p.maxTokens, 4096);
      });

      test('vocal uses higher temperature', () {
        final p = ModelRouter.resolveParams(TaskType.vocal);
        expect(p.temperature, 0.95);
        expect(p.maxTokens, 2048);
      });
    });
  });
}
