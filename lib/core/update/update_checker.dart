import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';

/// Resultat de la verification de mise a jour.
class UpdateCheckResult {
  final bool hasUpdate;
  final String? currentVersion;
  final String? latestVersion;
  final String? downloadUrl;
  final String? releaseNotes;
  final bool isRequired;

  const UpdateCheckResult({
    required this.hasUpdate,
    this.currentVersion,
    this.latestVersion,
    this.downloadUrl,
    this.releaseNotes,
    this.isRequired = false,
  });

  factory UpdateCheckResult.noUpdate() =>
      const UpdateCheckResult(hasUpdate: false);

  factory UpdateCheckResult.updateAvailable({
    required String currentVersion,
    required String latestVersion,
    required String downloadUrl,
    String? releaseNotes,
    bool isRequired = false,
  }) =>
      UpdateCheckResult(
        hasUpdate: true,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        releaseNotes: releaseNotes,
        isRequired: isRequired,
      );
}

/// Service de verification de mise a jour desktop.
///
/// Interroge un endpoint distant pour comparer la version locale
/// avec la derniere version disponible.
class UpdateChecker {
  static const String _updateEndpoint =
      'https://downloads.corelia.app/updates/latest.json';

  final http.Client _httpClient;
  final String currentVersion;

  UpdateChecker({
    http.Client? httpClient,
    String? currentVersion,
  })  : _httpClient = httpClient ?? http.Client(),
        currentVersion = currentVersion ?? AppConstants.appVersion;

  /// Verifie si une mise a jour est disponible.
  Future<UpdateCheckResult> check() async {
    try {
      final response = await _httpClient
          .get(Uri.parse(_updateEndpoint))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return UpdateCheckResult.noUpdate();
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // Supporte les cles Linux et Windows
      final platform = defaultTargetPlatform;
      final platformKey = platform == TargetPlatform.linux
          ? 'linux'
          : platform == TargetPlatform.windows
              ? 'windows'
              : 'linux';

      final platformData =
          data[platformKey] as Map<String, dynamic>? ?? data;

      final latestVersion = platformData['version'] as String?;
      if (latestVersion == null) return UpdateCheckResult.noUpdate();

      if (_isNewer(latestVersion, currentVersion)) {
        return UpdateCheckResult.updateAvailable(
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          downloadUrl: platformData['download_url'] as String? ?? '',
          releaseNotes: platformData['release_notes'] as String?,
          isRequired: platformData['required'] as bool? ?? false,
        );
      }

      return UpdateCheckResult.noUpdate();
    } catch (e) {
      debugPrint('[UpdateChecker] Check error: $e');
      return UpdateCheckResult.noUpdate();
    }
  }

  /// Compare deux versions semver.
  bool _isNewer(String latest, String current) {
    try {
      final latestParts = latest
          .split('.')
          .map((p) => int.tryParse(p) ?? 0)
          .toList();
      final currentParts = current
          .split('.')
          .map((p) => int.tryParse(p) ?? 0)
          .toList();

      for (var i = 0; i < 3; i++) {
        final l = i < latestParts.length ? latestParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
    } catch (_) {}
    return false;
  }
}
