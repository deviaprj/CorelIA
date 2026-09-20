import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/ai_client.dart';
import '../../../core/api/cloudflare_client.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/message.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../subscription/data/quota_service.dart';
import '../../subscription/data/role_providers.dart';
import '../../subscription/domain/quota_policy.dart';
import '../data/chat_repository.dart';
import '../data/model_router.dart';
import '../data/search_service.dart';
import '../data/web_search_trigger.dart';

/// Code d'erreur signalant un quota journalier épuisé.
const kQuotaExceededError = 'quota_exceeded';

/// État de l'écran de chat.
class ChatState {
  const ChatState({
    this.messages = const [],
    this.isStreaming = false,
    this.isSearching = false,
    this.useSearch = true,
    this.remainingRequests,
    this.quotaBlocked = false,
    this.error,
  });

  final List<Message> messages;
  final bool isStreaming;
  final bool isSearching;

  /// Recherche Internet forcée par l'utilisateur (activée par défaut).
  final bool useSearch;

  /// Requêtes restantes aujourd'hui ; `null` si illimité (Agent IA Full).
  final int? remainingRequests;

  /// Vrai lorsqu'un envoi a été bloqué par le quota.
  final bool quotaBlocked;

  final String? error;

  ChatState copyWith({
    List<Message>? messages,
    bool? isStreaming,
    bool? isSearching,
    bool? useSearch,
    int? remainingRequests,
    bool? quotaBlocked,
    String? error,
    bool clearError = false,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        isSearching: isSearching ?? this.isSearching,
        useSearch: useSearch ?? this.useSearch,
        remainingRequests: remainingRequests ?? this.remainingRequests,
        quotaBlocked: quotaBlocked ?? this.quotaBlocked,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Message conservé le temps que l'utilisateur débloque son quota.
class _PendingMessage {
  const _PendingMessage({required this.text, this.attachments = const []});

  final String text;
  final List<Attachment> attachments;
}

/// Orchestre une conversation unique : persistance, quotas, recherche web et
/// streaming IA.
class ChatNotifier extends Notifier<ChatState> {
  String? _conversationId;
  StreamSubscription<List<Message>>? _subscription;
  _PendingMessage? _pending;
  String? _lastModel;

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

    await refreshQuota();
  }

  /// Recharge le compteur de requêtes restantes pour le rôle courant.
  Future<void> refreshQuota() async {
    final role = ref.read(userRoleProvider);
    final remaining = await ref.read(quotaServiceProvider).remaining(role);
    state = state.copyWith(remainingRequests: remaining);
  }

  void toggleSearch() => state = state.copyWith(useSearch: !state.useSearch);

  void clearError() =>
      state = state.copyWith(clearError: true, quotaBlocked: false);

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

    final role = ref.read(userRoleProvider);
    final policy = QuotaPolicies.forRole(role);

    final totalSize = attachments.fold<int>(0, (sum, a) => sum + a.sizeBytes);
    if (totalSize > policy.maxAttachmentBytes) {
      state = state.copyWith(
        error: 'Pièce jointe trop volumineuse '
            '(${policy.maxAttachmentBytes ~/ (1024 * 1024)} Mo max).',
      );
      return;
    }

    // 1. Vérifier le quota journalier (Free uniquement).
    if (policy.limited) {
      try {
        final remaining = await ref.read(quotaServiceProvider).consume(role);
        state = state.copyWith(remainingRequests: remaining);
      } on QuotaExceededException {
        _pending = _PendingMessage(text: text, attachments: attachments);
        state = state.copyWith(
          error: kQuotaExceededError,
          quotaBlocked: true,
          isStreaming: false,
        );
        return;
      }
    }

    _pending = null;
    final effectiveText = trimmed.isEmpty ? 'Analyse ce document' : trimmed;
    final repository = ref.read(chatRepositoryProvider);

    // 2. Persister le message utilisateur.
    final userMessage = await repository.addMessage(
      conversationId: conversationId,
      role: Role.user,
      content: effectiveText,
      attachments: attachments,
      fileContext: _buildFileContext(attachments),
    );

    // 3. Placeholder de streaming (local, non persisté).
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

    // 4. Recherche Internet éventuelle.
    List<WebSearchResult>? searchResults;
    InstantAnswer? instantAnswer;
    final shouldSearch = policy.searchEnabled &&
        (state.useSearch || WebSearchTrigger.needsWebSearch(effectiveText));
    if (shouldSearch) {
      state = state.copyWith(isSearching: true);
      try {
        final searchService = ref.read(searchServiceProvider);
        final query = WebSearchTrigger.extractSearchQuery(effectiveText);
        // La recherche est active par défaut : on ne transmet au modèle que les
        // résultats qui recoupent réellement la question posée.
        final found = await searchService.search(query);
        final relevant = WebSearchTrigger.relevantResults(query, found);
        if (relevant.isNotEmpty) {
          searchResults = relevant;
          instantAnswer = await searchService.getInstantAnswer(query);
        }
      } catch (e) {
        debugPrint('[Chat] Recherche web échouée : $e');
      } finally {
        state = state.copyWith(isSearching: false);
      }
    }

    // 5. Streaming IA.
    final buffer = StringBuffer();
    try {
      final history = _buildHistory(
        files: attachments,
        searchResults: searchResults,
        instantAnswer: instantAnswer,
      );
      final entry = _resolveEntry(effectiveText, attachments, isFull: role.isFull);
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

      _replacePlaceholder(placeholderId, finalContent, sources: sources);

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

  /// Relance le message bloqué par le quota (après passage en Full).
  Future<void> retryPendingMessage() async {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    state = state.copyWith(quotaBlocked: false, clearError: true);
    await sendMessage(pending.text, attachments: pending.attachments);
  }

  /// Abandonne le message bloqué.
  void clearPendingMessage() => _pending = null;

  // ── Helpers internes ───────────────────────────────────────────────────────

  ModelEntry _resolveEntry(
    String text,
    List<Attachment> attachments, {
    required bool isFull,
  }) {
    final hasImage = attachments.any((a) => a.isImage);
    final task = ModelRouter.classifyTask(text, hasImage: hasImage);
    return ModelRouter.resolveModel(task, isFull: isFull) ??
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

    final fileContext = _activeFileContext(window, files);
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
      buffer
        ..writeln(ref.read(searchServiceProvider).formatInstantAnswerForAi(instant))
        ..writeln();
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
      buffer.writeln('Document : ${att.name}');
      if (Attachment.isUnreadableText(text)) {
        // Ne jamais présenter le marqueur d'échec comme du contenu : l'IA
        // répondrait qu'elle reçoit un « binaire illisible ».
        buffer.writeln(
          'Lecture automatique impossible (PDF scanné, image ou protégé). '
          "Préviens l'utilisateur et demande-lui de coller le texte.",
        );
      } else {
        buffer.writeln(text);
      }
      buffer.writeln();
    }
    final context = buffer.toString().trim();
    return context.isEmpty ? null : context;
  }

  /// Contexte documentaire actif pour ce tour.
  ///
  /// Les pièces jointes du message courant priment ; sinon on réinjecte le
  /// document le plus récemment fourni dans la conversation. Sans cela, une
  /// question de suivi (« et le chapitre 2 ? ») posée sans ré-attacher le
  /// fichier perdrait tout le document.
  String? _activeFileContext(List<Message> history, List<Attachment> current) {
    final fromCurrent = _buildFileContext(current);
    if (fromCurrent != null) return fromCurrent;

    for (var i = history.length - 1; i >= 0; i--) {
      final context = history[i].fileContext;
      if (context != null && context.isNotEmpty) return context;
    }
    return null;
  }

  Stream<String> _stream(ModelEntry entry, List<Map<String, dynamic>> history) {
    if (entry.provider == 'cloudflare') {
      return CloudflareWorkerClient(
        chatUrl: AppConfig.workerChatUrl,
        apiKey: AppConfig.clientApiKey,
      ).streamChat(messages: history, model: entry.modelId);
    }
    final key = AppConfig.deepSeekApiKey;
    if (key.isEmpty) throw const AiException('Clé API DeepSeek manquante');
    return DeepSeekClient(apiKey: key).streamChat(
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

  /// Modèle utilisé pour le dernier échange (diagnostics).
  String? get lastModel => _lastModel;
}

final chatNotifierProvider =
    NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);

/// Service de recherche web partagé.
final searchServiceProvider = Provider<SearchService>((ref) => SearchService());
