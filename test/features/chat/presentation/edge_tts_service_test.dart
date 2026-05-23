import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/presentation/edge_tts_service.dart';
import 'package:airon_bot/features/chat/presentation/tts_emotion.dart';
import 'package:airon_bot/features/chat/presentation/emotion_parser.dart';

void main() {
  group('EdgeTtsService', () {
    test('defaultVoice est fr-FR-HenriNeural', () {
      expect(EdgeTtsService.defaultVoice, 'fr-FR-HenriNeural');
    });

    test('frVoices contient les voix françaises', () {
      expect(EdgeTtsService.frVoices, contains('fr-FR-HenriNeural'));
      expect(EdgeTtsService.frVoices, contains('fr-FR-DeniseNeural'));
      expect(EdgeTtsService.frVoices.length, greaterThanOrEqualTo(2));
    });

    test('constructeur initialise les valeurs par défaut', () {
      final service = EdgeTtsService();
      expect(service.voice, EdgeTtsService.defaultVoice);
    });

    test('setVoice modifie la voix', () {
      final service = EdgeTtsService();
      service.setVoice('fr-FR-DeniseNeural');
      expect(service.voice, 'fr-FR-DeniseNeural');
    });

    test('setRate ne crashe pas avec des valeurs limites', () {
      final service = EdgeTtsService();
      service.setRate(0.1);
      service.setRate(5.0);
      service.setRate(1.5);
    });

    test('setPitch ne crashe pas avec des valeurs limites', () {
      final service = EdgeTtsService();
      service.setPitch(0.1);
      service.setPitch(10.0);
      service.setPitch(1.0);
    });

    test('isAvailable est une méthode statique qui retourne un Future<bool>', () async {
      // On ne teste pas l'appel réseau réel, juste que la signature est correcte
      // isAvailable() sera testée en intégration sur un vrai appareil
      expect(EdgeTtsService.isAvailable, isA<Function>());
    });
  });

  group('EmotionTtsConfig', () {
    test('neutral a rate < 1.0 et pitch == 1.0', () {
      final neutral = emotionTtsConfigs[TtsEmotion.neutral]!;
      expect(neutral.rate, lessThan(1.0));
      expect(neutral.pitch, 1.0);
    });

    test('joyful a rate > neutral.rate et pitch > 1.0', () {
      final joyful = emotionTtsConfigs[TtsEmotion.joyful]!;
      final neutral = emotionTtsConfigs[TtsEmotion.neutral]!;
      expect(joyful.rate, greaterThan(neutral.rate));
      expect(joyful.pitch, greaterThan(1.0));
    });

    test('sad a rate < 1.0 et pitch < 1.0', () {
      final sad = emotionTtsConfigs[TtsEmotion.sad]!;
      expect(sad.rate, lessThan(1.0));
      expect(sad.pitch, lessThan(1.0));
    });

    test('toutes les émotions ont une configuration', () {
      for (final emotion in TtsEmotion.values) {
        expect(emotionTtsConfigs.containsKey(emotion), true,
            reason: 'Missing config for $emotion');
      }
    });

    test('chaque config a rate et pitch positifs', () {
      for (final entry in emotionTtsConfigs.entries) {
        expect(entry.value.rate, greaterThan(0.0),
            reason: '${entry.key} rate should be > 0');
        expect(entry.value.pitch, greaterThan(0.0),
            reason: '${entry.key} pitch should be > 0');
      }
    });
  });

  group('EmotionParser', () {
    test('parse retourne neutral quand pas de balise', () {
      final result = EmotionParser.parse('Bonjour, comment ça va ?');
      expect(result.emotion, TtsEmotion.neutral);
      expect(result.cleanText, 'Bonjour, comment ça va ?');
      expect(result.hasEmotionTag, false);
    });

    test('parse détecte [joyeux]', () {
      final result = EmotionParser.parse('[joyeux] Super, ça marche !');
      expect(result.emotion, TtsEmotion.joyful);
      expect(result.cleanText, 'Super, ça marche !');
      expect(result.hasEmotionTag, true);
    });

    test('parse détecte [triste]', () {
      final result = EmotionParser.parse('[triste] Je suis désolé.');
      expect(result.emotion, TtsEmotion.sad);
    });

    test('parse détecte [sérieux]', () {
      final result = EmotionParser.parse('[sérieux] Attention.');
      expect(result.emotion, TtsEmotion.serious);
    });

    test('parse détecte [excité]', () {
      final result = EmotionParser.parse('[excité] Incroyable !');
      expect(result.emotion, TtsEmotion.excited);
    });

    test('parse détecte [amical]', () {
      final result = EmotionParser.parse('[amical] Salut !');
      expect(result.emotion, TtsEmotion.friendly);
    });

    test('parse garde la première émotion si plusieurs balises', () {
      final result = EmotionParser.parse('[joyeux] Super ! [triste] Mais dommage.');
      expect(result.emotion, TtsEmotion.joyful);
      expect(result.cleanText, 'Super ! Mais dommage.');
    });

    test('inferFromText détecte enthousiasme', () {
      expect(EmotionParser.inferFromText('Super, c\'est génial !'), TtsEmotion.excited);
    });

    test('inferFromText retourne neutral pour texte ordinaire', () {
      expect(EmotionParser.inferFromText('Le ciel est bleu.'), TtsEmotion.neutral);
    });
  });
}