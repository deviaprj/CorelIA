import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_config.dart';
import '../secure_storage.dart';

/// Exception API structurée portant le code HTTP et le message.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? path;

  const ApiException(this.message, {this.statusCode, this.path});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Factory pour créer un client Dio configuré (version web).
///
/// Pas de certificate pinning sur web (pas de dart:io).
class DioClientFactory {
  static Dio create() {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.streamTimeout,
        headers: ApiConfig.defaultHeaders,
      ),
    );

    dio.interceptors.addAll([
      _AuthInterceptor(),
      _RetryInterceptor(dio),
      if (kDebugMode)
        LogInterceptor(
          requestBody: true,
          responseBody: false,
          error: true,
        ),
    ]);

    return dio;
  }
}

/// Intercepteur qui injecte le JWT Firebase dans chaque requête.
class _AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final token = await SecureStorageService().read(StorageKeys.firebaseIdToken);
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    } catch (e) {
      debugPrint('[Dio] Impossible de lire le token : $e');
    }
    handler.next(options);
  }
}

/// Intercepteur qui retry automatiquement sur erreur réseau.
class _RetryInterceptor extends Interceptor {
  final Dio dio;
  static const maxRetries = 3;

  _RetryInterceptor(this.dio);

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = err.requestOptions.extra;
    final attempt = (extra['retry_attempt'] as int?) ?? 0;

    if (attempt < maxRetries && _shouldRetry(err)) {
      await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      extra['retry_attempt'] = attempt + 1;
      try {
        final response = await dio.fetch(err.requestOptions..extra = extra);
        handler.resolve(response);
        return;
      } on DioException catch (e) {
        handler.reject(e);
        return;
      }
    }
    handler.reject(err);
  }

  bool _shouldRetry(DioException error) {
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError ||
        (error.response?.statusCode ?? 0) >= 500;
  }
}

final dioProvider = Provider((ref) => DioClientFactory.create());