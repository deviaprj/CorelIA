import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/ai_client.dart';
import '../data/firestore_chat_repository.dart';
import '../data/quota_service.dart';
import '../domain/conversation.dart';
import '../domain/message.dart';
import '../../../core/constants.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/secure_storage.dart';
import '../../monetization/subscription/subscription_service.dart';

// ── Conversations stream ───────────────────────────────────────────────────────
final conversationsStreamProvider =
    StreamProvider.family<List<Conversation>, String>(
  (ref, userId) =>
      ref.watch(chatRepositoryProvider).watchConversations(userId),
);

// ── Messages stream ───────────────────────────────────────────────────────────
final messagesStreamProvider =
    StreamProvider.family<List<Message>, String>(
  (ref, convId) =>
      ref.watch(chatRepositoryProvider).watchMessages(convId),
);

// ── Chat state (streaming en cours) ──────────────────────────────────────────
class ChatState {
  final List<Message> messages;
  final bool isStreaming;
  final String? error;
  final int? remainingRequests;

  const ChatState({
    this.messages = const [],
    this.isStreaming = false,
    this.error,
    this.remainingRequests,
  });

  ChatState copyWith({
    List<Message>? messages,
    bool? isStreaming,
    String? error,
    int? remainingRequests,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        error: error,
        remainingRequests: remainingRequests ?? this.remainingRequests,
      );
}

class ChatNotifier extends FamilyNotifier<ChatState, String> {
  // conversationId = arg

  @override
  ChatState build(String conversationId) {
    // S'abonner au stream Firestore
    ref.listen(messagesStreamProvider(conversationId), (_, next) {
      if (next.hasValue && !state.isStreaming) {
        state = state.copyWith(messages: next.value!);
      }
    });
    return const ChatState();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || state.isStreaming) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    // 1. Vérifier quota (Cloud Function server-side)
    final isPro = await ref.read(isProProvider.future).catchError((_) => false);
    if (!isPro) {
      try {
        final remaining =
            await ref.read(quotaServiceProvider).checkAndDecrement();
        state = state.copyWith(remainingRequests: remaining);
      } on QuotaExceededException {
        state = state.copyWith(
          error: 'quota_exceeded',
          isStreaming: false,
        );
        return;
      } on FirebaseFunctionsException catch (e) {
        // Cloud Function indisponible (non déployée ou erreur réseau) :
        // on continue sans quota en mode dégradé, mais on log
        debugPrint('[Quota] Cloud Function unavailable: ${e.message}');
      } catch (e) {
        // Autre erreur - continuer en mode dégradé
        debugPrint('[Quota] Error checking quota: $e');
      }
    }

    // 2. Sauvegarder message utilisateur
    final repo = ref.read(chatRepositoryProvider);
    final userMsg = await repo.addMessage(
      conversationId: arg,
      role: Role.user,
      content: text,
    );

    // 3. Préparer l'appel streaming
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isStreaming: true,
      error: null,
    );

    // 4. Créer placeholder assistant
    final placeholderId = '${userMsg.id}_stream';
    final placeholder = Message(
      id: placeholderId,
      conversationId: arg,
      role: Role.assistant,
      content: '',
      isStreaming: true,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      messages: [...state.messages, placeholder],
    );

    // 5. Streamer la réponse IA
    try {
      final apiKey = await _getApiKey(isPro);
      if (apiKey.isEmpty) {
        throw const AiException(
          'Clé API non configurée. Ajoutez-la dans les paramètres.',
          statusCode: 401,
        );
      }
      // Prendre les derniers messages (les plus récents) pour le contexte IA
      final history = state.messages
          .where((m) => m.role != Role.system && !m.isStreaming)
          .toList()
          .reversed
          .take(AppConstants.maxContextMessages)
          .toList()
          .reversed
          .map((m) => m.toApiMap())
          .toList();

      final buffer = StringBuffer();
      final stream = _getAiStream(apiKey, history, isPro);

      // Optimisation: liste mutable pour éviter la recréation O(n²) à chaque token
      final updatedMessages = List<Message>.from(state.messages);
      final placeholderIndex = updatedMessages.indexWhere((m) => m.id == placeholderId);

      await for (final token in stream) {
        buffer.write(token);
        if (placeholderIndex != -1) {
          updatedMessages[placeholderIndex] = updatedMessages[placeholderIndex]
              .copyWith(content: buffer.toString());
          state = state.copyWith(messages: List.unmodifiable(updatedMessages));
        }
      }

      // 6. Sauvegarder la réponse finale
      final model = isPro ? AppConstants.mistralModel : AppConstants.deepSeekModel;
      await repo.addMessage(
        conversationId: arg,
        role: Role.assistant,
        content: buffer.toString(),
        model: model,
      );
    } on AiException catch (e) {
      state = state.copyWith(error: e.message);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      // Retirer le placeholder streaming
      state = state.copyWith(
        isStreaming: false,
        messages: state.messages.where((m) => m.id != placeholderId).toList(),
      );
    }
  }

  void clearError() => state = state.copyWith(error: null);

  Stream<String> _getAiStream(
    String apiKey,
    List<Map<String, dynamic>> history,
    bool isPro,
  ) {
    if (apiKey.isEmpty) {
      return Stream.error(
        const AiException('Clé API manquante', statusCode: 401),
      );
    }
    if (isPro) {
      return OpenRouterClient(apiKey: apiKey).streamChat(
        messages: history,
        model: AppConstants.mistralModel,
        maxTokens: AppConstants.proMaxTokens,
      );
    }
    return DeepSeekClient(apiKey: apiKey).streamChat(messages: history);
  }

  Future<String> _getApiKey(bool isPro) async {
    if (isPro) return AppConstants.openRouterApiKey;
    // Vérifier clé personnelle puis clé app
    final storage = ref.read(secureStorageProvider);
    final personal = await storage.read(StorageKeys.apiKeyDeepSeek);
    if (personal != null && personal.isNotEmpty) return personal;
    return AppConstants.deepSeekApiKey;
  }
}

final chatNotifierProvider =
    NotifierProviderFamily<ChatNotifier, ChatState, String>(
  ChatNotifier.new,
);
