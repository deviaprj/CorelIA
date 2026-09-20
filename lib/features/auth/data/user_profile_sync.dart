import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/app_user.dart';
import '../../../core/providers/firebase_providers.dart';

/// Profil utilisateur Firestore en temps réel (rôle d'abonnement, nom…).
final userProfileProvider = StreamProvider<AppUser?>((ref) {
  if (isDemoMode) return Stream.value(null);

  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(null);

  return ref
      .watch(firestoreProvider)
      .collection(AppConfig.colUsers)
      .doc(user.uid)
      .snapshots()
      .map((doc) {
    if (!doc.exists) return null;
    try {
      return AppUser.fromFirestore(doc);
    } catch (e) {
      debugPrint('[UserProfile] Erreur de lecture : $e');
      return null;
    }
  });
});
