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
///
/// En mode démo, on s'appuie sur le repository mock ; sinon sur Firebase. On ne
/// retombe **jamais** silencieusement sur le mock : un utilisateur non connecté
/// doit être vu comme tel (sinon l'historique se retrouve hors du compte).
final authStateProvider = StreamProvider<dynamic>((ref) {
  if (isDemoMode) return mockAuthRepository.authStateChanges;
  try {
    return ref.watch(firebaseAuthProvider).authStateChanges();
  } catch (_) {
    return const Stream<Never>.empty();
  }
});

/// Utilisateur courant, normalisé pour l'UI (uid / nom / e-mail / vérification).
final currentUserProvider = Provider<AppUserLike?>((ref) {
  if (isDemoMode) {
    final user = mockAuthRepository.currentUser;
    if (user == null) return null;
    return AppUserLike(
      uid: user.uid,
      displayName: user.label,
      email: user.email,
      // Les comptes simulés sont considérés confirmés : sans serveur, il n'y a
      // aucune boîte mail où cliquer.
      emailVerified: true,
    );
  }

  final firebaseUser = ref.watch(authStateProvider).valueOrNull;
  if (firebaseUser is! User) return null;

  // Seul l'e-mail/mot de passe exige une confirmation d'adresse : un compte
  // Google (ou invité) est vérifié par son fournisseur.
  final signedInWithPassword =
      firebaseUser.providerData.any((info) => info.providerId == 'password');

  return AppUserLike(
    uid: firebaseUser.uid,
    displayName: firebaseUser.displayName,
    email: firebaseUser.email,
    emailVerified: firebaseUser.emailVerified,
    signedInWithPassword: signedInWithPassword,
  );
});

/// Enveloppe typée pour éviter le `dynamic` côté UI.
class AppUserLike {
  const AppUserLike({
    required this.uid,
    this.displayName,
    this.email,
    this.emailVerified = false,
    this.signedInWithPassword = false,
  });

  final String uid;
  final String? displayName;
  final String? email;

  /// Adresse confirmée côté fournisseur. Par défaut `false` : en cas de doute on
  /// demande la confirmation plutôt que de laisser passer un compte non vérifié.
  final bool emailVerified;
  final bool signedInWithPassword;

  /// Un compte e-mail/mot de passe doit confirmer son adresse avant d'entrer.
  bool get needsEmailVerification => signedInWithPassword && !emailVerified;

  /// Nom affichable, avec replis progressifs.
  String get label {
    final pseudo = displayName?.trim();
    if (pseudo != null && pseudo.isNotEmpty) return pseudo;
    final mail = email?.trim();
    if (mail != null && mail.isNotEmpty) return mail.split('@').first;
    return 'Utilisateur';
  }
}
