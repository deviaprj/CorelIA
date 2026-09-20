import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Exception API structurée (code HTTP + message).
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Fabrique de clients Dio pour les appels réseau simples (recherche web).
///
/// Un retry automatique couvre les erreurs transitoires ; le logging n'est
/// activé qu'en debug et n'expose jamais les corps de réponse.
abstract class ApiClient {
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);

  static Dio create({
    Duration? receiveTimeout,
    Map<String, String>? headers,
    BaseOptions? baseOptions,
  }) {
    final dio = Dio(
      baseOptions ??
          BaseOptions(
            connectTimeout: ApiClient.connectTimeout,
            receiveTimeout: receiveTimeout ?? ApiClient.receiveTimeout,
            headers: {
              'Accept': 'application/json',
              ...?headers,
            },
          ),
    );

    dio.interceptors.add(_RetryInterceptor(dio));
    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(requestBody: false, responseBody: false, error: true),
      );
    }
    return dio;
  }
}

/// Retente automatiquement les erreurs réseau et les 5xx (3 tentatives).
class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(this._dio);

  final Dio _dio;
  static const _maxRetries = 3;

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = err.requestOptions.extra;
    final attempt = (extra['retry_attempt'] as int?) ?? 0;

    if (attempt < _maxRetries && _shouldRetry(err)) {
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      extra['retry_attempt'] = attempt + 1;
      try {
        final response = await _dio.fetch<dynamic>(err.requestOptions..extra = extra);
        handler.resolve(response);
        return;
      } on DioException catch (e) {
        handler.reject(e);
        return;
      }
    }
    handler.reject(err);
  }

  bool _shouldRetry(DioException error) =>
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.connectionError ||
      (error.response?.statusCode ?? 0) >= 500;
}
