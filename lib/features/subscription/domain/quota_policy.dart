import '../../../core/models/user_role.dart';

/// Politique d'usage associée à un rôle d'abonnement.
///
/// Toutes les limites sont centralisées ici : un seul endroit à modifier pour
/// ajuster l'offre Free ou Full.
class QuotaPolicy {
  const QuotaPolicy({
    required this.dailyRequests,
    required this.maxAttachmentBytes,
    required this.searchEnabled,
    required this.advancedFeatures,
  });

  /// Nombre de requêtes par jour ; `null` = illimité.
  final int? dailyRequests;

  /// Taille totale maximale des pièces jointes d'un message (octets).
  final int maxAttachmentBytes;

  /// Recherche Internet autorisée.
  final bool searchEnabled;

  /// Fonctionnalités avancées (modèles premium, pièces jointes étendues…).
  final bool advancedFeatures;

  bool get unlimited => dailyRequests == null;
  bool get limited => !unlimited;
}

/// Barème des rôles.
abstract class QuotaPolicies {
  static const free = QuotaPolicy(
    dailyRequests: 20,
    maxAttachmentBytes: 5 * 1024 * 1024,
    searchEnabled: true,
    advancedFeatures: false,
  );

  static const full = QuotaPolicy(
    dailyRequests: null, // illimité
    maxAttachmentBytes: 25 * 1024 * 1024,
    searchEnabled: true,
    advancedFeatures: true,
  );

  static QuotaPolicy forRole(UserRole role) =>
      role.isFull ? full : free;
}
