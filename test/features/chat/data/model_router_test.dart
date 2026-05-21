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
          ModelRouter.classifyTask('explain why', attachmentTypes: null),
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
  });
}
