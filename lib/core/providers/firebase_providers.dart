import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../secure_storage.dart';
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

// Mode DEMO: retourne AppUser ou User selon le mode
final currentUserProvider = Provider<dynamic>(
  (ref) {
    if (isDemoMode) {
      return mockAuthRepository.currentUser;
    }
    return ref.watch(authStateProvider).valueOrNull;
  },
);

// ── Secure storage ────────────────────────────────────────────────────────────
final secureStorageProvider = Provider<SecureStorageService>(
  (ref) => SecureStorageService(),
);
