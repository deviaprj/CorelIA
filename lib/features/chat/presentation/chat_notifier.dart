import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/ai_client.dart';
import '../data/chat_api_service.dart';
import '../data/firestore_chat_repository.dart';
import '../data/mock_chat_repository.dart';
import '../data/quota_service.dart';
import '../data/search_service.dart';
import '../data/file_quota_service.dart';
import '../data/file_upload_service.dart';
import '../data/search_quota_service.dart';
import '../data/voice_quota_service.dart';
import '../data/ollama_vision_service.dart';
import '../domain/conversation.dart';
import '../domain/message.dart';
import '../../../core/constants.dart';
import '../../../core/platform/platform_service.dart';
import '../../../core/platform/extension_providers.dart';
import '../../../core/platform/extension_bridge.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../monetization/subscription/subscription_service.dart';
import '../../settings/presentation/settings_screen.dart' show systemPromptProvider;
import '../../monetization/credits/credit_providers.dart';
import '../../monetization/credits/credit_service.dart';
import '../../../main.dart' show isDemoMode;
import 'slash_commands.dart';

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

// ── Chat state ─────────────────────────────────────────────────────────────
class ChatState {
  final List<Message> messages;
  final bool isStreaming;
  final String? error;
  final int? remainingRequests;
  final bool isSearching;
  final bool useSearch;
  final int displayCount;

  const ChatState({
    this.messages = const [],
    this.isStreaming = false,
    this.error,
    this.remainingRequests,
    this.isSearching = false,
    this.useSearch = false,
    this.displayCount = 30,
  });

  ChatState copyWith({
    List<Message>? messages,
    bool? isStreaming,
    String? error,
    int? remainingRequests,
    bool? isSearching,
    bool? useSearch,
    int? displayCount,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        error: error,
        remainingRequests: remainingRequests ?? this.remainingRequests,
        isSearching: isSearching ?? this.isSearching,
        useSearch: useSearch ?? this.useSearch,
        displayCount: displayCount ?? this.displayCount,
      );

  bool get canLoadMore => messages.length > displayCount;
  List<Message> get displayedMessages =>
      messages.length <= displayCount
          ? messages
          : messages.sublist(messages.length - displayCount);
}

class ChatNotifier extends FamilyNotifier<ChatState, String> {
  @override
  ChatState build(String conversationId) {
    ref.listen(messagesStreamProvider(conversationId), (_, next) {
      // Hors streaming uniquement : sync depuis le repo Firestore/mock.
      // Pendant le streaming, on gère tout localement pour éviter les
      // conflits entre placeholders locaux et sync repo.
      try {
        final messages = next.valueOrNull;
        if (messages != null && !state.isStreaming) {
          state = state.copyWith(messages: messages);
        }
      } catch (e, st) {
        debugPrint('[ChatNotifier.listen] Error: $e\n$st');
      }
    });
    return const ChatState();
  }

  /// Traite une commande slash (/download, /pdf, /links, etc.)
  /// Retourne true si la commande a été traitée (ne pas envoyer à l'IA).
  Future<bool> handleSlashCommand(String text) async {
    final parsed = SlashCommands.parse(text);
    if (parsed == null) return false;

    final bridge = ref.read(extensionBridgeProvider);
    if (!bridge.isExtension) {
      // Les commandes slash ne fonctionnent que dans l'extension
      state = state.copyWith(
        error: 'Commande /${parsed.command.name} disponible uniquement dans l\'extension Chrome.',
        isStreaming: false,
      );
      return true;
    }

    switch (parsed.command.name) {
      case 'download':
        return await _handleSlashDownload(parsed, bridge);
      case 'pdf':
        return await _handleSlashPdf(parsed, bridge);
      case 'links':
        return await _handleSlashLinks(parsed, bridge);
      case 'summarize':
        return await _handleSlashSummarize(parsed, bridge);
      case 'extract':
        return await _handleSlashExtract(parsed, bridge);
      case 'scroll':
        return await _handleSlashScroll(parsed, bridge);
      case 'open':
        return await _handleSlashOpen(parsed, bridge);
      case 'click':
        return await _handleSlashClick(parsed, bridge);
      case 'fill':
        return await _handleSlashFill(parsed, bridge);
      case 'screenshot':
        return await _handleSlashScreenshot(parsed, bridge);
      case 'back':
        return await _handleSlashBack(parsed, bridge);
      case 'forward':
        return await _handleSlashForward(parsed, bridge);
      default:
        return false;
    }
  }

  Future<bool> _handleSlashDownload(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      state = state.copyWith(error: 'Usage : /download <url> [filename]', isStreaming: false);
      return true;
    }
    final url = cmd.args[0];
    final filename = cmd.args.length > 1 ? cmd.args[1] : null;

    final action = BrowserAction(
      action: BrowserActionType.download,
      params: {
        'url': url,
        if (filename != null) 'filename': filename,
      },
    );
    final result = await bridge.executeAction(action);
    if (result.success) {
      final downloaded = result.data?['downloaded'] as List? ?? [];
      final count = downloaded.where((d) => (d as Map?)?['success'] == true).length;
      state = state.copyWith(error: null, isStreaming: false);
      _addAssistantMessage('Téléchargement lancé pour $count fichier(s).');
    } else {
      state = state.copyWith(error: 'Erreur téléchargement : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashPdf(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    // /pdf [url] [filename] — PDF de la page courante ou d'une URL
    final url = cmd.args.isNotEmpty ? cmd.args[0] : null;
    final filename = cmd.args.length > 1 ? cmd.args[1] : null;

    // Si une URL est fournie, l'ouvrir d'abord
    if (url != null && url.startsWith('http')) {
      final openAction = BrowserAction(
        action: BrowserActionType.openUrl,
        params: {'url': url},
      );
      await bridge.executeAction(openAction);
    }

    final action = BrowserAction(
      action: BrowserActionType.saveAsPdf,
      params: {
        if (filename != null) 'filename': filename,
      },
    );
    final result = await bridge.executeAction(action);
    if (result.success) {
      state = state.copyWith(error: null, isStreaming: false);
      _addAssistantMessage('Fenêtre d\'impression ouverte. Choisissez "Enregistrer au format PDF".');
    } else {
      state = state.copyWith(error: 'Erreur PDF : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashLinks(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final filter = cmd.args.isNotEmpty ? cmd.args[0] : 'all';
    final action = BrowserAction(
      action: BrowserActionType.extractLinks,
      params: {'filter': filter},
    );
    final result = await bridge.executeAction(action);
    if (result.success && result.data != null) {
      final links = result.data!['links'] as List? ?? [];
      final count = result.data!['count'] as int? ?? links.length;
      final appliedFilter = result.data!['filter'] as String? ?? 'all';
      final linksText = links.take(20).map((l) {
        final m = l as Map;
        return '- [${m['text'] ?? 'Lien'}](${m['href']})';
      }).join('\n');
      final more = count > 20 ? '\n... et ${count - 20} autres' : '';
      _addAssistantMessage('Liens trouvés ($appliedFilter, $count au total) :\n$linksText$more');
    } else {
      state = state.copyWith(error: 'Erreur extraction liens : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashSummarize(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final action = BrowserAction(
      action: BrowserActionType.summarizePage,
      params: {},
    );
    final result = await bridge.executeAction(action);
    if (result.success && result.data != null) {
      final content = result.data!['content'] as String? ?? '';
      final title = result.data!['title'] as String? ?? '';
      // Injecter le contenu dans le message et laisser l'IA résumer
      final summarizePrompt = 'Résume le contenu suivant de la page "$title" '
          '(${content.length} caractères extraits) :\n\n${content.substring(0, content.length > 3000 ? 3000 : content.length)}';
      await sendMessage(summarizePrompt);
      return true;
    } else {
      state = state.copyWith(error: 'Erreur résumé : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashExtract(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final selector = cmd.args.isNotEmpty ? cmd.args[0] : 'body';
    final action = BrowserAction(
      action: BrowserActionType.extractText,
      params: {'selector': selector},
    );
    final result = await bridge.executeAction(action);
    if (result.success && result.data != null) {
      final text = result.data!['text'] as String? ?? '';
      _addAssistantMessage('Texte extrait de "$selector" (${text.length} caractères) :\n\n${text.substring(0, text.length > 3000 ? 3000 : text.length)}');
    } else {
      state = state.copyWith(error: 'Erreur extraction : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashScroll(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final direction = cmd.args.isNotEmpty ? cmd.args[0] : 'down';
    final amount = cmd.args.length > 1 ? int.tryParse(cmd.args[1]) ?? 500 : 500;
    final action = BrowserAction(
      action: BrowserActionType.scroll,
      params: {'direction': direction, 'amount': amount},
    );
    final result = await bridge.executeAction(action);
    if (result.success) {
      state = state.copyWith(error: null, isStreaming: false);
      _addAssistantMessage('Défilé ${direction == 'up' ? 'vers le haut' : 'vers le bas'} de $amount px.');
    } else {
      state = state.copyWith(error: 'Erreur scroll : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashOpen(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      state = state.copyWith(error: 'Usage : /open <url>', isStreaming: false);
      return true;
    }
    final action = BrowserAction(
      action: BrowserActionType.openUrl,
      params: {'url': cmd.args[0]},
    );
    final result = await bridge.executeAction(action);
    if (result.success) {
      state = state.copyWith(error: null, isStreaming: false);
      _addAssistantMessage('Onglet ouvert : ${cmd.args[0]}');
    } else {
      state = state.copyWith(error: 'Erreur ouverture : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashClick(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      state = state.copyWith(error: 'Usage : /click <sélecteur CSS>', isStreaming: false);
      return true;
    }
    final action = BrowserAction(
      action: BrowserActionType.clickElement,
      params: {'selector': cmd.args[0]},
    );
    final result = await bridge.executeAction(action);
    if (result.success) {
      state = state.copyWith(error: null, isStreaming: false);
      _addAssistantMessage('Cliqué sur "${cmd.args[0]}".');
    } else {
      state = state.copyWith(error: 'Erreur clic : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashFill(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.length < 2) {
      state = state.copyWith(error: 'Usage : /fill <sélecteur CSS> <valeur>', isStreaming: false);
      return true;
    }
    final action = BrowserAction(
      action: BrowserActionType.fillForm,
      params: {'selector': cmd.args[0], 'value': cmd.args.sublist(1).join(' ')},
    );
    final result = await bridge.executeAction(action);
    if (result.success) {
      state = state.copyWith(error: null, isStreaming: false);
      _addAssistantMessage('Champ "${cmd.args[0]}" rempli.');
    } else {
      state = state.copyWith(error: 'Erreur remplissage : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashScreenshot(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final action = BrowserAction(action: BrowserActionType.screenshot, params: {});
    final result = await bridge.executeAction(action);
    if (result.success) {
      state = state.copyWith(error: null, isStreaming: false);
      _addAssistantMessage('Capture d\'écran effectuée.');
    } else {
      state = state.copyWith(error: 'Erreur capture : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashBack(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final action = BrowserAction(action: BrowserActionType.navigateBack, params: {});
    final result = await bridge.executeAction(action);
    if (result.success) {
      state = state.copyWith(error: null, isStreaming: false);
      _addAssistantMessage('Retour à la page précédente.');
    } else {
      state = state.copyWith(error: 'Erreur navigation : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashForward(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final action = BrowserAction(action: BrowserActionType.navigateForward, params: {});
    final result = await bridge.executeAction(action);
    if (result.success) {
      state = state.copyWith(error: null, isStreaming: false);
      _addAssistantMessage('Page suivante.');
    } else {
      state = state.copyWith(error: 'Erreur navigation : ${result.error}', isStreaming: false);
    }
    return true;
  }

  /// Ajoute un message assistant au state (pour les résultats de commandes slash).
  void _addAssistantMessage(String text) {
    final msg = Message(
      id: 'slash_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: arg,
      role: Role.assistant,
      content: text,
      isStreaming: false,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(messages: [...state.messages, msg]);
  }

  Future<void> sendMessage(
    String text, {
    String? imageBase64,
    String? imageMimeType,
    String? fileName,
    String? fileContent,
    bool isVoiceConversation = false,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && imageBase64 == null) return;
    if (trimmed.length > 10000 || state.isStreaming) return;

    // Slash commands: intercept before AI processing (extension only)
    if (trimmed.startsWith('/') && PlatformService.isExtension) {
      final handled = await handleSlashCommand(trimmed);
      if (handled) return;
    }

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
        // Fallback local : credit service
        try {
          final remaining = await ref.read(creditServiceProvider).decrement();
          state = state.copyWith(remainingRequests: remaining);
        } on CreditsExhaustedException {
          state = state.copyWith(error: 'quota_exceeded', isStreaming: false);
          return;
        } catch (fallbackErr) {
          debugPrint('[Credit] Fallback error: $fallbackErr');
        }
      } catch (e) {
        debugPrint('[Quota] Error checking quota: $e');
        // Fallback local : credit service
        try {
          final remaining = await ref.read(creditServiceProvider).decrement();
          state = state.copyWith(remainingRequests: remaining);
        } on CreditsExhaustedException {
          state = state.copyWith(error: 'quota_exceeded', isStreaming: false);
          return;
        } catch (fallbackErr) {
          debugPrint('[Credit] Fallback error: $fallbackErr');
        }
      }

      // Quota fichiers (local, 100% autonome)
      if (fileContent != null && fileContent.isNotEmpty) {
        try {
          await ref.read(fileQuotaServiceProvider).checkAndDecrement();
        } on FileQuotaExceededException {
          state = state.copyWith(
            error: 'quota_files_exceeded',
            isStreaming: false,
          );
          return;
        } catch (e) {
          debugPrint('[FileQuota] Error: $e');
        }
      }

      // Quota recherches web (local, 100% autonome)
      if (state.useSearch) {
        try {
          await ref.read(searchQuotaServiceProvider).checkAndDecrement();
        } on SearchQuotaExceededException {
          state = state.copyWith(
            error: 'quota_search_exceeded',
            isStreaming: false,
          );
          return;
        } catch (e) {
          debugPrint('[SearchQuota] Error: $e');
        }
      }

      // Quota vocal (local, 100% autonome)
      if (isVoiceConversation) {
        try {
          await ref.read(voiceQuotaServiceProvider).checkAndDecrement();
        } on VoiceQuotaExceededException {
          state = state.copyWith(
            error: 'quota_voice_exceeded',
            isStreaming: false,
          );
          return;
        } catch (e) {
          debugPrint('[VoiceQuota] Error: $e');
        }
      }
    }

    // 1. Persister le message utilisateur dans le repo
    final userMsg = isDemoMode
        ? await mockChatRepository.addMessage(
            conversationId: arg,
            role: Role.user,
            content: trimmed,
            imageBase64: imageBase64,
            imageMimeType: imageMimeType,
            fileName: fileName,
          )
        : await ref.read(chatRepositoryProvider).addMessage(
            conversationId: arg,
            role: Role.user,
            content: trimmed,
            imageBase64: imageBase64,
            imageMimeType: imageMimeType,
            fileName: fileName,
          );

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

    // Recherche web — uniquement si l'utilisateur l'a activée OU si l'intent le nécessite
    List<WebSearchResult>? searchResults;
    InstantAnswer? instantAnswer;
    final shouldSearch = state.useSearch || _needsWebSearch(userMsg.content);
    if (shouldSearch) {
      try {
        state = state.copyWith(isSearching: true);
        final searchService = ref.read(searchServiceProvider);
        final searchQuery = _extractSearchQuery(userMsg.content);

        // Lancer la recherche principale et l'Instant Answer en parallèle
        final results = await searchService.searchWithFallback(searchQuery);
        searchResults = results;

        // Chercher une réponse instantanée si on a des résultats
        if (results.isNotEmpty) {
          try {
            instantAnswer = await searchService.getInstantAnswer(searchQuery);
          } catch (_) {
            // L'Instant Answer est optionnel, ne pas bloquer
          }
        }
      } catch (e) {
        debugPrint('[ChatNotifier] Recherche web echouee : $e');
      } finally {
        state = state.copyWith(isSearching: false);
      }
    }

    try {
      var retries = 0;
      const maxRetries = 2;
      while (retries <= maxRetries) {
        try {
          final stream = await _buildStream(
            userMsg,
            isPro,
            searchResults: searchResults,
            instantAnswer: instantAnswer,
            fileContent: fileContent,
            fileName: fileName,
          );

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
          break; // Stream reussi, sortir de la boucle retry
        } on AiException catch (e) {
          if (retries < maxRetries &&
              (e.statusCode == null || e.statusCode! >= 500 || e.statusCode == 429)) {
            retries++;
            debugPrint('[ChatNotifier] Retry stream $retries/$maxRetries : ${e.message}');
            await Future<void>.delayed(Duration(seconds: retries));
            continue;
          }
          rethrow;
        }
      }

      flushState();
      throttleTimer?.cancel();

      // 4. Stream terminé : transformer le placeholder en vrai message final
      var finalContent = buffer.toString();
      final model = isPro ? AppConstants.mistralModel : AppConstants.deepSeekModel;

      // Parser et exécuter les actions navigateur (extension Chrome uniquement)
      // puis supprimer les balises [CORELY_ACTION] du texte affiché
      finalContent = await _processBrowserActions(finalContent);

      // Stocker les sources separément pour affichage UI structuré
      List<String>? sourceList;
      if (searchResults != null && searchResults.isNotEmpty) {
        final searchService = ref.read(searchServiceProvider);
        sourceList = searchService.formatSourcesAsList(searchResults);
        // Garder les sources en markdown dans le content pour compatibilité
        final sourcesMd = searchService.formatSourcesForUi(searchResults);
        finalContent = '$finalContent$sourcesMd';
      }

      if (placeholderIndex != -1) {
        mutableMessages[placeholderIndex] = mutableMessages[placeholderIndex]
            .copyWith(
              content: finalContent,
              isStreaming: false,
              searchSources: sourceList,
            );
      }

      state = state.copyWith(
        messages: List<Message>.from(mutableMessages),
        isStreaming: false,
        isSearching: false,
      );

      // 5. Persister la réponse finale dans le repo pour que ref.listen
      //    la garde sync si l'utilisateur revient sur la conversation
      final persistedSources = sourceList;
      if (isDemoMode) {
        await mockChatRepository.addMessage(
          conversationId: arg,
          role: Role.assistant,
          content: finalContent,
          model: model,
          searchSources: persistedSources,
        );
      } else {
        await ref.read(chatRepositoryProvider).addMessage(
          conversationId: arg,
          role: Role.assistant,
          content: finalContent,
          model: model,
          searchSources: persistedSources,
        );
      }
    } on AiException catch (e) {
      final msg = _formatAiError(e);
      state = state.copyWith(error: msg, isStreaming: false, isSearching: false);
    } on ChatApiException catch (e) {
      state = state.copyWith(error: e.message, isStreaming: false, isSearching: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isStreaming: false, isSearching: false);
    } finally {
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

  Future<Stream<String>> _buildStream(
    Message userMsg,
    bool isPro, {
    List<WebSearchResult>? searchResults,
    InstantAnswer? instantAnswer,
    String? fileContent,
    String? fileName,
  }) async {
    // ── 0. Prompt système Corely ───────────────────────────────────────────
    final corelySystemPrompt = ref.read(systemPromptProvider);

    // Ajouter le contexte des actions navigateur si on est en extension Chrome
    final fullSystemPrompt = PlatformService.isExtension
        ? '$corelySystemPrompt\n\n$_browserActionSystemContext'
        : corelySystemPrompt;

    // ── 1. Construire l'historique ───────────────────────────────────────
    final historyMessages = state.messages
        .where((m) => m.role != Role.system && !m.isStreaming)
        .toList()
        .reversed
        .take(AppConstants.maxContextMessages)
        .toList()
        .reversed
        .toList();

    // Insérer le prompt système en tête
    historyMessages.insert(0, Message(
      id: 'corely_system_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: arg,
      role: Role.system,
      content: fullSystemPrompt,
      createdAt: DateTime.now(),
    ));

    // ── 2. Injecter le contexte fichier ────────────────────────────────
    if (fileContent != null && fileContent.isNotEmpty) {
      final truncated = FileUploadService.truncateForContext(
        fileContent,
        isPro: isPro,
      );
      final fileLabel = fileName != null ? 'Fichier : $fileName' : 'Document';
      historyMessages.insert(0, Message(
        id: 'file_context_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: arg,
        role: Role.system,
        content:
            "$fileLabel\n\n"
            "Contenu du document fourni par l'utilisateur. "
            'Utilise ce contenu pour repondre '
            "a la question de l'utilisateur.\n\n"
            '$truncated',
        createdAt: DateTime.now(),
      ));
    }

    // ── 3. Injecter le contexte recherche web ────────────────────────────
    if (instantAnswer != null) {
      // Réponse instantanée en priorité (plus concise et directe)
      final searchService = ref.read(searchServiceProvider);
      final instantContext = searchService.formatInstantAnswerForAi(instantAnswer);

      historyMessages.insert(0, Message(
        id: 'instant_context_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: arg,
        role: Role.system,
        content: 'Réponse rapide issue d\'une encyclopédie. Utilise cette information si pertinente.\n\n$instantContext',
        createdAt: DateTime.now(),
      ));
    }

    if (searchResults != null && searchResults.isNotEmpty) {
      final searchService = ref.read(searchServiceProvider);
      final searchContext = searchService.formatForAi(searchResults, userMsg.content);

      historyMessages.insert(0, Message(
        id: 'search_context_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: arg,
        role: Role.system,
        content:
            'Voici des resultats de recherche web pertinents pour la question. '
            'Utilise-les pour enrichir ta reponse et cite tes sources.\n\n'
            '$searchContext',
        createdAt: DateTime.now(),
      ));
    }

    final historyMaps = historyMessages.map((m) => m.toApiMap()).toList();

    // ── 4. DeepSeek / OpenRouter direct (100% autonome) ───────────────
    return _getDirectAiStream(historyMaps, isPro);
  }

  Stream<String> _getDirectAiStream(
    List<Map<String, dynamic>> history,
    bool isPro,
  ) {
    // 1. Les images passent TOUJOURS par un modele vision,
    //    independamment du statut Pro/Free.
    final hasImage = history.any((m) => m['content'] is List);
    if (hasImage) {
      return _getVisionStream(history);
    }

    // 2. Pro sans image → OpenRouter (Mistral)
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

    // 3. Free (ou Pro sans OpenRouter) → DeepSeek texte
    final deepSeekKey = AppConstants.deepSeekApiKey;
    if (deepSeekKey.isEmpty) {
      return _mockResponseStream();
    }
    return DeepSeekClient(apiKey: deepSeekKey)
        .streamChat(messages: history, enableSearch: false);
  }

  /// Route une requete avec image vers un modele vision.
  /// Priorite : Ollama (si configuré) > OpenRouter GPT-4o-mini > DeepSeek chat.
  Stream<String> _getVisionStream(List<Map<String, dynamic>> history) async* {
    // 0. Ollama vision locale (si configuré et disponible)
    final ollama = ref.read(ollamaVisionServiceProvider);
    await ollama.loadConfig();
    if (ollama.enabled) {
      final available = await ollama.isAvailable();
      if (available) {
        debugPrint('[ChatNotifier] Vision via Ollama');
        try {
          // Extraire l'image base64 du dernier message utilisateur
          final lastUserMsg = history.lastWhere(
            (m) => m['role'] == 'user',
            orElse: () => {},
          );
          final content = lastUserMsg['content'];
          String? imageBase64;
          String textPrompt = '';
          if (content is List) {
            for (final part in content) {
              if (part is Map) {
                if (part['type'] == 'text') textPrompt = part['text'] as String? ?? '';
                if (part['type'] == 'image_url') {
                  final url = part['image_url']?['url'] as String? ?? '';
                  if (url.startsWith('data:')) {
                    imageBase64 = url.substring(url.indexOf(',') + 1);
                  }
                }
              }
            }
          }
          if (imageBase64 != null) {
            final description = await ollama.analyzeImage(
              imageBase64: imageBase64,
              prompt: textPrompt.isNotEmpty ? textPrompt : 'Décris cette image en détail.',
            );
            yield description;
            return;
          }
        } catch (e) {
          debugPrint('[ChatNotifier] Ollama vision error, fallback cloud: $e');
        }
      }
    }

    // 1. OpenRouter GPT-4o-mini
    final openRouterKey = AppConstants.openRouterApiKey;
    if (openRouterKey.isNotEmpty) {
      debugPrint('[ChatNotifier] Vision via OpenRouter');
      yield* OpenRouterClient(apiKey: openRouterKey).streamChat(
        messages: history,
        model: AppConstants.visionModel,
        maxTokens: AppConstants.proMaxTokens,
      );
      return;
    }

    // 2. DeepSeek chat (supporte vision)
    final deepSeekKey = AppConstants.deepSeekApiKey;
    if (deepSeekKey.isNotEmpty) {
      debugPrint('[ChatNotifier] Vision via DeepSeek chat');
      yield* DeepSeekClient(apiKey: deepSeekKey).streamChat(
        messages: history,
        model: AppConstants.deepSeekVisionModel,
        enableSearch: true,
      );
      return;
    }

    throw const AiException(
      'Analyse d\'image non disponible. Ajoutez une cle API OpenRouter.',
      statusCode: 400,
    );
  }

  /// Réponse mock pour tests en mode DEMO
  Stream<String> _mockResponseStream() async* {
    const response =
        'Bonjour ! Je suis Corely, votre assistant IA. '
        'En mode démo, je fonctionne sans connexion externe. '
        'Posez-moi des questions sur n\'importe quel sujet !';
    for (final word in response.split(' ')) {
      yield '$word ';
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  /// Formate les erreurs IA pour l'utilisateur.
  String _formatAiError(AiException e) {
    final msg = e.message;
    if (msg.contains('image') || msg.contains('image_url')) {
      return 'Ce modele ne supporte pas l\'analyse d\'images. '
          'Ajoutez une cle OpenRouter dans les parametres.';
    }
    if (msg.contains('Clé API')) return msg;
    if (msg.contains('429') || msg.contains('Trop de requêtes')) {
      return 'Limite de requetes atteinte. Reessayez dans un moment.';
    }
    return 'Erreur IA. Reessayez.';
  }

  void toggleSearch() {
    state = state.copyWith(useSearch: !state.useSearch);
  }

  void clearError() => state = state.copyWith(error: null);

  // ── Intent classification ────────────────────────────────────────────────
  // Détermine si le message nécessite une recherche web.
  // Les questions factuelles, temporelles ou sur l'actualité en ont besoin.
  // Les conversations générales, la créativité et le code n'en ont pas besoin.
  static bool _needsWebSearch(String message) {
    final lower = message.toLowerCase();
    // Mots-clés déclencheurs : informations factuelles/temporelles
    final triggerWords = [
      'actualité', 'actualites', 'news', 'aujourd\'hui', 'en ce moment',
      'quelle est la', 'quel est le', 'combien de', 'combien coûte',
      'où est', 'ou est', 'où trouver', 'ou trouver',
      'qui est', 'qui a', 'quand est', 'quelle année', 'quel année',
      'dernier', 'dernière', 'latest', 'newest', 'current',
      'prix de', 'cours de', 'taux de', 'météo', 'meteo',
      'score de', 'résultat de', 'classement de',
      'est-ce que', 'est-il vrai', 'vrai ou faux',
      'comment aller', 'itinéraire', 'distance entre',
    ];
    // Mots-clés exclus : créativité, code, opinion, conversation
    final excludeWords = [
      'écris', 'ecris', 'rédige', 'redige', 'raconte', 'invente',
      'imagine', 'crée', 'cree', 'dessine', 'compose',
      'code', 'programme', 'fonction', 'script', 'algorithme',
      'explique-moi', 'explique comment', 'pourquoi le',
      'qu\'en penses-tu', 'ton avis', 'selon toi',
      'story', 'poème', 'poeme', 'chanson', 'blague',
    ];
    // Si le message contient un mot-clé exclusif, pas de recherche
    if (excludeWords.any((w) => lower.contains(w))) return false;
    // Si le message contient un mot-clé déclencheur, recherche
    if (triggerWords.any((w) => lower.contains(w))) return true;
    // Questions explicites avec "?" — heuristique
    if (lower.contains('?')) {
      // Les questions longues et détaillées sont souvent conversationnelles
      if (lower.length > 100) return false;
      return true;
    }
    // Par défaut, pas de recherche (conversation normale)
    return false;
  }

  /// Extrait une requête de recherche optimisée à partir du message utilisateur.
  /// Supprime les salutations et le contexte conversationnel superflu.
  static String _extractSearchQuery(String message) {
    var query = message.trim();
    // Retirer les salutations courantes
    const salutations = ['bonjour', 'salut', 'hello', 'hi', 'hey', 'coucou'];
    for (final s in salutations) {
      if (query.toLowerCase().startsWith(s)) {
        query = query.substring(s.length).trim();
        break;
      }
    }
    // Limiter la longueur de la requête
    if (query.length > 200) {
      query = '${query.substring(0, 200)}...';
    }
    return query;
  }

  /// Charge plus de messages dans l'historique (UI pagination).
  void loadMoreHistory() {
    if (!state.canLoadMore) return;
    state = state.copyWith(displayCount: state.displayCount + 20);
  }

  // ── Browser actions (extension Chrome) ────────────────────────────────────

  /// Contexte système injecté quand l'app tourne en extension Chrome.
  /// Indique à l'IA les actions navigateur disponibles et leur format.
  static const _browserActionSystemContext =
      'You have browser interaction capabilities when running as a Chrome extension. '
      'When the user asks you to open a URL, click something on the page, fill a form, '
      'scroll, download a file, convert to PDF, or extract information from the current page, '
      'output a structured action command using this exact format:\n'
      '[CORELY_ACTION]\n'
      '{"action": "ACTION_TYPE", "params": { ... }}\n'
      '[/CORELY_ACTION]\n\n'
      'Available actions:\n'
      '- OPEN_URL: {"action": "OPEN_URL", "params": {"url": "https://..."}}\n'
      '- GET_PAGE_CONTENT: {"action": "GET_PAGE_CONTENT", "params": {}}\n'
      '- SUMMARIZE_PAGE: {"action": "SUMMARIZE_PAGE", "params": {}}\n'
      '- EXTRACT_TEXT: {"action": "EXTRACT_TEXT", "params": {"selector": "CSS selector"}}\n'
      '- EXTRACT_LINKS: {"action": "EXTRACT_LINKS", "params": {"filter": "all|video|image|audio|document"}}\n'
      '- CLICK_ELEMENT: {"action": "CLICK_ELEMENT", "params": {"selector": "CSS selector"}}\n'
      '- FILL_FORM: {"action": "FILL_FORM", "params": {"selector": "CSS selector", "value": "text"}}\n'
      '- SCROLL: {"action": "SCROLL", "params": {"direction": "down", "amount": 500}}\n'
      '- NAVIGATE_BACK: {"action": "NAVIGATE_BACK", "params": {}}\n'
      '- NAVIGATE_FORWARD: {"action": "NAVIGATE_FORWARD", "params": {}}\n'
      '- DOWNLOAD: {"action": "DOWNLOAD", "params": {"url": "https://...", "filename": "optional_name.mp4"}}\n'
      '  Multiple URLs: {"action": "DOWNLOAD", "params": {"urls": ["url1", "url2"], "filename": "optional_prefix"}}\n'
      '- SAVE_AS_PDF: {"action": "SAVE_AS_PDF", "params": {"filename": "optional_name"}}\n'
      '- SCREENSHOT: {"action": "SCREENSHOT", "params": {}}\n\n'
      'You can include one or more actions in your response alongside regular text. '
      'The actions will be executed after your response is displayed. '
      'Always explain what you are doing before outputting an action. '
      'For SUMMARIZE_PAGE, extract the content first then provide your summary in your response. '
      'For DOWNLOAD, you can pass a single url or an array of urls. '
      'For EXTRACT_LINKS, use filter "video" for video URLs, "image" for image URLs, '
      '"audio" for audio URLs, "document" for document URLs, or "all" for all links.';

  /// Parse et exécute les actions navigateur dans la réponse de l'IA.
  /// Retourne le texte nettoyé (sans les balises [CORELY_ACTION]).
  Future<String> _processBrowserActions(String content) async {
    if (!PlatformService.isExtension) return content;

    final stripped = _stripActionCommands(content);
    await _parseAndExecuteBrowserActions(content);
    return stripped;
  }

  /// Extrait et exécute les actions navigateur d'une réponse IA.
  Future<void> _parseAndExecuteBrowserActions(String content) async {
    final actionRegex = RegExp(
      r'\[CORELY_ACTION\]\s*(\{[\s\S]*?\})\s*\[/CORELY_ACTION\]',
      multiLine: true,
    );

    final matches = actionRegex.allMatches(content);
    if (matches.isEmpty) return;

    final bridge = ref.read(extensionBridgeProvider);
    for (final match in matches) {
      try {
        final jsonStr = match.group(1)?.trim();
        if (jsonStr == null) continue;

        // Parse the JSON action
        final decoded = _parseJsonLoose(jsonStr);
        if (decoded == null) continue;

        final action = BrowserAction(
          action: BrowserActionType.fromString(decoded['action'] as String? ?? ''),
          params: Map<String, dynamic>.from(decoded['params'] as Map? ?? {}),
        );

        final result = await bridge.executeAction(action);
        debugPrint('[ChatNotifier] Browser action ${action.action.value}: '
            'success=${result.success}${result.error != null ? ' error=${result.error}' : ''}');

        // Si l'action a retourné du contenu de page, on pourrait l'injecter
        // dans un futur message système, mais pour l'instant on loggue simplement
        if (result.success &&
            (result.action == BrowserActionType.getPageContent ||
                result.action == BrowserActionType.summarizePage) &&
            result.data != null) {
          final contentStr = result.data!['content'] as String? ?? '';
          debugPrint('[ChatNotifier] Page content received: '
              '${contentStr.substring(0, contentStr.length > 200 ? 200 : contentStr.length)}...');
        }
      } catch (e) {
        debugPrint('[ChatNotifier] Browser action parse error: $e');
      }
    }
  }

  /// Parse JSON de manière tolérante (accepte les sauts de ligne dans les strings).
  static Map<String, dynamic>? _parseJsonLoose(String jsonStr) {
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Supprime les balises [CORELY_ACTION]...[/CORELY_ACTION] du texte affiché.
  static String _stripActionCommands(String text) {
    return text
        .replaceAll(
          RegExp(r'\[CORELY_ACTION\][\s\S]*?\[/CORELY_ACTION\]', multiLine: true),
          '',
        )
        .trim();
  }
}

final chatNotifierProvider =
    NotifierProviderFamily<ChatNotifier, ChatState, String>(
  ChatNotifier.new,
);
