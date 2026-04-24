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
  final bool isSearching;
  final bool useSearch;

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
  OllamaLocalClient? _ollamaClient;
  String? _ollamaUrl;

  @override
  ChatState build(String conversationId) {
    ref.listen(messagesStreamProvider(conversationId), (_, next) {
      // Hors streaming uniquement : sync depuis le repo Firestore/mock.
      // Pendant le streaming, on gère tout localement pour éviter les
      // conflits entre placeholders locaux et sync repo.
      if (next.hasValue && !state.isStreaming) {
        state = state.copyWith(messages: next.value!);
      }
    });
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

    final isPro = await ref.read(isProProvider.future).catchError((_) => false);
    if (!isPro) {
      try {
        final remaining =
            await ref.read(quotaServiceProvider).checkAndDecrement();
        state = state.copyWith(remainingRequests: remaining);
      } on QuotaExceededException {
        state = state.copyWith(error: 'quota_exceeded', isStreaming: false);
        return;
      } on FirebaseFunctionsException catch (e) {
        debugPrint('[Quota] Cloud Function unavailable: ${e.message}');
      } catch (e) {
        debugPrint('[Quota] Error checking quota: $e');
      }
    }

    // 1. Persister le message utilisateur dans le repo
    final userMsg = isDemoMode
        ? await mockChatRepository.addMessage(
            conversationId: arg, role: Role.user, content: trimmed)
        : await ref.read(chatRepositoryProvider).addMessage(
            conversationId: arg, role: Role.user, content: trimmed);

    // 2. ref.listen va sync le message utilisateur depuis le repo,
    //    mais en attendant on s'assure que le state le contient pour
    //    que le placeholder s'ajoute correctement.
    final baseMessages = state.messages.any((m) => m.id == userMsg.id)
        ? state.messages
        : [...state.messages, userMsg];

    // 3. Créer le placeholder de streaming (local uniquement)
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
      messages: [...baseMessages, placeholder],
      isStreaming: true,
      error: null,
      isSearching: state.useSearch,
    );

    final buffer = StringBuffer();
    // Liste mutable interne pour éviter les allocations O(n) à chaque token
    var mutableMessages = List<Message>.from(state.messages);
    var placeholderIndex = mutableMessages.indexWhere((m) => m.id == placeholderId);

    // Throttle : mettre à jour l'état Riverpod uniquement tous les 8 tokens
    // ou tous les 150ms pour réduire les rebuilds UI
    var tokenCount = 0;
    const throttleEvery = 8;
    Timer? throttleTimer;
    var hasPendingUpdate = false;

    void flushState() {
      if (hasPendingUpdate && placeholderIndex != -1) {
        mutableMessages[placeholderIndex] =
            mutableMessages[placeholderIndex].copyWith(content: buffer.toString());
        state = state.copyWith(messages: List<Message>.from(mutableMessages));
        hasPendingUpdate = false;
      }
    }

    try {
      final stream = await _buildStream(userMsg, isPro);

      await for (final token in stream) {
        buffer.write(token);
        tokenCount++;
        hasPendingUpdate = true;

        if (tokenCount % throttleEvery == 0) {
          flushState();
        } else if (throttleTimer == null || !throttleTimer.isActive) {
          throttleTimer = Timer(const Duration(milliseconds: 150), flushState);
        }
      }

      flushState();
      throttleTimer?.cancel();

      // 4. Stream terminé : transformer le placeholder en vrai message final
      //    (pas de suppression — on remplace isStreaming=false et on persiste)
      final finalContent = buffer.toString();
      final model = isPro ? AppConstants.mistralModel : AppConstants.deepSeekModel;

      if (placeholderIndex != -1) {
        mutableMessages[placeholderIndex] = mutableMessages[placeholderIndex]
            .copyWith(content: finalContent, isStreaming: false);
      }

      state = state.copyWith(
        messages: List<Message>.from(mutableMessages),
        isStreaming: false,
        isSearching: false,
      );

      // 5. Persister la réponse finale dans le repo pour que ref.listen
      //    la garde sync si l'utilisateur revient sur la conversation
      if (isDemoMode) {
        await mockChatRepository.addMessage(
          conversationId: arg,
          role: Role.assistant,
          content: finalContent,
          model: model,
        );
      } else {
        await ref.read(chatRepositoryProvider).addMessage(
          conversationId: arg,
          role: Role.assistant,
          content: finalContent,
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
      // S'assurer que isStreaming est false et que le placeholder
      // n'est pas orphelin (si une erreur est survenue en cours de stream)
      if (state.isStreaming) {
        state = state.copyWith(
          isStreaming: false,
          isSearching: false,
          messages: state.messages
              .where((m) => !m.isStreaming)
              .toList(),
        );
      }
    }
  }

  Future<Stream<String>> _buildStream(Message userMsg, bool isPro) async {
    // ── 1. Construire l'historique ───────────────────────────────────────
    final historyMessages = state.messages
        .where((m) => m.role != Role.system && !m.isStreaming)
        .toList()
        .reversed
        .take(AppConstants.maxContextMessages)
        .toList()
        .reversed
        .toList();

    // ── 2. Recherche web directe (autonome, pas de backend) ────────────
    if (state.useSearch) {
      try {
        state = state.copyWith(isSearching: true);
        final searchService = ref.read(searchServiceProvider);
        final results = await searchService.searchDirect(userMsg.content);
        final searchContext = searchService.formatForAi(results, userMsg.content);

        // Injecter les résultats comme un message système au début
        historyMessages.insert(0, Message(
          id: 'search_context_${DateTime.now().millisecondsSinceEpoch}',
          conversationId: arg,
          role: Role.system,
          content:
              'Tu es un assistant IA avec accès à internet. '
              'Utilise les résultats de recherche ci-dessous pour répondre '
              'à la question de l\'utilisateur. Cite tes sources quand c\'est pertinent.\n\n'
              '$searchContext',
          createdAt: DateTime.now(),
        ));

        debugPrint('[ChatNotifier] Recherche web directe : ${results.length} résultats');
      } catch (e) {
        debugPrint('[ChatNotifier] Recherche web échouée : $e');
      } finally {
        state = state.copyWith(isSearching: false);
      }
    }

    final historyMaps = historyMessages.map((m) => m.toApiMap()).toList();

    // ── 3. Ollama local (prioritaire si disponible) ────────────────────
    if (_ollamaClient != null && _ollamaUrl != null) {
      return _ollamaClient!.streamChat(
        messages: historyMaps,
        model: 'llama3.2',
        maxTokens: isPro ? AppConstants.proMaxTokens : AppConstants.maxTokens,
      );
    }

    // ── 4. DeepSeek / OpenRouter direct (100% autonome) ───────────────
    return _getDirectAiStream(historyMaps, isPro);
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
    final deepSeekKey = AppConstants.deepSeekApiKey;
    if (deepSeekKey.isEmpty && isDemoMode) {
      // Mode DEMO sans clé API → réponse mock pour tests
      return _mockResponseStream();
    }
    return DeepSeekClient(apiKey: deepSeekKey)
        .streamChat(messages: history);
  }

  /// Réponse mock pour tests en mode DEMO
  Stream<String> _mockResponseStream() async* {
    const response =
        'Bonjour ! Je suis AironBot, votre assistant IA. '
        'En mode démo, je fonctionne sans connexion externe. '
        'Posez-moi des questions sur n\'importe quel sujet !';
    for (final word in response.split(' ')) {
      yield '$word ';
      await Future.delayed(const Duration(milliseconds: 80));
    }
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
