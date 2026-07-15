import 'package:flutter/foundation.dart';
import 'desktop_tool.dart';

/// Niveau de permission pour un outil desktop.
enum PermissionLevel {
  /// Refuse — l'outil ne peut pas etre utilise.
  denied,

  /// Autorise pour cette session uniquement (redemande au prochain lancement).
  grantedOnce,

  /// Autorise de facon permanente.
  grantedAlways,
}

/// Etat des permissions pour une categorie d'outils.
class DesktopPermission {
  final String toolId;
  final PermissionLevel level;
  final DateTime? grantedAt;

  const DesktopPermission({
    required this.toolId,
    required this.level,
    this.grantedAt,
  });

  bool get isGranted =>
      level == PermissionLevel.grantedOnce ||
      level == PermissionLevel.grantedAlways;

  Map<String, dynamic> toJson() => {
        'toolId': toolId,
        'level': level.name,
        'grantedAt': grantedAt?.toIso8601String(),
      };

  factory DesktopPermission.fromJson(Map<String, dynamic> json) =>
      DesktopPermission(
        toolId: json['toolId'] as String,
        level: PermissionLevel.values.firstWhere(
          (e) => e.name == json['level'],
          orElse: () => PermissionLevel.denied,
        ),
        grantedAt: json['grantedAt'] != null
            ? DateTime.tryParse(json['grantedAt'] as String)
            : null,
      );
}

/// Gestionnaire de permissions pour les outils desktop.
///
/// Stocke les permissions en memoire et via SharedPreferences.
/// Avant chaque execution d'outil, verifie si l'utilisateur a donne son accord.
class DesktopPermissionService {
  final Map<String, DesktopPermission> _permissions = {};

  /// Charge les permissions persistees.
  Future<void> load() async {
    // Sera implemente avec SharedPreferences ou SQLite
    // Pour l'instant : stockage memoire
  }

  /// Verifie si un outil est autorise.
  bool isGranted(String toolId) {
    return _permissions[toolId]?.isGranted ?? false;
  }

  /// Obtient le niveau de permission pour un outil.
  PermissionLevel level(String toolId) {
    return _permissions[toolId]?.level ?? PermissionLevel.denied;
  }

  /// Accorde une permission.
  void grant(String toolId, PermissionLevel level) {
    _permissions[toolId] = DesktopPermission(
      toolId: toolId,
      level: level,
      grantedAt: DateTime.now(),
    );
    debugPrint(
        '[DesktopPermission] $toolId → ${level.name}');
  }

  /// Retire une permission.
  void revoke(String toolId) {
    _permissions.remove(toolId);
  }

  /// Revoque toutes les permissions.
  void revokeAll() {
    _permissions.clear();
  }

  /// Demande une permission a l'utilisateur.
  ///
  /// Retourne le niveau accorde, ou [PermissionLevel.denied] si refuse.
  /// Cette methode doit etre appelee depuis l'UI thread (dialog).
  Future<PermissionLevel> requestPermission(
    DesktopTool tool,
  ) async {
    // Pour l'instant, log seulement. L'implementation UI viendra avec
    // un dialog de permission dans le chat_screen.
    debugPrint('[DesktopPermission] Permission requise pour ${tool.name}');
    // En mode DEMO / dev, on accorde automatiquement
    if (kDebugMode) {
      grant(tool.id, PermissionLevel.grantedOnce);
      return PermissionLevel.grantedOnce;
    }
    return PermissionLevel.denied;
  }
}

/// Singleton du service de permissions.
final desktopPermissionService = DesktopPermissionService();
