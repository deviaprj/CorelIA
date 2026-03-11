import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:uuid/uuid.dart';
import '../domain/app_user.dart';
import '../../../core/constants.dart';
import '../../../core/providers/firebase_providers.dart';

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
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  FirebaseAuthRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  })  : _auth = auth,
        _firestore = firestore;

  @override
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  @override
  Future<AppUser?> getCurrentAppUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final doc = await _firestore
        .collection(AppConstants.colUsers)
        .doc(user.uid)
        .get();
    if (!doc.exists) return null;
    return AppUser.fromFirestore(doc);
  }

  @override
  Future<void> signInWithEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  @override
  Future<void> registerWithEmail(
      String email, String password, String name) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (cred.user != null) {
      await cred.user!.updateDisplayName(name);
      await _createUserDocument(cred.user!);
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    UserCredential cred;
    if (kIsWeb) {
      // Web : popup Firebase Auth natif (pas besoin de google_sign_in)
      final provider = GoogleAuthProvider();
      provider.addScope('email');
      cred = await _auth.signInWithPopup(provider);
    } else {
      // Mobile : google_sign_in
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; // annulé
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      cred = await _auth.signInWithCredential(credential);
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
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    // Suppression RGPD — les données Firestore sont nettoyées par Cloud Function
    await _firestore.collection(AppConstants.colUsers).doc(uid).delete();
    await _auth.currentUser?.delete();
  }

  Future<void> _createUserDocument(User user) async {
    final ref = _firestore.collection(AppConstants.colUsers).doc(user.uid);
    final exists = (await ref.get()).exists;
    if (exists) return;

    final appUser = AppUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName ?? 'Utilisateur',
      photoURL: user.photoURL,
      createdAt: DateTime.now(),
      referralCode: const Uuid().v4().substring(0, 8).toUpperCase(),
    );
    await ref.set(appUser.toFirestore());
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firestoreProvider),
  );
});
