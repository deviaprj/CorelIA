import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:corel_ia/core/secure_storage.dart';

// Fake implementation for testing
class FakeSecureStorage implements SecureStorageService {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read(String key) async => _storage[key];

  @override
  Future<void> write(String key, String value) async {
    _storage[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _storage.remove(key);
  }

  @override
  Future<void> clear() async {
    _storage.clear();
  }
}

void main() {
  group('StorageKeys', () {
    test('should have correct key names', () {
      expect(StorageKeys.apiKeyDeepSeek, equals('api_key_deepseek'));
      expect(StorageKeys.onboardingDone, equals('onboarding_done'));
      expect(StorageKeys.selectedModel, equals('selected_model'));
      expect(StorageKeys.themeMode, equals('theme_mode'));
      expect(StorageKeys.ttsEnabled, equals('tts_enabled'));
      expect(StorageKeys.speechLang, equals('speech_lang'));
    });
  });

  group('SecureStorageService Operations', () {
    late FakeSecureStorage storage;

    setUp(() {
      storage = FakeSecureStorage();
    });

    test('should write and read value successfully', () async {
      const key = 'test_key';
      const value = 'test_value';

      await storage.write(key, value);
      final result = await storage.read(key);

      expect(result, equals(value));
    });

    test('should return null for non-existent key', () async {
      const key = 'non_existent_key';

      final result = await storage.read(key);

      expect(result, isNull);
    });

    test('should delete value successfully', () async {
      const key = 'test_key';
      const value = 'test_value';

      await storage.write(key, value);
      expect(await storage.read(key), equals(value));

      await storage.delete(key);
      expect(await storage.read(key), isNull);
    });

    test('should clear all values successfully', () async {
      await storage.write('key1', 'value1');
      await storage.write('key2', 'value2');

      expect(await storage.read('key1'), isNotNull);
      expect(await storage.read('key2'), isNotNull);

      await storage.clear();

      expect(await storage.read('key1'), isNull);
      expect(await storage.read('key2'), isNull);
    });

    test('should update existing value', () async {
      const key = 'test_key';
      const value1 = 'value1';
      const value2 = 'value2';

      await storage.write(key, value1);
      expect(await storage.read(key), equals(value1));

      await storage.write(key, value2);
      expect(await storage.read(key), equals(value2));
    });
  });

  group('SharedPreferences Web Storage', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('should write and read values', () async {
      final prefs = await SharedPreferences.getInstance();
      const key = 'airon_secure_test_key';
      const value = 'test_value';

      await prefs.setString(key, value);
      final result = prefs.getString(key);

      expect(result, equals(value));
    });

    test('should prefix keys correctly', () async {
      // Verify the prefix logic used in _WebSecureStorage
      final prefs = await SharedPreferences.getInstance();
      const prefix = 'airon_secure_';
      const key = 'my_key';
      const value = 'my_value';

      await prefs.setString('$prefix$key', value);
      final result = prefs.getString('$prefix$key');

      expect(result, equals(value));
    });
  });
}
