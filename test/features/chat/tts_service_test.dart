import 'package:corel_ia/features/chat/data/tts_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFlutterTts extends Mock implements FlutterTts {}

void main() {
  late _MockFlutterTts engine;
  late TtsService service;

  setUp(() {
    engine = _MockFlutterTts();

    when(() => engine.setSpeechRate(any())).thenAnswer((_) async => 1);
    when(() => engine.setPitch(any())).thenAnswer((_) async => 1);
    when(() => engine.setVolume(any())).thenAnswer((_) async => 1);
    when(() => engine.awaitSpeakCompletion(any())).thenAnswer((_) async => 1);
    when(() => engine.stop()).thenAnswer((_) async => 1);
    when(() => engine.setLanguage(any())).thenAnswer((_) async => 1);
    when(() => engine.getVoices).thenAnswer((_) async => <dynamic>[]);
    when(() => engine.speak(any())).thenAnswer((_) async => 1);

    service = TtsService(engine: engine);
  });

  test('applique le débit configuré au moteur', () async {
    await service.speak('Bonjour, comment vas-tu ?');

    verify(() => engine.setSpeechRate(TtsService.speechRate)).called(1);
    verify(() => engine.setPitch(1.0)).called(1);
    verify(() => engine.setVolume(1.0)).called(1);
  });

  test('configure le moteur une seule fois', () async {
    await service.speak('Premier message.');
    await service.speak('Second message.');

    verify(() => engine.setSpeechRate(TtsService.speechRate)).called(1);
    verify(() => engine.speak(any())).called(2);
  });

  test('lit le texte nettoyé des emojis et du Markdown', () async {
    await service.speak('**Bravo** 🎉 pour `ce` résultat !');

    final spoken = verify(() => engine.speak(captureAny())).captured.single;
    expect(spoken, 'Bravo pour ce résultat !');
  });

  test('ne sollicite pas le moteur pour un texte vide', () async {
    var done = false;
    service.onDone = () => done = true;

    await service.speak('🎉🎉');

    verifyNever(() => engine.speak(any()));
    expect(done, isTrue);
  });

  test('choisit la langue d\'après le texte lu', () async {
    await service.speak('The capital of Canada is Ottawa, and you can visit it.');

    final language = verify(() => engine.setLanguage(captureAny())).captured.last;
    expect(language, 'en-US');
  });
}
