import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/feedback_event.dart';
import '../data/learning_repository.dart';

/// Collecteur de feedback utilisateur (explicite et implicite).
///
/// Le feedback explicite vient des interactions directes (thumbs up/down).
/// Le feedback implicite est deduit du comportement (barge-in, retry, etc.).
class FeedbackCollector {
  final LearningRepository _repo;

  FeedbackCollector(this._repo);

  // ── Feedback explicite ──────────────────────────────────────────────────────

  /// Thumbs up sur un message assistant.
  Future<void> thumbsUp(String messageId, {String? conversationId, String? content}) async {
    await _save(
      type: 'thumbs_up',
      messageId: messageId,
      conversationId: conversationId,
      content: content,
    );
  }

  /// Thumbs down sur un message assistant.
  Future<void> thumbsDown(String messageId, {String? conversationId, String? content, String? reason}) async {
    await _save(
      type: 'thumbs_down',
      messageId: messageId,
      conversationId: conversationId,
      content: content,
      metadata: reason != null ? {'reason': reason} : null,
    );
  }

  /// Feedback apres un slash command (succes ou echec).
  Future<void> slashResult({
    required String command,
    required bool success,
    String? error,
    String? conversationId,
  }) async {
    await _save(
      type: success ? 'slash_success' : 'slash_failure',
      conversationId: conversationId,
      metadata: {
        'command': command,
        if (error != null) 'error': error,
      },
    );
  }

  // ── Feedback implicite ────────────────────────────────────────────────────

  /// Barge-in pendant le TTS (l'utilisateur a interrompu la voix).
  Future<void> bargeIn({String? conversationId, String? transcript}) async {
    await _save(
      type: 'barge_in',
      conversationId: conversationId,
      content: transcript,
    );
  }

  /// L'utilisateur a corrige/reformule sa demande immediatement.
  Future<void> correction({String? conversationId, String? original, String? corrected}) async {
    await _save(
      type: 'correction',
      conversationId: conversationId,
      metadata: {
        if (original != null) 'original': original,
        if (corrected != null) 'corrected': corrected,
      },
    );
  }

  /// L'utilisateur a relance une requete similaire (probable echec de la premiere).
  Future<void> retry({String? conversationId, String? query}) async {
    await _save(
      type: 'retry',
      conversationId: conversationId,
      content: query,
    );
  }

  /// L'utilisateur a ouvert un lien source (recherche reussie).
  Future<void> linkOpened({String? conversationId, String? url}) async {
    await _save(
      type: 'link_opened',
      conversationId: conversationId,
      metadata: {'url': url},
    );
  }

  /// Reutilisation d'un slash command (succes implicite).
  Future<void> slashReused({String? conversationId, String? command}) async {
    await _save(
      type: 'slash_reused',
      conversationId: conversationId,
      metadata: {'command': command},
    );
  }

  /// Feature non utilisee apres onboarding (desinteret implicite).
  Future<void> featureIgnored({required String feature}) async {
    await _save(
      type: 'feature_ignored',
      metadata: {'feature': feature},
    );
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  Future<void> _save({
    required String type,
    String? messageId,
    String? conversationId,
    String? content,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final event = FeedbackEvent(
        id: const Uuid().v4(),
        type: type,
        messageId: messageId,
        conversationId: conversationId,
        content: content,
        metadata: metadata,
        createdAt: DateTime.now(),
      );
      await _repo.saveFeedback(event);
    } catch (e) {
      debugPrint('[FeedbackCollector] save error: $e');
    }
  }
}
