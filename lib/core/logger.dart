import 'package:flutter/foundation.dart';

/// Niveaux de log structure.
enum LogLevel { debug, info, warn, error }

/// Logger structure leger pour remplacer les `debugPrint()` eparpilles.
///
/// Usage :
/// ```dart
/// final log = AppLogger('ChatNotifier');
/// log.info('Stream started', {'model': modelId});
/// log.warn('Quota exceeded');
/// log.error('API call failed', {'statusCode': 429});
/// ```
///
/// En production (kReleaseMode), seuls les niveaux [warn] et [error] sont affiches.
/// En debug, tous les niveaux sont visibles.
class AppLogger {
  final String _tag;

  const AppLogger(this._tag);

  void debug(String message, [Map<String, dynamic>? extra]) =>
      _log(LogLevel.debug, message, extra);

  void info(String message, [Map<String, dynamic>? extra]) =>
      _log(LogLevel.info, message, extra);

  void warn(String message, [Map<String, dynamic>? extra]) =>
      _log(LogLevel.warn, message, extra);

  void error(String message, [Map<String, dynamic>? extra]) =>
      _log(LogLevel.error, message, extra);

  void _log(LogLevel level, String message, Map<String, dynamic>? extra) {
    // En release, ne logger que les warnings et erreurs
    if (kReleaseMode && level != LogLevel.warn && level != LogLevel.error) {
      return;
    }

    final prefix = '[${_tag}]';
    final levelStr = level.name.toUpperCase();
    final extraStr = extra != null && extra.isNotEmpty ? ' | $extra' : '';

    final line = '$prefix [$levelStr] $message$extraStr';

    if (level == LogLevel.error) {
      debugPrint('\x1B[31m$line\x1B[0m'); // rouge
    } else if (level == LogLevel.warn) {
      debugPrint('\x1B[33m$line\x1B[0m'); // jaune
    } else {
      debugPrint(line);
    }
  }
}
