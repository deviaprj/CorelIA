import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helpers pour les tests

/// Crée un widget enveloppé dans ProviderScope
Widget createTestWidget(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

/// Attend qu'un SnackBar apparaisse et vérifie son contenu
Future<void> expectSnackBar(WidgetTester tester, String message) async {
  await tester.pump();
  expect(find.byType(SnackBar), findsOneWidget);
  expect(find.text(message), findsOneWidget);
}

/// Attend qu'un dialogue apparaisse et vérifie son contenu
Future<void> expectDialog(WidgetTester tester, String title) async {
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
  expect(find.text(title), findsOneWidget);
}

/// Ferme un dialogue en cliquant sur un bouton
Future<void> tapDialogButton(WidgetTester tester, String buttonText) async {
  await tester.tap(find.widgetWithText(TextButton, buttonText));
  await tester.pumpAndSettle();
}

/// Mock d'un stream avec des données de test
Stream<T> mockStream<T>(List<T> data) async* {
  for (final item in data) {
    yield item;
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

/// Vérifie que le widget a le bon type
void expectWidgetType<T>(Finder finder) {
  expect(finder, findsOneWidget);
  expect(
    finder.evaluate().first.widget,
    isA<T>(),
  );
}

/// Attend l'apparition d'un widget
Future<void> waitForWidget(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final endTime = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(endTime)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw Exception('Widget not found within timeout');
}

/// Simule un swipe pour dismiss
Future<void> swipeToDismiss(
  WidgetTester tester,
  Finder finder, {
  Offset offset = const Offset(-500, 0),
}) async {
  await tester.drag(finder, offset);
  await tester.pumpAndSettle();
}

/// Vérifie les propriétés d'un TextField
void expectTextField(
  WidgetTester tester,
  Finder finder, {
  String? hintText,
  bool? obscureText,
  TextInputType? keyboardType,
}) {
  final field = tester.widget<TextField>(finder);

  if (hintText != null) {
    expect(field.decoration?.hintText, equals(hintText));
  }

  if (obscureText != null) {
    expect(field.obscureText, equals(obscureText));
  }

  if (keyboardType != null) {
    expect(field.keyboardType, equals(keyboardType));
  }
}

/// Extension pour les tests de performance
extension PerformanceTester on WidgetTester {
  /// Mesure le temps d'exécution d'une action
  Future<int> measureTime(Future<void> Function() action) async {
    final stopwatch = Stopwatch()..start();
    await action();
    stopwatch.stop();
    return stopwatch.elapsedMilliseconds;
  }

  /// Vérifie le nombre de frames
  Future<int> countFrames(Future<void> Function() action) async {
    int frameCount = 0;
    binding.addTimeStampCallback((_) => frameCount++);
    await action();
    binding.removeTimeStampCallback((_) {});
    return frameCount;
  }
}

/// Mock de Firebase Auth
class MockFirebaseAuth {
  bool isSignedIn = false;
  String? userId;
  String? email;

  void signIn({required String uid, required String userEmail}) {
    isSignedIn = true;
    userId = uid;
    email = userEmail;
  }

  void signOut() {
    isSignedIn = false;
    userId = null;
    email = null;
  }
}

/// Mock de Firestore
class MockFirestore {
  final Map<String, Map<String, dynamic>> _data = {};

  void setDocument(String collection, String id, Map<String, dynamic> data) {
    _data['$collection/$id'] = {...data, '_id': id};
  }

  Map<String, dynamic>? getDocument(String collection, String id) {
    return _data['$collection/$id'];
  }

  List<Map<String, dynamic>> query(String collection, {
    String? field,
    dynamic isEqualTo,
  }) {
    return _data.entries
        .where((e) => e.key.startsWith('$collection/'))
        .map((e) => e.value)
        .where((doc) {
          if (field == null) return true;
          return doc[field] == isEqualTo;
        })
        .toList();
  }

  void clear() => _data.clear();
}

/// Générateur de données de test
class TestData {
  static String generateId() => 'test_${DateTime.now().millisecondsSinceEpoch}';

  static String generateEmail() => 'test_${generateId()}@example.com';

  static String loremIpsum({int words = 50}) {
    const words = [
      'lorem', 'ipsum', 'dolor', 'sit', 'amet', 'consectetur',
      'adipiscing', 'elit', 'sed', 'do', 'eiusmod', 'tempor',
      'incididunt', 'ut', 'labore', 'et', 'dolore', 'magna',
    ];
    return List.generate(words, (_) => words[TestData._randomInt(words.length)])
        .join(' ');
  }

  static int _randomInt(int max) => DateTime.now().millisecondsSinceEpoch % max;
}
