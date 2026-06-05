import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service de vision via Ollama (modèle multimodal local).
///
/// Protocole : POST http://<host>:11434/api/generate
/// Body : { model: "llava:13b", prompt: "...", images: ["base64..."], stream: false }
///
/// 100% autonome — fonctionne sur le réseau local, aucun cloud requis.
class OllamaVisionService {
  static const String defaultModel = 'llava:13b';
  static const String defaultHost = 'http://localhost:11434';
  static const String _prefsKeyHost = 'ollama_host';
  static const String _prefsKeyModel = 'ollama_model';
  static const String _prefsKeyEnabled = 'ollama_enabled';

  final Dio _dio;

  OllamaVisionService({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        ));

  /// Hôte Ollama configuré (persisté dans SharedPreferences).
  String _host = defaultHost;
  String _model = defaultModel;
  bool _enabled = false;
  bool _initialized = false;

  String get host => _host;
  String get model => _model;
  bool get enabled => _enabled;

  /// Charge la configuration depuis SharedPreferences.
  Future<void> loadConfig() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _host = prefs.getString(_prefsKeyHost) ?? defaultHost;
      _model = prefs.getString(_prefsKeyModel) ?? defaultModel;
      _enabled = prefs.getBool(_prefsKeyEnabled) ?? false;
      debugPrint('[OllamaVision] Config: host=$_host, model=$_model, enabled=$_enabled');
    } catch (e) {
      debugPrint('[OllamaVision] Load config error: $e');
    }
  }

  /// Sauvegarde la configuration.
  Future<void> saveConfig({
    String? host,
    String? model,
    bool? enabled,
  }) async {
    if (host != null) _host = host;
    if (model != null) _model = model;
    if (enabled != null) _enabled = enabled;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyHost, _host);
      await prefs.setString(_prefsKeyModel, _model);
      await prefs.setBool(_prefsKeyEnabled, _enabled);
      debugPrint('[OllamaVision] Config saved: host=$_host, model=$_model, enabled=$_enabled');
    } catch (e) {
      debugPrint('[OllamaVision] Save config error: $e');
    }
  }

  /// Teste si Ollama est disponible au démarrage (ping GET /api/tags).
  Future<bool> isAvailable() async {
    if (!_enabled) return false;
    try {
      final response = await _dio.get<dynamic>(
        '$_host/api/tags',
        options: Options(sendTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[OllamaVision] Not available: $e');
      return false;
    }
  }

  /// Analyse une image via Ollama.
  /// [imageBase64] : image encodée en base64 (sans préfixe data:).
  /// [prompt] : question sur l'image.
  /// Retourne la description textuelle de l'image.
  Future<String> analyzeImage({
    required String imageBase64,
    required String prompt,
  }) async {
    if (!_enabled) throw StateError('Ollama vision is disabled');

    final response = await _dio.post<dynamic>(
      '$_host/api/generate',
      data: jsonEncode({
        'model': _model,
        'prompt': prompt,
        'images': [imageBase64],
        'stream': false,
      }),
      options: Options(
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 120),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    if (response.statusCode == 200 && response.data is Map) {
      final data = response.data as Map<String, dynamic>;
      return data['response'] as String? ?? '';
    }

    throw StateError('Ollama vision: unexpected response ${response.statusCode}');
  }

  /// Liste les modèles disponibles sur le serveur Ollama.
  Future<List<String>> listModels() async {
    try {
      final response = await _dio.get<dynamic>(
        '$_host/api/tags',
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final models = data['models'] as List<dynamic>? ?? [];
        return models.map((m) {
          final model = m as Map<String, dynamic>;
          return model['name'] as String? ?? '';
        }).where((n) => n.isNotEmpty).toList();
      }
    } catch (e) {
      debugPrint('[OllamaVision] List models error: $e');
    }
    return [];
  }
}

final ollamaVisionServiceProvider = Provider<OllamaVisionService>((ref) => OllamaVisionService());