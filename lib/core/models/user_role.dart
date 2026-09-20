/// Niveaux d'abonnement de l'application.
enum UserRole {
  /// Assistant IA Free : chat avec recherche Internet, requêtes limitées.
  free('free'),

  /// Agent IA Full : requêtes illimitées et fonctionnalités avancées.
  full('full');

  const UserRole(this.id);

  /// Identifiant persistant (Firestore / RevenueCat).
  final String id;

  bool get isFull => this == UserRole.full;

  /// Tolère l'ancien identifiant `pro` pour ne pas casser les données existantes.
  static UserRole fromId(String? id) => switch (id) {
        'full' || 'pro' => UserRole.full,
        _ => UserRole.free,
      };

  String get label => switch (this) {
        UserRole.free => 'Assistant IA Free',
        UserRole.full => 'Agent IA Full',
      };
}
