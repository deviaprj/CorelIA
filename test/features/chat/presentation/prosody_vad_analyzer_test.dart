import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/presentation/prosody_vad_analyzer.dart';

void main() {
  group('ProsodyVadAnalyzer', () {
    late ProsodyVadAnalyzer vad;

    setUp(() {
      vad = ProsodyVadAnalyzer();
    });

    tearDown(() {
      vad.reset();
    });

    test('waiting quand aucune donnee', () {
      expect(vad.evaluate(), SpeechFinalDecision.waiting);
    });

    test('endOfPhrase quand ponctuation finale + silence 400ms', () async {
      vad.onTranscriptUpdate('Bonjour.', isFinal: true);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(vad.evaluate(), SpeechFinalDecision.endOfPhrase);
    });

    test('endOfPhrase quand pas de ponctuation + silence 900ms', () async {
      vad.onTranscriptUpdate('Bonjour');
      await Future<void>.delayed(const Duration(milliseconds: 950));
      expect(vad.evaluate(), SpeechFinalDecision.endOfPhrase);
    });

    test('waiting quand ponctuation + silence < 200ms', () async {
      vad.onTranscriptUpdate('Bonjour.');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(vad.evaluate(), SpeechFinalDecision.waiting);
    });

    test('waiting quand pas de ponctuation + silence < 900ms', () async {
      vad.onTranscriptUpdate('Bonjour');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(vad.evaluate(), SpeechFinalDecision.waiting);
    });

    test('endOfPhrase quand utterance > 12s', () async {
      vad.onTranscriptUpdate('Ceci est un test');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // Simulate 12+ seconds by manipulating the internal state isn't possible
      // since _utteranceStart is private. Instead, test with default timing.
      // For a real 12s test, we'd need a mockable clock. This test documents
      // the requirement; in practice the safety cap triggers after 12s.
      // We verify the constructor accepts the parameter.
      final customVad = ProsodyVadAnalyzer(maxUtteranceDuration: const Duration(milliseconds: 50));
      customVad.onTranscriptUpdate('Test');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(customVad.evaluate(), SpeechFinalDecision.endOfPhrase);
    });

    test('breathingPause quand silence 200-400ms avec ponctuation', () async {
      vad.onTranscriptUpdate('Bonjour.');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(vad.evaluate(), SpeechFinalDecision.breathingPause);
    });

    test('breathingPause sans ponctuation mais energie remonte', () async {
      vad.onTranscriptUpdate('Bonjour');
      vad.onSoundLevelChange(0.1);
      vad.onSoundLevelChange(0.05);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      vad.onSoundLevelChange(0.2); // energy rising
      expect(vad.evaluate(), SpeechFinalDecision.breathingPause);
    });

    test('energy drop below 15% of peak sustained 300ms triggers endOfPhrase', () async {
      vad.onTranscriptUpdate('Test sans ponctuation');
      vad.onSoundLevelChange(0.8);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      vad.onSoundLevelChange(0.05);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      vad.onSoundLevelChange(0.04);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(vad.evaluate(), SpeechFinalDecision.endOfPhrase);
    });

    test('reset remet tout a zero', () {
      vad.onTranscriptUpdate('Test');
      vad.onSoundLevelChange(0.5);
      vad.reset();
      expect(vad.evaluate(), SpeechFinalDecision.waiting);
    });
  });
}
