import 'package:firebase_auth/firebase_auth.dart';

/// Traduit une erreur d'authentification en message lisible par l'utilisateur.
///
/// Les messages bruts de Firebase sont en anglais et parfois techniques : on
/// mappe les codes connus, et on garde le code entre parenthèses pour le support.
String authErrorMessage(Object? error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-email' => 'Adresse e-mail invalide.',
      'user-disabled' => 'Ce compte a été désactivé.',
      'user-not-found' => 'Aucun compte ne correspond à cette adresse.',
      'wrong-password' || 'invalid-credential' =>
        'E-mail ou mot de passe incorrect.',
      'email-already-in-use' => 'Un compte existe déjà avec cette adresse.',
      'weak-password' => 'Mot de passe trop faible (8 caractères minimum).',
      'operation-not-allowed' =>
        'Ce mode de connexion n\'est pas activé côté serveur.',
      'too-many-requests' =>
        'Trop de tentatives. Réessaie dans quelques minutes.',
      'network-request-failed' =>
        'Connexion impossible. Vérifie ton accès à Internet.',
      'requires-recent-login' =>
        'Reconnecte-toi avant d\'effectuer cette action.',
      'account-exists-with-different-credential' =>
        'Cette adresse est déjà utilisée avec un autre mode de connexion.',
      _ => 'Échec de l\'authentification (${error.code}).',
    };
  }

  if (error is StateError) {
    return 'Comptes en ligne indisponibles : ${error.message}';
  }

  return 'Échec de l\'authentification.';
}
