import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/providers/firebase_providers.dart';

/// Gère le système de parrainage : appliquer un code, compter les filleuls,
/// et attribuer les bonus de requêtes.
class ReferralService {
  final FirebaseFirestore _firestore;

  ReferralService({required FirebaseFirestore firestore})
      : _firestore = firestore;

  /// Applique [code] pour l'utilisateur [userId].
  /// Retourne `true` si le code est valide et appliqué, `false` sinon.
  Future<bool> applyReferralCode(String userId, String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) return false;

    // Chercher le parrain qui possède ce code
    final snap = await _firestore
        .collection(AppConstants.colUsers)
        .where('referralCode', isEqualTo: trimmed)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return false;

    final referrerDoc = snap.docs.first;
    // On ne peut pas se parrainer soi-même
    if (referrerDoc.id == userId) return false;

    // Vérifier que l'utilisateur n'a pas déjà un parrain
    final userDoc = await _firestore
        .collection(AppConstants.colUsers)
        .doc(userId)
        .get();
    final userData = userDoc.data();
    if (userData != null && userData['referredBy'] != null) return false;

    final batch = _firestore.batch();

    // Marquer le filleul comme parrainé
    batch.update(
      _firestore.collection(AppConstants.colUsers).doc(userId),
      {'referredBy': trimmed},
    );

    // Enregistrer dans la collection referrals
    batch.set(
      _firestore.collection(AppConstants.colReferrals).doc(),
      {
        'referrerId': referrerDoc.id,
        'referredId': userId,
        'code': trimmed,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

    // Bonus : +5 requêtes quotidiennes pour le parrain
    batch.update(
      _firestore.collection(AppConstants.colUsers).doc(referrerDoc.id),
      {'dailyRequests': FieldValue.increment(-5)},
    );

    // Bonus : +5 requêtes quotidiennes pour le filleul
    batch.update(
      _firestore.collection(AppConstants.colUsers).doc(userId),
      {'dailyRequests': FieldValue.increment(-5)},
    );

    await batch.commit();
    return true;
  }

  /// Retourne le nombre de filleuls parrainés par [userId].
  Future<int> getReferralCount(String userId) async {
    final snap = await _firestore
        .collection(AppConstants.colReferrals)
        .where('referrerId', isEqualTo: userId)
        .get();
    return snap.docs.length;
  }

  /// Récupère le code de parrainage de l'utilisateur [userId].
  Future<String?> getReferralCode(String userId) async {
    final doc = await _firestore
        .collection(AppConstants.colUsers)
        .doc(userId)
        .get();
    return doc.data()?['referralCode'] as String?;
  }

  /// Vérifie si l'utilisateur a déjà utilisé un code parrain.
  Future<bool> hasReferrer(String userId) async {
    final doc = await _firestore
        .collection(AppConstants.colUsers)
        .doc(userId)
        .get();
    return doc.data()?['referredBy'] != null;
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final referralServiceProvider = Provider<ReferralService>((ref) {
  return ReferralService(firestore: ref.watch(firestoreProvider));
});

/// Nombre de filleuls de l'utilisateur courant.
final referralCountProvider = FutureProvider<int>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return 0;
  return ref.watch(referralServiceProvider).getReferralCount(user.uid);
});

/// Code de parrainage de l'utilisateur courant.
final referralCodeProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.watch(referralServiceProvider).getReferralCode(user.uid);
});

/// Indique si l'utilisateur a déjà un parrain.
final hasReferrerProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  return ref.watch(referralServiceProvider).hasReferrer(user.uid);
});
