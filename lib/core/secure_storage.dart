import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stockage sécurisé abstrait — utilise flutter_secure_storage sur mobile,
/// SharedPreferences sur web (chrome.storage.local via JS serait l'idéal en prod).
abstract class SecureStorageService {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
  Future<void> clear();

  factory SecureStorageService() {
    if (kIsWeb) return _WebSecureStorage();
    return _NativeSecureStorage();
  }
}

class _NativeSecureStorage implements SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> clear() => _storage.deleteAll();
}

class _WebSecureStorage implements SecureStorageService {
  static const _prefix = 'airon_secure_';

  @override
  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', value);
  }

  @override
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$key');
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}

/// Clés de stockage
abstract class StorageKeys {
  static const apiKeyDeepSeek = 'api_key_deepseek';
  static const firebaseIdToken = 'firebase_id_token';
  static const onboardingDone = 'onboarding_done';
  static const selectedModel = 'selected_model';
  static const themeMode = 'theme_mode';
  static const ttsEnabled = 'tts_enabled';
  static const speechLang = 'speech_lang';
}
