import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/domain/app_user.dart';
import '../../../main.dart' show isDemoMode;

/// Provider qui écoute le document utilisateur Firestore en temps réel.
/// Permet la synchronisation multi-appareils du profil (plan, displayName, etc.).
final userProfileProvider = StreamProvider<AppUser?>((ref) {
  if (isDemoMode) return Stream.value(null);

  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(null);

  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection(AppConstants.colUsers)
      .doc(user.uid)
      .snapshots()
      .map((doc) {
    if (!doc.exists) return null;
    try {
      return AppUser.fromFirestore(doc);
    } catch (e) {
      debugPrint('[UserProfileSync] Parse error: $e');
      return null;
    }
  });
});

/// Provider qui indique si l'utilisateur est Pro, avec synchronisation temps réel.
/// Sur mobile, utilise RevenueCat ; sur web/extension, utilise Firestore.
/// Ce provider combine les deux sources et prend la valeur la plus favorable.
final isProSyncProvider = Provider<bool>((ref) {
  if (isDemoMode) return false;

  // Sur web/extension : vérifier Firestore en temps réel
  final userProfile = ref.watch(userProfileProvider).valueOrNull;
  if (userProfile != null) {
    return userProfile.isPro;
  }

  // Fallback : ne pas bloquer si Firestore n'est pas encore chargé
  return false;
});