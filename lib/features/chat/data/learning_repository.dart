import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants.dart';
import '../domain/learning_pattern.dart';
import '../domain/feedback_event.dart';

/// Repository pour persister les patterns d'apprentissage et les feedbacks.
///
/// Les donnees sont stockees dans Firestore sous :
/// - users/{uid}/learning_patterns
/// - users/{uid}/feedback_events
///
/// En mode DEMO (sans Firestore), les donnees sont stockees en memoire.
class LearningRepository {
  final FirebaseFirestore? _db;
  final String? _userId;

  // Mode DEMO : stockage en memoire
  final List<LearningPattern> _memoryPatterns = [];
  final List<FeedbackEvent> _memoryEvents = [];

  LearningRepository({FirebaseFirestore? db, String? userId})
      : _db = db,
        _userId = userId;

  bool get _isDemo => _db == null || _userId == null || _userId!.isEmpty;

  // ── Learning Patterns ───────────────────────────────────────────────────────

  Future<void> savePattern(LearningPattern pattern) async {
    if (_isDemo) {
      _memoryPatterns.add(pattern);
      debugPrint('[LearningRepo] Pattern saved (memory): ${pattern.type}');
      return;
    }
    try {
      await _db!
          .collection(AppConstants.colUsers)
          .doc(_userId)
          .collection('learning_patterns')
          .doc(pattern.id)
          .set(pattern.toFirestore());
    } catch (e) {
      debugPrint('[LearningRepo] savePattern error: $e');
    }
  }

  Future<List<LearningPattern>> getPatternsByType(String type, {int limit = 50}) async {
    if (_isDemo) {
      return _memoryPatterns
          .where((p) => p.type == type)
          .toList()
          .reversed
          .take(limit)
          .toList();
    }
    try {
      final snap = await _db!
          .collection(AppConstants.colUsers)
          .doc(_userId)
          .collection('learning_patterns')
          .where('type', isEqualTo: type)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) => LearningPattern.fromFirestore(d.data())).toList();
    } catch (e) {
      debugPrint('[LearningRepo] getPatternsByType error: $e');
      return const [];
    }
  }

  Future<void> deletePattern(String patternId) async {
    if (_isDemo) {
      _memoryPatterns.removeWhere((p) => p.id == patternId);
      return;
    }
    try {
      await _db!
          .collection(AppConstants.colUsers)
          .doc(_userId)
          .collection('learning_patterns')
          .doc(patternId)
          .delete();
    } catch (e) {
      debugPrint('[LearningRepo] deletePattern error: $e');
    }
  }

  // ── Feedback Events ─────────────────────────────────────────────────────────

  Future<void> saveFeedback(FeedbackEvent event) async {
    if (_isDemo) {
      _memoryEvents.add(event);
      debugPrint('[LearningRepo] Feedback saved (memory): ${event.type}');
      return;
    }
    try {
      await _db!
          .collection(AppConstants.colUsers)
          .doc(_userId)
          .collection('feedback_events')
          .doc(event.id)
          .set(event.toFirestore());
    } catch (e) {
      debugPrint('[LearningRepo] saveFeedback error: $e');
    }
  }

  Future<List<FeedbackEvent>> getRecentFeedback({int limit = 100}) async {
    if (_isDemo) {
      return _memoryEvents.reversed.take(limit).toList();
    }
    try {
      final snap = await _db!
          .collection(AppConstants.colUsers)
          .doc(_userId)
          .collection('feedback_events')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) => FeedbackEvent.fromFirestore(d.data())).toList();
    } catch (e) {
      debugPrint('[LearningRepo] getRecentFeedback error: $e');
      return const [];
    }
  }

  Future<void> deleteAllUserData() async {
    if (_isDemo) {
      _memoryPatterns.clear();
      _memoryEvents.clear();
      return;
    }
    try {
      final batch = _db!.batch();
      final patterns = await _db!
          .collection(AppConstants.colUsers)
          .doc(_userId)
          .collection('learning_patterns')
          .get();
      for (final doc in patterns.docs) {
        batch.delete(doc.reference);
      }
      final events = await _db!
          .collection(AppConstants.colUsers)
          .doc(_userId)
          .collection('feedback_events')
          .get();
      for (final doc in events.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[LearningRepo] deleteAllUserData error: $e');
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Generate a unique ID for patterns/events.
  static String generateId() => const Uuid().v4();
}
