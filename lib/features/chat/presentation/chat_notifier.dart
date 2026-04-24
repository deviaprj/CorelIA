import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/ai_client.dart';
import '../data/chat_api_service.dart';
import '../data/firestore_chat_repository.dart';
import '../data/mock_chat_repository.dart';
import '../data/ollama_local_client.dart';
import '../data/quota_service.dart';
import '../data/search_service.dart';
import '../domain/conversation.dart';
import '../domain/message.dart';
import '../../../core/constants.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/secure_storage.dart';
import '../../monetization/subscription/subscription_service.dart';
import '../../../main.dart' show isDemoMode;

// ── Conversations stream ───────────────────────────────────────────────────
final conversationsStreamProvider =
    StreamProvider.family<List<Conversation>, String>(
  (ref, userId) {
    if (isDemoMode) {
      return mockChatRepository.watchConversations(userId);
    }
    return ref.watch(chatRepositoryProvider).watchConversations(userId);
  },
);

// ── Messages stream ────────────────────────────────────────────────────────
final messagesStreamProvider = StreamProvider.family<List<Message>, String>(
  (ref, convId) {
    if (isDemoMode) {
      return mockChatRepository.watchMessages(convId);
    }
    return ref.watch(chatRepositoryProvider).watchMessages(convId);
  },
);

// ── Services providers ─────────────────────────────────────────────────────
final chatApiServiceProvider = Provider((ref) => ChatApiService());
final searchServiceProvider = Provider((ref) => SearchService());
final ollamaLocalClientProvider = Provider((ref) => OllamaLocalClient());

// ── Chat state ─────────────────────────────────────────────────────────────
class ChatState {
  final List<Message> messages;
  final bool isStreaming;
  final String? error;
  final int? remainingRequests;
  final bool isSearching; // Indicateur visuel recherche web en cours
  final bool useSearch; // Toggle recherche web activée

  const ChatState({
    this.messages = const [],
    this.isStreaming = false,
    this.error,
    this.remainingRequests,
    this.isSearching = false,
    this.useSearch = false,
  });

  ChatState copyWith({
    List<Message>? messages,
    bool? isStreaming,
    String? error,
    int? remainingRequests,
    bool? isSearching,
    bool? useSearch,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        error: error,
        remainingRequests: remainingRequests ?? this.remainingRequests,
        isSearching: isSearching ?? this.isSearching,
        useSearch: useSearch ?? this.useSearch,
      );
}

class ChatNotifier extends FamilyNotifier<ChatState, String> {
  // conversationId = arg
  OllamaLocalClient? _ollamaClient;
  String? _ollamaUrl;

  @override
  ChatState build(String conversationId) {
    // S'abonner au stream Firestore
    ref.listen(messagesStreamProvider(conversationId), (_, next) {
      if (next.hasValue && !state.isStreaming) {
        state = state.copyWith(messages: next.value!);
      }
    });

    // Détection asynchrone Ollama local (non bloquante)
    _detectOllamaLocal();

    return const ChatState();
  }

  Future<void> _detectOllamaLocal() async {
    final client = ref.read(ollamaLocalClientProvider);
    final url = await client.detectLocalServer();
    if (url != null) {
      _ollamaClient = client;
      _ollamaUrl = url;
      debugPrint('[ChatNotifier] Ollama local détecté : $url');
    }
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 10000 || state.isStreaming) return;

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
        debugPrint('[Quota] Cloud Function unavailable: ${e.message}');
      } catch (e) {
        debugPrint('[Quota] Error checking quota: $e');
      }
    }

    // 2. Sauvegarder message utilisateur
    final userMsg = isDemoMode
        ? await mockChatRepository.addMessage(
            conversationId: arg,
            role: Role.user,
            content: trimmed,
          )
        : await ref.read(chatRepositoryProvider).addMessage(
            conversationId: arg,
            role: Role.user,
            content: trimmed,
          );

    // 3. Préparer l'appel streaming
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isStreaming: true,
      error: null,
      isSearching: state.useSearch,
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
      final stream = await _buildStream(userMsg, isPro);

      final buffer = StringBuffer();
      final updatedMessages = List<Message>.from(state.messages);
      final placeholderIndex =
          updatedMessages.indexWhere((m) => m.id == placeholderId);

      await for (final token in stream) {
        buffer.write(token);
        if (placeholderIndex != -1) {
          updatedMessages[placeholderIndex] =
              updatedMessages[placeholderIndex]
                  .copyWith(content: buffer.toString());
          state = state.copyWith(messages: List.unmodifiable(updatedMessages));
        }
      }

      // 6. Sauvegarder la réponse finale
      final model = isPro ? AppConstants.mistralModel : AppConstants.deepSeekModel;
      if (isDemoMode) {
        await mockChatRepository.updateMessageContent(
            arg, placeholderId, buffer.toString());
      } else {
        await ref.read(chatRepositoryProvider).addMessage(
          conversationId: arg,
          role: Role.assistant,
          content: buffer.toString(),
          model: model,
        );
      }
    } on AiException catch (e) {
      state = state.copyWith(error: e.message);
    } on ChatApiException catch (e) {
      state = state.copyWith(error: e.message);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(
        isStreaming: false,
        isSearching: false,
        messages: state.messages.where((m) => m.id != placeholderId).toList(),
      );
    }
  }

  Future<Stream<String>> _buildStream(Message userMsg, bool isPro) async {
    final history = state.messages
        .where((m) => m.role != Role.system && !m.isStreaming)
        .toList()
        .reversed
        .take(AppConstants.maxContextMessages)
        .toList()
        .reversed
        .map((m) => m.toApiMap())
        .toList();

    // Stratégie 1 : Backend FastAPI (recommandé)
    final connectivity = await Connectivity().checkConnectivity();
    final hasNetwork = connectivity != ConnectivityResult.none;

    if (hasNetwork && !isDemoMode) {
      try {
        final apiService = ref.read(chatApiServiceProvider);
        return apiService.streamChat(
          conversationId: arg,
          history: history,
          useSearch: state.useSearch,
          useOllamaLocal: _ollamaUrl != null,
          ollamaLocalUrl: _ollamaUrl,
          maxTokens: isPro ? AppConstants.proMaxTokens : AppConstants.maxTokens,
        );
      } catch (e) {
        debugPrint('[ChatNotifier] Backend indisponible : $e');
        // Fallback silencieux vers les API directes
      }
    }

    // Stratégie 2 : Ollama local (offline / réseau local)
    if (_ollamaClient != null && _ollamaUrl != null) {
      return _ollamaClient!.streamChat(
        messages: history,
        model: 'llama3.2',
        maxTokens: isPro ? AppConstants.proMaxTokens : AppConstants.maxTokens,
      );
    }

    // Stratégie 3 : API directes (fallback final)
    return _getDirectAiStream(history, isPro);
  }

  Stream<String> _getDirectAiStream(
    List<Map<String, dynamic>> history,
    bool isPro,
  ) {
    if (isPro) {
      final key = AppConstants.openRouterApiKey;
      if (key.isNotEmpty) {
        return OpenRouterClient(apiKey: key).streamChat(
          messages: history,
          model: AppConstants.mistralModel,
          maxTokens: AppConstants.proMaxTokens,
        );
      }
    }
    // DeepSeek gratuit (fallback ultime)
    return DeepSeekClient(apiKey: AppConstants.deepSeekApiKey)
        .streamChat(messages: history);
  }

  void toggleSearch() {
    state = state.copyWith(useSearch: !state.useSearch);
  }

  void clearError() => state = state.copyWith(error: null);
}

final chatNotifierProvider =
    NotifierProviderFamily<ChatNotifier, ChatState, String>(
  ChatNotifier.new,
);
