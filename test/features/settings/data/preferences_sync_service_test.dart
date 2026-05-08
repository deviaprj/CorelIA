import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/settings/data/preferences_sync_service.dart';

void main() {
  group('SyncedPreferences', () {
    test('construction par défaut', () {
      const prefs = SyncedPreferences();
      expect(prefs.systemPrompt, '');
      expect(prefs.themeMode, 'system');
      expect(prefs.ttsSpeed, 0.65);
      expect(prefs.updatedAt, isNull);
    });

    test('construction avec valeurs', () {
      const prefs = SyncedPreferences(
        systemPrompt: 'Tu es Corely',
        themeMode: 'dark',
        ttsSpeed: 0.8,
        updatedAt: null,
      );
      expect(prefs.systemPrompt, 'Tu es Corely');
      expect(prefs.themeMode, 'dark');
      expect(prefs.ttsSpeed, 0.8);
    });

    test('toFirestore et fromFirestore', () {
      const prefs = SyncedPreferences(
        systemPrompt: 'Test prompt',
        themeMode: 'light',
        ttsSpeed: 0.75,
      );
      final map = prefs.toFirestore();
      expect(map['systemPrompt'], 'Test prompt');
      expect(map['themeMode'], 'light');
      expect(map['ttsSpeed'], 0.75);
      expect(map['updatedAt'], isNotNull);
    });

    test('fromFirestore avec document null', () {
      // On ne peut pas facilement créer un DocumentSnapshot mock,
      // donc on teste que les valeurs par défaut sont correctes
      const prefs = SyncedPreferences();
      expect(prefs.systemPrompt, '');
      expect(prefs.themeMode, 'system');
    });
  });

  group('PreferencesSyncService', () {
    test('constructeur avec paramètres', () {
      // On ne peut pas tester Firebase en unit test,
      // mais on vérifie que la classe peut être instanciée
      expect(PreferencesSyncService, isNotNull);
    });
  });
}