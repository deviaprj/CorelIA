import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/app_user.dart';
import '../../../core/providers/firebase_providers.dart';

/// Contrat d'authentification (implémenté par Firebase, mocké en démo).
abstract class AuthRepository {
  Stream<User?> get authStateChanges;
  Future<AppUser?> getCurrentAppUser();
  Future<void> signInWithEmail(String email, String password);
  Future<void> registerWithEmail(String email, String password, String name);
  Future<void> signInWithGoogle();
  Future<void> signInAnonymously();
  Future<void> signOut();
  Future<void> deleteAccount();
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({required FirebaseAuth auth, required FirebaseFirestore firestore})
      : _auth = auth,
        _firestore = firestore;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  @override
  Future<AppUser?> getCurrentAppUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final doc = await _firestore.collection(AppConfig.colUsers).doc(user.uid).get();
    if (!doc.exists) return null;
    return AppUser.fromFirestore(doc);
  }

  @override
  Future<void> signInWithEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  @override
  Future<void> registerWithEmail(String email, String password, String name) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = cred.user;
    if (user != null) {
      await user.updateDisplayName(name);
      await _createUserDocument(user);
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    final UserCredential cred;
    if (kIsWeb) {
      final provider = GoogleAuthProvider()..addScope('email');
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
    if (cred.additionalUserInfo?.isNewUser ?? false) {
      await _createUserDocument(cred.user!);
    }
  }

  @override
  Future<void> signInAnonymously() async {
    final cred = await _auth.signInAnonymously();
    await _createUserDocument(cred.user!);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection(AppConfig.colUsers).doc(user.uid).delete();
    await user.delete();
  }

  Future<void> _createUserDocument(User user) async {
    final ref = _firestore.collection(AppConfig.colUsers).doc(user.uid);
    if ((await ref.get()).exists) return;
    await ref.set(
      AppUser(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName ?? 'Utilisateur',
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
