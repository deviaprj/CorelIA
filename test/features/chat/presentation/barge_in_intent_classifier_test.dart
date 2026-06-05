import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/features/chat/presentation/barge_in_intent_classifier.dart';

void main() {
  group('BargeInIntentClassifier', () {
    test('single word "stop" → stop', () {
      expect(BargeInIntentClassifier.classify('stop'), BargeInIntent.stop);
    });

    test('single word "chut" → stop', () {
      expect(BargeInIntentClassifier.classify('chut'), BargeInIntent.stop);
    });

    test('single word "non" → correction', () {
      expect(BargeInIntentClassifier.classify('non'), BargeInIntent.correction);
    });

    test('single word "encore" → repeat', () {
      expect(BargeInIntentClassifier.classify('encore'), BargeInIntent.repeat);
    });

    test('single word "pardon" → repeat', () {
      expect(BargeInIntentClassifier.classify('pardon'), BargeInIntent.repeat);
    });

    test('single word "quoi" → repeat', () {
      expect(BargeInIntentClassifier.classify('quoi'), BargeInIntent.repeat);
    });

    test('single word "bonjour" → none', () {
      expect(BargeInIntentClassifier.classify('bonjour'), BargeInIntent.none);
    });

    test('single word "ok" → none', () {
      expect(BargeInIntentClassifier.classify('ok'), BargeInIntent.none);
    });

    test('multi-word stop patterns', () {
      expect(BargeInIntentClassifier.classify('Tais toi'), BargeInIntent.stop);
      expect(BargeInIntentClassifier.classify('Arrête de parler'), BargeInIntent.stop);
      expect(BargeInIntentClassifier.classify('Silence s\'il te plait'), BargeInIntent.stop);
      expect(BargeInIntentClassifier.classify('Coupe le son'), BargeInIntent.stop);
      expect(BargeInIntentClassifier.classify('Fini'), BargeInIntent.none);
    });

    test('multi-word topicChange patterns', () {
      expect(
        BargeInIntentClassifier.classify('Changement de sujet'),
        BargeInIntent.topicChange,
      );
      expect(
        BargeInIntentClassifier.classify('Parle-moi de Paris'),
        BargeInIntent.topicChange,
      );
      expect(
        BargeInIntentClassifier.classify("On parle d'autre chose"),
        BargeInIntent.topicChange,
      );
    });

    test('multi-word correction patterns', () {
      expect(
        BargeInIntentClassifier.classify('Attends une seconde'),
        BargeInIntent.correction,
      );
      expect(
        BargeInIntentClassifier.classify("C'est pas ça"),
        BargeInIntent.correction,
      );
      expect(
        BargeInIntentClassifier.classify("J'ai fait une erreur"),
        BargeInIntent.correction,
      );
    });

    test('multi-word repeat patterns', () {
      expect(
        BargeInIntentClassifier.classify('Répète ça'),
        BargeInIntent.repeat,
      );
      expect(
        BargeInIntentClassifier.classify('Tu peux répéter'),
        BargeInIntent.repeat,
      );
      expect(
        BargeInIntentClassifier.classify("Je n'ai pas compris"),
        BargeInIntent.repeat,
      );
    });

    test('empty string → none', () {
      expect(BargeInIntentClassifier.classify(''), BargeInIntent.none);
    });

    test('whitespace only → none', () {
      expect(BargeInIntentClassifier.classify('   '), BargeInIntent.none);
    });

    test('texte sans intention → none', () {
      expect(
        BargeInIntentClassifier.classify('Il fait beau aujourd\'hui'),
        BargeInIntent.none,
      );
      expect(
        BargeInIntentClassifier.classify('La tour Eiffel est à Paris'),
        BargeInIntent.none,
      );
    });

    test('priorité stop > topicChange > correction > repeat', () {
      // "stop" et "changement de sujet" ensemble → stop (testé en premier)
      expect(
        BargeInIntentClassifier.classify('Stop, changement de sujet'),
        BargeInIntent.stop,
      );
      // "non" et "répète" ensemble → correction (testé avant repeat)
      expect(
        BargeInIntentClassifier.classify('Non, répète ça'),
        BargeInIntent.correction,
      );
    });
  });
}
