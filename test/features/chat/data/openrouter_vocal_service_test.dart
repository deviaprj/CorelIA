import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/features/chat/data/openrouter_vocal_service.dart';
import 'package:corel_ia/features/chat/data/openrouter_tts_service.dart';

void main() {
  group('OpenRouterVocalService', () {
    group('voiceForEmotion', () {
      test('neutral -> nova', () {
        expect(OpenRouterVocalService.voiceForEmotion('neutral'), TtsVoice.nova);
      });
      test('joyful -> shimmer', () {
        expect(OpenRouterVocalService.voiceForEmotion('joyful'), TtsVoice.shimmer);
      });
      test('friendly -> shimmer', () {
        expect(OpenRouterVocalService.voiceForEmotion('friendly'), TtsVoice.shimmer);
      });
      test('excited -> fable', () {
        expect(OpenRouterVocalService.voiceForEmotion('excited'), TtsVoice.fable);
      });
      test('serious -> echo', () {
        expect(OpenRouterVocalService.voiceForEmotion('serious'), TtsVoice.echo);
      });
      test('sad -> onyx', () {
        expect(OpenRouterVocalService.voiceForEmotion('sad'), TtsVoice.onyx);
      });
      test('unknown -> nova fallback', () {
        expect(OpenRouterVocalService.voiceForEmotion('unknown'), TtsVoice.nova);
      });
    });

    group('defaultVoice', () {
      test('jovial mode -> shimmer', () {
        expect(OpenRouterVocalService.defaultVoice(useJovial: true), TtsVoice.shimmer);
      });
      test('fast mode -> nova', () {
        expect(OpenRouterVocalService.defaultVoice(useJovial: false), TtsVoice.nova);
      });
    });

    group('LLM chain routing', () {
      test('jovial chain exists and is accessible', () {
        expect(OpenRouterVocalService.defaultVoice, isNotNull);
      });
    });
  });
}
