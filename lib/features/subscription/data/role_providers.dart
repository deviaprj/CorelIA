import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/user_role.dart';
import '../../auth/data/user_profile_sync.dart';

/// Rôle d'abonnement courant de l'utilisateur.
///
/// Source : le document utilisateur Firestore (`plan`). En mode démo, tout le
/// monde est en Free. L'abonnement RevenueCat met à jour ce champ (voir
/// `subscription_service.dart`).
final userRoleProvider = Provider<UserRole>((ref) {
  if (isDemoMode) return UserRole.free;
  final profile = ref.watch(userProfileProvider).valueOrNull;
  return profile?.role ?? UserRole.free;
});
