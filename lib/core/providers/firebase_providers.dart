import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/mock_auth_repository.dart';
import '../config/app_config.dart';

/// Instance FirebaseAuth.
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

/// Instance Firestore.
final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

/// Flux d'authentification.
/// En mode démo, on s'appuie sur le repository mock.
final authStateProvider = StreamProvider<dynamic>((ref) {
  if (isDemoMode) return mockAuthRepository.authStateChanges;
  try {
    return ref.watch(firebaseAuthProvider).authStateChanges();
  } catch (_) {
    return mockAuthRepository.authStateChanges;
  }
});

/// Utilisateur courant, normalisé pour l'UI (uid / nom / email).
final currentUserProvider = Provider<AppUserLike?>((ref) {
  if (isDemoMode) {
    final user = mockAuthRepository.currentUser;
    if (user == null) return null;
    return AppUserLike(
      uid: user.uid,
      displayName: user.displayName,
      email: user.email,
    );
  }

  try {
    final firebaseUser = ref.watch(authStateProvider).valueOrNull;
    if (firebaseUser == null) return null;
    return AppUserLike(
      uid: (firebaseUser as dynamic).uid as String,
      displayName: (firebaseUser as dynamic).displayName as String?,
      email: (firebaseUser as dynamic).email as String?,
    );
  } catch (_) {
    return null;
  }
});

/// Enveloppe typée pour éviter le `dynamic` côté UI.
class AppUserLike {
  const AppUserLike({required this.uid, this.displayName, this.email});

  final String uid;
  final String? displayName;
  final String? email;
}
