import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants.dart';

/// Configuration centralisée de l'API backend AironBot.
abstract class ApiConfig {
  /// URL de base du backend FastAPI.
  /// En dev local : http://10.0.2.2:8000 (Android emulator) ou localhost (iOS/web)
  static const baseUrl = String.fromEnvironment('BACKEND_URL',
      defaultValue: 'https://api.aironbot.app');

  /// Timeout pour les requêtes classiques (recherche, auth, etc.)
  static const connectTimeout = Duration(seconds: 10);

  /// Timeout pour le streaming chat SSE (peut être long)
  static const streamTimeout = Duration(seconds: 120);

  /// Headers communs envoyés avec chaque requête.
  static Map<String, String> get defaultHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'text/event-stream',
    'X-Client-Version': AppConstants.appVersion,
    'X-Platform': defaultTargetPlatform.name,
  };
}
