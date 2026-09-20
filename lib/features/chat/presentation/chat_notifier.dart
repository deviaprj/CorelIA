import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/ai_client.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/message.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/firebase_providers.dart';
import '../data/chat_repository.dart';
import '../data/model_router.dart';
import '../data/search_service.dart';
import '../data/web_search_trigger.dart';

/// État de l'écran de chat.
class ChatState {
  const ChatState({
    this.messages = const [],
    this.isStreaming = false,
    this.isSearching = false,
    this.useSearch = false,
    this.error,
  });

  final List<Message> messages;
  final bool isStreaming;
  final bool isSearching;

  /// Recherche Internet forcée par l'utilisateur.
  final bool useSearch;
  final String? error;

  ChatState copyWith({
    List<Message>? messages,
    bool? isStreaming,
    bool? isSearching,
    bool? useSearch,
    String? error,
    bool clearError = false,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        isSearching: isSearching ?? this.isSearching,
        useSearch: useSearch ?? this.useSearch,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Orchestre une conversation unique : persistance, recherche web et streaming IA.
class ChatNotifier extends Notifier<ChatState> {
  String? _conversationId;
  StreamSubscription<List<Message>>? _subscription;

  @override
  ChatState build() {
    ref.onDispose(() => _subscription?.cancel());
    return const ChatState();
  }

  /// Prépare la conversation courante (reprend la plus récente ou en crée une).
  Future<void> start() async {
    if (_conversationId != null) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final repository = ref.read(chatRepositoryProvider);
    final conversations = await repository.watchConversations(user.uid).first;
    final conversation = conversations.isNotEmpty
        ? conversations.first
        : await repository.createConversation(userId: user.uid);

    _conversationId = conversation.id;
    _subscription = repository.watchMessages(conversation.id).listen((messages) {
      if (!state.isStreaming) state = state.copyWith(messages: messages);
    });
  }

  void toggleSearch() => state = state.copyWith(useSearch: !state.useSearch);

  void clearError() => state = state.copyWith(clearError: true);

  /// Envoie un message et streame la réponse de l'IA.
  Future<void> sendMessage(
    String text, {
    List<Attachment> attachments = const [],
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;
    if (state.isStreaming) return;

    await start();
    final conversationId = _conversationId;
    if (conversationId == null) return;

    final totalSize = attachments.fold<int>(0, (sum, a) => sum + a.sizeBytes);
    if (totalSize > AppConfig.maxAttachmentBytes) {
      state = state.copyWith(
        error: 'Pièce jointe trop volumineuse '
            '(${AppConfig.maxAttachmentBytes ~/ (1024 * 1024)} Mo max).',
      );
      return;
    }

    final effectiveText =
        trimmed.isEmpty ? 'Analyse ce document' : trimmed;
    final repository = ref.read(chatRepositoryProvider);

    // 1. Persister le message utilisateur.
    final userMessage = await repository.addMessage(
      conversationId: conversationId,
      role: Role.user,
      content: effectiveText,
      attachments: attachments,
      fileContext: _buildFileContext(attachments),
    );

    // 2. Placeholder de streaming (local, non persisté).
    final placeholderId = '${userMessage.id}_stream';
    final baseMessages = state.messages.any((m) => m.id == userMessage.id)
        ? state.messages
        : [...state.messages, userMessage];
    state = state.copyWith(
      messages: [
        ...baseMessages,
        Message(
          id: placeholderId,
          conversationId: conversationId,
          role: Role.assistant,
          content: '',
          isStreaming: true,
          createdAt: DateTime.now(),
        ),
      ],
      isStreaming: true,
      clearError: true,
    );

    // 3. Recherche Internet éventuelle.
    List<WebSearchResult>? searchResults;
    InstantAnswer? instantAnswer;
    final shouldSearch =
        state.useSearch || WebSearchTrigger.needsWebSearch(effectiveText);
    if (shouldSearch) {
      state = state.copyWith(isSearching: true);
      try {
        final searchService = ref.read(searchServiceProvider);
        final query = WebSearchTrigger.extractSearchQuery(effectiveText);
        searchResults = await searchService.search(query);
        if (searchResults.isNotEmpty) {
          instantAnswer = await searchService.getInstantAnswer(query);
        }
      } catch (e) {
        debugPrint('[Chat] Recherche web échouée : $e');
      } finally {
        state = state.copyWith(isSearching: false);
      }
    }

    // 4. Streaming IA.
    final buffer = StringBuffer();
    try {
      final history = _buildHistory(
        files: attachments,
        searchResults: searchResults,
        instantAnswer: instantAnswer,
      );
      final entry = _resolveEntry(effectiveText, attachments);
      _lastModel = entry.modelId;

      await for (final token in _stream(entry, history)) {
        buffer.write(token);
        _pushPartial(placeholderId, buffer.toString());
      }
      _pushPartial(placeholderId, buffer.toString());

      final finalContent = buffer.toString().trim();
      final sources = searchResults == null
          ? null
          : ref.read(searchServiceProvider).formatSourcesAsList(searchResults);

      _replacePlaceholder(
        placeholderId,
        finalContent,
        sources: sources,
      );

      await repository.addMessage(
        conversationId: conversationId,
        role: Role.assistant,
        content: finalContent,
        model: entry.modelId,
        searchSources: sources,
      );
    } on AiException catch (e) {
      _dropPlaceholder(placeholderId);
      state = state.copyWith(
        error: formatAiError(e),
        isStreaming: false,
        isSearching: false,
      );
    } catch (e) {
      _dropPlaceholder(placeholderId);
      state = state.copyWith(
        error: e.toString(),
        isStreaming: false,
        isSearching: false,
      );
    }
  }

  String? _lastModel;

  // ── Helpers internes ───────────────────────────────────────────────────────

  ModelEntry _resolveEntry(String text, List<Attachment> attachments) {
    final hasImage = attachments.any((a) => a.isImage);
    final task = ModelRouter.classifyTask(text, hasImage: hasImage);
    return ModelRouter.resolveModel(task, isFull: false) ??
        (throw const AiException('Aucun modèle IA disponible'));
  }

  List<Map<String, dynamic>> _buildHistory({
    required List<Attachment> files,
    List<WebSearchResult>? searchResults,
    InstantAnswer? instantAnswer,
  }) {
    final history = state.messages
        .where((m) => m.role != Role.system && !m.isStreaming)
        .toList();
    final window = history.length > AppConfig.maxContextMessages
        ? history.sublist(history.length - AppConfig.maxContextMessages)
        : history;
    final historyMaps = window.map((m) => m.toApiMap()).toList();

    final systemMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': ref.read(systemPromptProvider)},
    ];

    final fileContext = _buildFileContext(files);
    if (fileContext != null) {
      systemMessages.add({
        'role': 'system',
        'content': "Contenu du document fourni par l'utilisateur :\n\n$fileContext",
      });
    }

    final searchContext = _searchContext(searchResults, instantAnswer);
    if (searchContext != null) {
      systemMessages.add({'role': 'system', 'content': searchContext});
    }

    return [...systemMessages, ...historyMaps];
  }

  String? _searchContext(
    List<WebSearchResult>? results,
    InstantAnswer? instant,
  ) {
    final buffer = StringBuffer();
    if (instant != null) {
      buffer.writeln(ref.read(searchServiceProvider).formatInstantAnswerForAi(instant));
      buffer.writeln();
    }
    if (results != null && results.isNotEmpty) {
      buffer.write(
        ref.read(searchServiceProvider).formatForAi(results, 'la question posée'),
      );
    }
    final context = buffer.toString().trim();
    return context.isEmpty ? null : context;
  }

  String? _buildFileContext(List<Attachment> attachments) {
    final buffer = StringBuffer();
    for (final att in attachments) {
      final text = att.extractedText;
      if (att.isImage || text == null || text.isEmpty) continue;
      buffer
        ..writeln('Document : ${att.name}')
        ..writeln(text)
        ..writeln();
    }
    final context = buffer.toString().trim();
    return context.isEmpty ? null : context;
  }

  Stream<String> _stream(ModelEntry entry, List<Map<String, dynamic>> history) {
    if (entry.provider == 'deepseek') {
      final key = AppConfig.deepSeekApiKey;
      if (key.isEmpty) throw const AiException('Clé API DeepSeek manquante');
      return DeepSeekClient(apiKey: key).streamChat(
        messages: history,
        model: entry.modelId,
      );
    }
    final key = AppConfig.openRouterApiKey;
    if (key.isEmpty) throw const AiException('Clé API OpenRouter manquante');
    return OpenRouterClient(apiKey: key).streamChat(
      messages: history,
      model: entry.modelId,
    );
  }

  void _pushPartial(String placeholderId, String content) {
    state = state.copyWith(
      messages: state.messages
          .map((m) => m.id == placeholderId ? m.copyWith(content: content) : m)
          .toList(),
    );
  }

  void _replacePlaceholder(
    String placeholderId,
    String content, {
    List<String>? sources,
  }) {
    state = state.copyWith(
      messages: state.messages
          .map(
            (m) => m.id == placeholderId
                ? m.copyWith(
                    content: content,
                    isStreaming: false,
                    searchSources: sources,
                  )
                : m,
          )
          .toList(),
      isStreaming: false,
      isSearching: false,
    );
  }

  void _dropPlaceholder(String placeholderId) {
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != placeholderId).toList(),
      isStreaming: false,
    );
  }

  /// Modèle utilisé pour le dernier échange (utile aux tests/diagnostics).
  String? get lastModel => _lastModel;
}

final chatNotifierProvider =
    NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);

/// Service de recherche web partagé.
final searchServiceProvider = Provider<SearchService>((ref) => SearchService());
