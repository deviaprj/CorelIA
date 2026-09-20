import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/app_user.dart';
import '../../../core/providers/firebase_providers.dart';

/// Données saisies à la création d'un compte e-mail/mot de passe.
class RegistrationData {
  const RegistrationData({
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
    required this.birthDate,
  });

  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final DateTime birthDate;

  /// Nom complet, tel qu'enregistré dans le profil Firebase.
  String get fullName => '$firstName $lastName'.trim();
}

/// Contrat d'authentification (implémenté par Firebase, simulé en mode démo).
abstract class AuthRepository {
  Stream<User?> get authStateChanges;

  Future<AppUser?> getCurrentAppUser();

  Future<void> signInWithEmail(String email, String password);

  Future<void> registerWithEmail(RegistrationData data);

  Future<void> signInWithGoogle();

  Future<void> signInAnonymously();

  /// (Re)envoie l'e-mail de vérification au compte connecté.
  Future<void> sendEmailVerification();

  /// Recharge le compte depuis le serveur (met à jour `emailVerified`).
  Future<void> reloadCurrentUser();

  bool get isEmailVerified;

  Future<void> signOut();

  Future<void> deleteAccount();
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  })  : _auth = auth,
        _firestore = firestore;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  @override
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  @override
  Future<AppUser?> getCurrentAppUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final docRef = _firestore.collection(AppConfig.colUsers).doc(user.uid);
    var doc = await docRef.get();
    // Document manquant (compte créé ailleurs) : on le crée à la volée pour que
    // le profil et l'historique aient toujours un socle.
    if (!doc.exists) {
      await _writeUserDocument(user);
      doc = await docRef.get();
    }
    return doc.exists ? AppUser.fromFirestore(doc) : null;
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = cred.user;
    if (user != null) await _writeUserDocument(user);
  }

  @override
  Future<void> registerWithEmail(RegistrationData data) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: data.email,
      password: data.password,
    );
    final user = cred.user;
    if (user == null) return;

    await user.updateDisplayName(data.fullName);
    await _writeUserDocument(
      user,
      firstName: data.firstName,
      lastName: data.lastName,
      birthDate: data.birthDate,
    );

    // Le compte n'est utilisable qu'une fois l'adresse confirmée.
    await user.sendEmailVerification();
  }

  @override
  Future<void> signInWithGoogle() async {
    final UserCredential cred;
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');
      cred = await _auth.signInWithPopup(provider);
    } else {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; // Annulé par l'utilisateur.
      final googleAuth = await googleUser.authentication;
      cred = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        ),
      );
    }

    final user = cred.user;
    if (user == null) return;

    // Google fournit un nom complet d'un seul tenant : on le répartit.
    final nameParts = (user.displayName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    await _writeUserDocument(
      user,
      firstName: nameParts.isNotEmpty ? nameParts.first : null,
      lastName: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : null,
    );
  }

  @override
  Future<void> signInAnonymously() async {
    final cred = await _auth.signInAnonymously();
    final user = cred.user;
    if (user != null) await _writeUserDocument(user);
  }

  @override
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null || user.emailVerified) return;
    await user.sendEmailVerification();
  }

  @override
  Future<void> reloadCurrentUser() async {
    await _auth.currentUser?.reload();
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Effacer le profil et les conversations avant le compte lui-même.
    final conversations = await _firestore
        .collection(AppConfig.colConversations)
        .where('userId', isEqualTo: user.uid)
        .get();
    final batch = _firestore.batch();
    for (final conversation in conversations.docs) {
      final messages = await conversation.reference
          .collection(AppConfig.colMessages)
          .get();
      for (final message in messages.docs) {
        batch.delete(message.reference);
      }
      batch.delete(conversation.reference);
    }
    batch.delete(_firestore.collection(AppConfig.colUsers).doc(user.uid));
    await batch.commit();

    await user.delete();
  }

  /// Crée le document `users/{uid}` s'il n'existe pas encore.
  ///
  /// Le client n'écrit jamais `plan` autrement qu'à `free` : les règles Firestore
  /// interdisent toute élévation de privilège depuis l'appli.
  Future<void> _writeUserDocument(
    User user, {
    String? firstName,
    String? lastName,
    DateTime? birthDate,
  }) async {
    final ref = _firestore.collection(AppConfig.colUsers).doc(user.uid);
    if ((await ref.get()).exists) return;

    await ref.set(
      AppUser(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
        firstName: firstName,
        lastName: lastName,
        birthDate: birthDate,
        photoURL: user.photoURL,
        createdAt: DateTime.now(),
      ).toFirestore(),
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (isDemoMode) {
    throw StateError('Firebase non disponible en mode démo');
  }
  return FirebaseAuthRepository(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firestoreProvider),
  );
});
