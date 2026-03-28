import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../secure_storage.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/auth/data/mock_auth_repository.dart';
import '../../main.dart' show isDemoMode;

// ── Firebase instances ────────────────────────────────────────────────────────
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final firebaseMessagingProvider = Provider<FirebaseMessaging>(
  (ref) => FirebaseMessaging.instance,
);

// ── Auth state ────────────────────────────────────────────────────────────────
// Mode DEMO: utilise le mock auth repository
final authStateProvider = StreamProvider<dynamic>(
  (ref) {
    if (isDemoMode) {
      return mockAuthRepository.authStateChanges;
    }
    return ref.watch(firebaseAuthProvider).authStateChanges();
  },
);

/// Utilisateur courant typé.
/// En mode DEMO renvoie un [AppUser], sinon un objet doté de `.uid`.
/// Les consommateurs doivent accéder à `.uid` / `.displayName` / `.email`.
final currentUserProvider = Provider<AppUserLike?>(
  (ref) {
    if (isDemoMode) {
      final user = mockAuthRepository.currentUser;
      if (user == null) return null;
      return AppUserLike(
        uid: user.uid,
        displayName: user.displayName,
        email: user.email,
      );
    }
    final firebaseUser = ref.watch(authStateProvider).valueOrNull;
    if (firebaseUser == null) return null;
    return AppUserLike(
      uid: (firebaseUser as dynamic).uid as String,
      displayName: (firebaseUser as dynamic).displayName as String?,
      email: (firebaseUser as dynamic).email as String?,
    );
  },
);

/// Lightweight typed wrapper so consumers don't deal with dynamic.
class AppUserLike {
  final String uid;
  final String? displayName;
  final String? email;
  const AppUserLike({required this.uid, this.displayName, this.email});
}

// ── Secure storage ────────────────────────────────────────────────────────────
final secureStorageProvider = Provider<SecureStorageService>(
  (ref) => SecureStorageService(),
);
