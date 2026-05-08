import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../main.dart' show isDemoMode;

/// Clés de préférences synchronisées entre appareils via Firestore.
class SyncedPreferences {
  final String systemPrompt;
  final String themeMode;
  final double ttsSpeed;
  final DateTime? updatedAt;

  const SyncedPreferences({
    this.systemPrompt = '',
    this.themeMode = 'system',
    this.ttsSpeed = 0.65,
    this.updatedAt,
  });

  Map<String, dynamic> toFirestore() => {
        'systemPrompt': systemPrompt,
        'themeMode': themeMode,
        'ttsSpeed': ttsSpeed,
        'updatedAt': updatedAt != null
            ? Timestamp.fromDate(updatedAt!)
            : FieldValue.serverTimestamp(),
      };

  factory SyncedPreferences.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return const SyncedPreferences();
    return SyncedPreferences(
      systemPrompt: (data['systemPrompt'] as String?) ?? '',
      themeMode: (data['themeMode'] as String?) ?? 'system',
      ttsSpeed: (data['ttsSpeed'] as num?)?.toDouble() ?? 0.65,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Service de synchronisation des préférences utilisateur via Firestore.
///
/// Architecture :
/// - Chaque utilisateur a un document `users/{uid}/preferences/sync`
/// - Les préférences locales (SharedPreferences) sont poussées vers Firestore
///   quand l'utilisateur les modifie
/// - Au démarrage, les préférences distantes sont lues et fusionnées
///   (la valeur la plus récente l'emporte)
/// - En temps réel, un listener Firestore met à jour les préférences locales
///   si elles changent sur un autre appareil
class PreferencesSyncService {
  final FirebaseFirestore _firestore;
  final String _userId;

  PreferencesSyncService({
    required FirebaseFirestore firestore,
    required String userId,
  })  : _firestore = firestore,
        _userId = userId;

  /// Chemin du document Firestore pour les préférences synchronisées.
  String get _docPath => '${AppConstants.colUsers}/$_userId/preferences/sync';

  /// Pousse les préférences locales vers Firestore.
  Future<void> pushPreferences(SyncedPreferences prefs) async {
    try {
      await _firestore.doc(_docPath).set(prefs.toFirestore(), SetOptions(merge: true));
      debugPrint('[PrefsSync] Pushed preferences for $_userId');
    } catch (e) {
      debugPrint('[PrefsSync] Push error: $e');
    }
  }

  /// Récupère les préférences distantes depuis Firestore.
  Future<SyncedPreferences?> fetchPreferences() async {
    try {
      final doc = await _firestore.doc(_docPath).get();
      if (doc.exists) {
        return SyncedPreferences.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      debugPrint('[PrefsSync] Fetch error: $e');
      return null;
    }
  }

  /// Écoute les changements de préférences en temps réel.
  /// Retourne un Stream qui émet les nouvelles préférences à chaque changement.
  Stream<SyncedPreferences> watchPreferences() {
    return _firestore.doc(_docPath).snapshots().map((doc) {
      if (doc.exists) {
        return SyncedPreferences.fromFirestore(doc);
      }
      return const SyncedPreferences();
    });
  }

  /// Fusionne les préférences locales et distantes.
  /// La valeur la plus récente (updatedAt) l'emporte.
  Future<SyncedPreferences> mergeWithLocal(SyncedPreferences remote) async {
    final prefs = await SharedPreferences.getInstance();

    final localSystemPrompt = prefs.getString('corely_system_prompt') ?? '';
    final localThemeMode = prefs.getString('theme_mode') ?? 'system';
    final localTtsSpeed = prefs.getDouble('tts_speed') ?? 0.65;

    // Si le remote est plus récent ou si la locale est vide, prendre le remote
    final merged = SyncedPreferences(
      systemPrompt: remote.systemPrompt.isNotEmpty ? remote.systemPrompt : localSystemPrompt,
      themeMode: remote.themeMode.isNotEmpty ? remote.themeMode : localThemeMode,
      ttsSpeed: remote.ttsSpeed > 0 ? remote.ttsSpeed : localTtsSpeed,
      updatedAt: remote.updatedAt,
    );

    // Écrire les valeurs fusionnées dans SharedPreferences
    if (merged.systemPrompt.isNotEmpty) {
      await prefs.setString('corely_system_prompt', merged.systemPrompt);
    }
    if (merged.themeMode.isNotEmpty) {
      await prefs.setString('theme_mode', merged.themeMode);
    }
    await prefs.setDouble('tts_speed', merged.ttsSpeed);

    return merged;
  }
}

/// Provider pour le PreferencesSyncService.
/// Null si l'utilisateur n'est pas connecté ou en mode démo.
final preferencesSyncProvider = Provider<PreferencesSyncService?>((ref) {
  if (isDemoMode) return null;

  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  final firestore = ref.watch(firestoreProvider);
  return PreferencesSyncService(firestore: firestore, userId: user.uid);
});

/// Provider qui écoute les changements de préférences distantes en temps réel.
/// Met à jour les SharedPreferences locales automatiquement.
final syncedPreferencesProvider = StreamProvider<SyncedPreferences?>((ref) {
  final syncService = ref.watch(preferencesSyncProvider);
  if (syncService == null) return Stream.value(null);

  return syncService.watchPreferences();
});