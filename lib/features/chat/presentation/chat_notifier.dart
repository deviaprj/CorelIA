import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../data/ai_client.dart';
import '../data/chat_api_service.dart';
import '../data/firestore_chat_repository.dart';
import '../data/mock_chat_repository.dart';
import '../data/quota_service.dart';
import '../data/search_service.dart';
import '../data/enhanced_search_service.dart';
import '../data/search_intent_extractor.dart';
import '../data/weather_service.dart';
import '../data/location_service.dart';
import '../data/file_quota_service.dart';
import '../data/file_upload_service.dart';
import '../data/search_quota_service.dart';
import '../data/voice_quota_service.dart';
import '../data/ollama_vision_service.dart';
import '../data/document_generation_service.dart';
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
import '../../../core/language/language_service.dart' as lang;
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
final enhancedSearchServiceProvider =
    Provider((ref) => EnhancedSearchService());
final weatherServiceProvider = Provider((ref) => WeatherService());
final locationServiceProvider = Provider((ref) => LocationService());
final documentGenerationServiceProvider =
  Provider((ref) => DocumentGenerationService());

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
  List<String> _lastLinksForDownload = const [];
  String _lastLinksFilter = 'all';

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
  /// Retourne true si la commande a ete traitee (ne pas envoyer a l'IA).
  Future<bool> handleSlashCommand(String text) async {
    final parsed = SlashCommands.parse(text);
    if (parsed == null) {
      debugPrint('[ChatNotifier] Slash command parse returned null for: ${text.length > 60 ? '${text.substring(0, 60)}...' : text}');
      return false;
    }
    debugPrint('[ChatNotifier] Slash command intercepted: /${parsed.command.name} (${parsed.args.length} args)');

    final bridge = ref.read(extensionBridgeProvider);
    final isExtension = bridge.isExtension;

    // Commands that work on ALL platforms (not just extension)
    final universalCommands = {'docgen'};

    if (!isExtension && !universalCommands.contains(parsed.command.name)) {
      // Extension-only commands require the extension bridge.
      state = state.copyWith(
        error: 'Commande /${parsed.command.name} disponible uniquement dans l\'extension Chrome.',
        isStreaming: false,
      );
      return true;
    }

    // Add natural language user message to conversation
    final appLang = ref.read(lang.languageProvider);
    final naturalText = parsed.toNaturalLanguage(appLang);
    final userMsg = Message(
      id: 'slash_user_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: arg,
      role: Role.user,
      content: naturalText,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(messages: [...state.messages, userMsg]);
    // Persist in repo (best effort, fire-and-forget)
    try {
      if (isDemoMode) {
        await mockChatRepository.addMessage(
          conversationId: arg,
          role: Role.user,
          content: naturalText,
        );
      } else {
        await ref.read(chatRepositoryProvider).addMessage(
          conversationId: arg,
          role: Role.user,
          content: naturalText,
        );
      }
    } catch (_) {
      // Non-bloquant : le message est deja dans le state local
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
      case 'forms':
        return await _handleSlashForms(parsed, bridge);
      case 'tables':
        return await _handleSlashTables(parsed, bridge);
      case 'media':
        return await _handleSlashMedia(parsed, bridge);
      case 'metadata':
        return await _handleSlashMetadata(parsed, bridge);
      case 'autofill':
        return await _handleSlashAutofill(parsed, bridge);
      case 'inspect':
        return await _handleSlashInspect(parsed, bridge);
      case 'highlight':
        return await _handleSlashHighlight(parsed, bridge);
      case 'waitfor':
        return await _handleSlashWaitFor(parsed, bridge);
      case 'export':
        return await _handleSlashExport(parsed, bridge);
      case 'monitor':
        return await _handleSlashMonitor(parsed, bridge);
      case 'translate':
        return await _handleSlashTranslate(parsed, bridge);
      case 'searchpage':
        return await _handleSlashSearchPage(parsed, bridge);
      case 'docgen':
        return await _handleSlashDocgen(parsed, bridge);
      default:
        return false;
    }
  }

  Future<bool> _handleSlashDownload(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    List<String> urlsToDownload;
    String? filename;

    if (cmd.args.isEmpty) {
      if (_lastLinksForDownload.isEmpty) {
        state = state.copyWith(
          error: 'Aucun lien en mémoire. Lancez d\'abord `/links`, puis `/download`.',
          isStreaming: false,
        );
        return true;
      }
      urlsToDownload = _lastLinksForDownload;
    } else {
      urlsToDownload = [cmd.args[0]];
      filename = cmd.args.length > 1 ? cmd.args[1] : null;
    }

    final action = BrowserAction(
      action: BrowserActionType.download,
      params: {
        if (urlsToDownload.length == 1) 'url': urlsToDownload.first,
        if (urlsToDownload.length > 1) 'urls': urlsToDownload,
        if (filename != null) 'filename': filename,
      },
    );
    final result = await bridge.executeAction(action);
    if (result.success) {
      final downloaded = result.data?['downloaded'] as List? ?? [];
      final count = downloaded.where((d) => (d as Map?)?['success'] == true).length;
      state = state.copyWith(error: null, isStreaming: false);
      if (cmd.args.isEmpty) {
        _addAssistantMessage(
          'Téléchargement lancé pour $count fichier(s) depuis le dernier `/links` '
          '(filtre `${_lastLinksFilter}`, ${_lastLinksForDownload.length} lien(s) en mémoire).',
        );
      } else {
        _addAssistantMessage('Téléchargement lancé pour $count fichier(s).');
      }
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
    final rawFilter = cmd.args.isNotEmpty ? cmd.args[0] : 'all';
    final aliases = <String, String>{
      'videos': 'video',
      'images': 'image',
      'documents': 'document',
      'docs': 'document',
      'files': 'document',
      'audios': 'audio',
    };
    final filter = aliases[rawFilter.toLowerCase()] ?? rawFilter.toLowerCase();
    final action = BrowserAction(
      action: BrowserActionType.extractLinks,
      params: {'filter': filter},
    );
    final result = await bridge.executeAction(action);
    if (result.success && result.data != null) {
      final links = result.data!['links'] as List? ?? [];
      final count = result.data!['count'] as int? ?? links.length;
      final appliedFilter = result.data!['filter'] as String? ?? 'all';
      final totalMatched = result.data!['totalMatched'] as int? ?? count;
      final pageUrl = result.data!['pageUrl'] as String? ?? '';
      final pageTitle = result.data!['pageTitle'] as String? ?? '';
      final rawAnchorCount = result.data!['rawAnchorCount'] as int? ?? 0;
      final mediaSourceCount = result.data!['mediaSourceCount'] as int? ?? 0;
      _lastLinksFilter = appliedFilter;
      _lastLinksForDownload = links
          .whereType<Map>()
          .map((m) => m['href'])
          .whereType<String>()
          .where((u) => u.trim().isNotEmpty)
          .toList(growable: false);
      final linksText = links.take(20).map((l) {
        final m = l as Map;
        return '- [${m['text'] ?? 'Lien'}](${m['href']})';
      }).join('\n');
      final more = count > 20 ? '\n... et ${count - 20} autres' : '';
      final diagnostics = 'Diagnostic: page="${pageTitle.isNotEmpty ? pageTitle : 'N/A'}" '
          'URL=$pageUrl | ancres_brutes=$rawAnchorCount | media_sources=$mediaSourceCount '
          '| matches_total=$totalMatched | retournes=$count';
      _addAssistantMessage('Liens trouvés ($appliedFilter, $count au total) :\n$linksText$more\n\n'
          '$diagnostics\n\n💡 Lancez `/download` sans paramètre pour télécharger toute cette liste.');
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

  // ── Nouvelles commandes slash (Session V7) ──────────────────────────────────

  Future<bool> _handleSlashForms(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final action = BrowserAction(action: BrowserActionType.extractForms, params: {});
    final result = await bridge.executeAction(action);
    if (result.success && result.data != null) {
      final forms = result.data!['forms'] as List? ?? [];
      final count = result.data!['count'] as int? ?? forms.length;
      if (forms.isEmpty) {
        _addAssistantMessage('Aucun formulaire trouvé sur cette page.');
      } else {
        final buffer = StringBuffer();
        final requestedIndex = cmd.args.isNotEmpty ? int.tryParse(cmd.args[0]) : null;

        if (requestedIndex != null) {
          if (requestedIndex < 0 || requestedIndex >= forms.length) {
            state = state.copyWith(
              error: 'Index de formulaire invalide: $requestedIndex (0..${forms.length - 1})',
              isStreaming: false,
            );
            return true;
          }

          final f = forms[requestedIndex] as Map;
          final inputs = (f['inputs'] as List? ?? []).cast<Map>();
          buffer.writeln('**Formulaire ${requestedIndex + 1}/$count**');
          buffer.writeln('- Action: ${f['action'] ?? 'N/A'}');
          buffer.writeln('- Méthode: ${f['method'] ?? 'GET'}');
          buffer.writeln('- ID: ${f['id'] ?? 'N/A'}');
          buffer.writeln('- Champs: ${inputs.length}');
          buffer.writeln();
          for (var i = 0; i < inputs.length && i < 20; i++) {
            final input = inputs[i];
            buffer.writeln(
              '- ${input['tagName'] ?? 'INPUT'} `${input['name'] ?? ''}` '
              '(type: ${input['type'] ?? 'text'}${input['required'] == true ? ', requis' : ''})',
            );
          }
          if (inputs.length > 20) {
            buffer.writeln('- ... et ${inputs.length - 20} autres');
          }
          buffer.writeln('\n💡 `/autofill` pour remplir ce formulaire automatiquement.');
        } else {
          buffer.writeln('**$count formulaire(s) trouvé(s)**\n');
          for (var i = 0; i < forms.length; i++) {
            final f = forms[i] as Map;
            final method = (f['method'] ?? 'GET').toString();
            final actionUrl = (f['action'] ?? '').toString();
            final id = (f['id'] ?? '').toString();
            final inputs = (f['inputs'] as List? ?? []).length;
            buffer.writeln('- Formulaire #$i : $method ${actionUrl.isNotEmpty ? actionUrl : '(action N/A)'} '
                '${id.isNotEmpty ? '| id=$id ' : ''}| $inputs champ(s)');
          }
          buffer.writeln('\n💡 `/forms 0` pour le détail d\'un formulaire. `/autofill` pour remplissage automatique.');
        }
        _addAssistantMessage(buffer.toString());
      }
    } else {
      state = state.copyWith(error: 'Erreur extraction formulaires : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashTables(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final action = BrowserAction(action: BrowserActionType.extractTables, params: {});
    final result = await bridge.executeAction(action);
    if (result.success && result.data != null) {
      final tables = result.data!['tables'] as List? ?? [];
      if (tables.isEmpty) {
        _addAssistantMessage('Aucun tableau trouvé sur cette page.');
      } else {
        final requestedIndex = cmd.args.isNotEmpty ? int.tryParse(cmd.args[0]) : null;
        final buffer = StringBuffer();

        if (requestedIndex != null && (requestedIndex < 0 || requestedIndex >= tables.length)) {
          state = state.copyWith(
            error: 'Index de tableau invalide: $requestedIndex (0..${tables.length - 1})',
            isStreaming: false,
          );
          return true;
        }

        final start = requestedIndex ?? 0;
        final end = requestedIndex ?? (tables.length - 1);
        final shownCount = end - start + 1;
        buffer.writeln('**$shownCount tableau(x) affiché(s)** | ${result.data!['totalRows'] ?? 0} lignes au total\n');

        for (var i = start; i <= end; i++) {
          final t = tables[i] as Map;
          buffer.writeln('### Tableau ${i + 1} : ${t['rowCount']} lignes × ${t['colCount']} colonnes');
          if (t['caption'] != null) buffer.writeln('*${t['caption']}*');
          final headers = t['headers'] as List?;
          if (headers != null && headers.isNotEmpty) {
            buffer.writeln('En-têtes : ${headers.join(' | ')}');
          }
          final rows = t['rows'] as List? ?? [];
          for (var j = 0; j < rows.length && j < 10; j++) {
            final row = rows[j] as List;
            buffer.writeln('  ${row.join(' | ')}');
          }
          if ((t['rowCount'] as int?)! > 10) buffer.writeln('  ... et ${t['rowCount']! - 10} autres lignes');
          buffer.writeln();
        }
        buffer.writeln('💡 Utilisez `/export csv` pour exporter les tableaux en CSV.');
        _addAssistantMessage(buffer.toString());
      }
    } else {
      state = state.copyWith(error: 'Erreur extraction tableaux : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashMedia(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final type = cmd.args.isNotEmpty ? cmd.args[0] : 'all';
    final action = BrowserAction(action: BrowserActionType.extractMedia, params: {});
    final result = await bridge.executeAction(action);
    if (result.success && result.data != null) {
      final images = (result.data!['images'] as List? ?? []).cast<Map>();
      final videos = (result.data!['videos'] as List? ?? []).cast<Map>();
      final audios = (result.data!['audios'] as List? ?? []).cast<Map>();
      final buffer = StringBuffer();

      void showImages() {
        buffer.writeln('**${images.length} image(s) :**');
        for (final img in images.take(15)) {
          buffer.writeln('- ![](${img['src']}) [${img['width']}×${img['height']}]');
        }
        if (images.length > 15) buffer.writeln('- ... et ${images.length - 15} autres');
      }

      void showVideos() {
        buffer.writeln('**${videos.length} vidéo(s) :**');
        for (final vid in videos.take(10)) {
          buffer.writeln('- ${vid['src'] ?? 'N/A'}');
        }
      }

      void showAudios() {
        buffer.writeln('**${audios.length} piste(s) audio :**');
        for (final a in audios.take(10)) {
          buffer.writeln('- ${a['src'] ?? 'N/A'}');
        }
      }

      switch (type) {
        case 'images':
          showImages();
          break;
        case 'videos':
          showVideos();
          break;
        case 'audio':
          showAudios();
          break;
        default:
          buffer.writeln('**Médias extraits de la page :**\n');
          if (images.isNotEmpty) showImages();
          if (videos.isNotEmpty) showVideos();
          if (audios.isNotEmpty) showAudios();
          if (images.isEmpty && videos.isEmpty && audios.isEmpty) {
            buffer.writeln('Aucun média trouvé.');
          }
      }
      buffer.writeln('\n💡 `/download <url>` pour télécharger un média. Combo : `/media images` puis `/download <url>`.');
      _addAssistantMessage(buffer.toString());
    } else {
      state = state.copyWith(error: 'Erreur extraction médias : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashMetadata(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final action = BrowserAction(action: BrowserActionType.pageMetadata, params: {});
    final result = await bridge.executeAction(action);
    if (result.success && result.data != null) {
      final d = result.data!;
      final buffer = StringBuffer();
      buffer.writeln('**Métadonnées de la page**\n');
      buffer.writeln('| Propriété | Valeur |');
      buffer.writeln('|-----------|--------|');
      void row(String k, dynamic v) {
        final val = v?.toString().replaceAll('\n', ' ').trim() ?? 'N/A';
        buffer.writeln('| $k | ${val.length > 100 ? '${val.substring(0, 100)}...' : val} |');
      }
      row('Titre', d['title']);
      row('URL', d['url']);
      row('Description', d['description']);
      row('Auteur', d['author']);
      row('Date publication', d['publishDate']);
      row('Langue', d['language']);
      row('Mots', d['wordCount']);
      row('OpenGraph Title', d['ogTitle']);
      row('OpenGraph Image', d['ogImage']);
      buffer.writeln('\n**Titres principaux :**');
      final headings = (d['headings'] as List? ?? []).cast<Map>();
      for (final h in headings.take(15)) {
        buffer.writeln('- ${h['level']} : ${h['text']}');
      }
      buffer.writeln('\n💡 `/summarize` pour résumer. `/export json` pour exporter. `/links` pour les liens.');
      _addAssistantMessage(buffer.toString());
    } else {
      state = state.copyWith(error: 'Erreur métadonnées : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashAutofill(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final action = BrowserAction(action: BrowserActionType.autoFillPage, params: {});
    final result = await bridge.executeAction(action);
    if (result.success && result.data != null) {
      final filled = result.data!['filledCount'] as int? ?? 0;
      final total = result.data!['totalInputs'] as int? ?? 0;
      _addAssistantMessage('Formulaire rempli automatiquement : **$filled / $total** champ(s).\n\n'
          '⚠️ Données de test utilisées (Jean Dupont). Modifiez les champs si nécessaire.\n'
          '💡 `/fill <sélecteur> <valeur>` pour modifier un champ spécifique. `/forms` pour voir les formulaires.');
    } else {
      state = state.copyWith(error: 'Erreur autofill : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashInspect(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      state = state.copyWith(error: 'Usage : /inspect <sélecteur CSS>', isStreaming: false);
      return true;
    }
    final action = BrowserAction(
      action: BrowserActionType.getElementInfo,
      params: {'selector': cmd.args[0]},
    );
    final result = await bridge.executeAction(action);
    if (result.success && result.data != null) {
      final d = result.data!;
      final buffer = StringBuffer();
      buffer.writeln('**Inspection : `${cmd.args[0]}`**\n');
      buffer.writeln('- Tag : `<${d['tagName']}>`');
      buffer.writeln('- ID : ${d['id'] ?? 'N/A'}');
      buffer.writeln('- Classes : ${d['className'] ?? 'N/A'}');
      buffer.writeln('- Visible : ${d['visible'] == true ? '✅' : '❌'}');
      final pos = d['position'] as Map?;
      if (pos != null) {
        buffer.writeln('- Position : x=${pos['x']}, y=${pos['y']}, ${pos['width']}×${pos['height']}');
      }
      buffer.writeln('- Contenu texte : "${d['text'] ?? ''}"');
      buffer.writeln('\n**Attributs :**');
      final attrs = (d['attributes'] as List? ?? []).cast<Map>();
      for (final a in attrs.take(20)) {
        buffer.writeln('- ${a['name']}="${a['value']}"');
      }
      buffer.writeln('\nHTML (début) : ```html\n${d['html'] ?? ''}\n```');
      buffer.writeln('\n💡 `/click ${cmd.args[0]}` pour cliquer. `/highlight ${cmd.args[0]}` pour surligner.');
      _addAssistantMessage(buffer.toString());
    } else {
      state = state.copyWith(error: 'Erreur inspection : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashHighlight(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      state = state.copyWith(error: 'Usage : /highlight <sélecteur CSS>', isStreaming: false);
      return true;
    }
    final action = BrowserAction(
      action: BrowserActionType.highlightElement,
      params: {'selector': cmd.args[0]},
    );
    final result = await bridge.executeAction(action);
    if (result.success) {
      _addAssistantMessage('Élément `${cmd.args[0]}` surligné pendant 3 secondes.');
    } else {
      state = state.copyWith(error: 'Erreur surbrillance : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashWaitFor(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      state = state.copyWith(error: 'Usage : /waitfor <sélecteur CSS> [timeout_ms]', isStreaming: false);
      return true;
    }
    final timeout = cmd.args.length > 1 ? int.tryParse(cmd.args[1]) ?? 10000 : 10000;
    final action = BrowserAction(
      action: BrowserActionType.waitForSelector,
      params: {'selector': cmd.args[0], 'timeout': timeout},
    );
    final result = await bridge.executeAction(action);
    if (result.success) {
      final waited = result.data!['waited'] as int? ?? 0;
      _addAssistantMessage('Élément `${cmd.args[0]}` apparu après ${waited}ms.\n'
          '💡 `/inspect ${cmd.args[0]}` pour l\'analyser. `/click ${cmd.args[0]}` pour cliquer dessus.');
    } else {
      state = state.copyWith(error: 'Timeout : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashExport(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final format = cmd.args.isNotEmpty ? cmd.args[0] : 'json';

    // Récupérer d'abord le contenu de la page
    final contentAction = BrowserAction(
      action: BrowserActionType.getPageContent,
      params: {},
    );
    final contentResult = await bridge.executeAction(contentAction);

    if (!contentResult.success) {
      state = state.copyWith(error: 'Erreur export : ${contentResult.error}', isStreaming: false);
      return true;
    }

    final title = contentResult.data!['title'] as String? ?? 'page';
    final content = contentResult.data!['content'] as String? ?? '';
    final url = contentResult.data!['url'] as String? ?? '';

    final safeTitle = title.replaceAll(RegExp(r'[^a-zA-Z0-9À-ɏ\s-]'), '_').trim();

    switch (format) {
      case 'json':
        final json = '{\n  "title": ${_jsonStr(title)},\n  "url": ${_jsonStr(url)},\n'
            '  "content": ${_jsonStr(content.substring(0, content.length > 10000 ? 10000 : content.length))}\n}';
        _addAssistantMessage('**Export JSON :**\n```json\n$json\n```\n\n'
            '💡 Copiez ce contenu ou utilisez `/download <url>` pour des fichiers distants.');
        break;
      case 'md':
      case 'markdown':
        final md = '# $title\n\n> Source : $url\n\n$content';
        _addAssistantMessage('**Export Markdown :**\n```markdown\n${md.substring(0, md.length > 3000 ? 3000 : md.length)}\n```\n\n'
            '${md.length > 3000 ? '(tronqué à 3000 caractères)\n\n' : ''}'
            '💡 `/pdf` pour imprimer la page. `/download` pour fichiers distants.');
        break;
      case 'csv':
        // Exporter les tableaux comme CSV
        final tableAction = BrowserAction(action: BrowserActionType.extractTables, params: {});
        final tableResult = await bridge.executeAction(tableAction);
        if (tableResult.success && tableResult.data != null) {
          final tables = tableResult.data!['tables'] as List? ?? [];
          final csvBuffer = StringBuffer();
          for (final t in tables.cast<Map>()) {
            final rows = t['rows'] as List? ?? [];
            for (final row in rows.cast<List>()) {
              csvBuffer.writeln(row.map((c) => '"${c.toString().replaceAll('"', '""')}"').join(','));
            }
            csvBuffer.writeln();
          }
          _addAssistantMessage('**Export CSV (tableaux) :**\n```csv\n${csvBuffer.toString().substring(0, 3000)}\n```\n\n'
              '💡 Les données CSV peuvent être ouvertes dans Excel / Google Sheets.');
        } else {
          _addAssistantMessage('Aucun tableau trouvé pour l\'export CSV. Utilisez `/export json` ou `/export md`.');
        }
        break;
      default:
        state = state.copyWith(error: 'Format inconnu : $format. Utilisez json, csv, ou md.', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashMonitor(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      state = state.copyWith(error: 'Usage : /monitor <sélecteur CSS> [interval_sec]', isStreaming: false);
      return true;
    }
    final selector = cmd.args[0];
    final interval = cmd.args.length > 1 ? int.tryParse(cmd.args[1]) ?? 30 : 30;
    final clampedInterval = interval.clamp(5, 300);

    // Première capture
    final action = BrowserAction(
      action: BrowserActionType.extractText,
      params: {'selector': selector},
    );
    final result = await bridge.executeAction(action);
    if (result.success) {
      final text = result.data!['text'] as String? ?? '';
      _addAssistantMessage('**Surveillance activée** : `${selector}` toutes les $clampedInterval secondes.\n\n'
          'Valeur actuelle : "${text.substring(0, text.length > 200 ? 200 : text.length)}"\n\n'
          '⚠️ La surveillance en continu nécessite l\'extension active. '
          'Relancez `/monitor $selector $clampedInterval` pour vérifier à nouveau.\n'
          '💡 Idéal pour : prix, disponibilité, score, statut. Combo : `/waitfor "${selector}:contains(\'Disponible\')"`');
    } else {
      state = state.copyWith(error: 'Erreur surveillance : ${result.error}', isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashTranslate(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final targetLang = cmd.args.isNotEmpty ? cmd.args[0] : 'fr';
    const supportedLangs = ['fr', 'en', 'es', 'de', 'it', 'pt', 'ja', 'zh', 'ar', 'ru', 'ko', 'nl'];
    if (!supportedLangs.contains(targetLang)) {
      state = state.copyWith(
        error: 'Langue non supportée : $targetLang. Supportées : ${supportedLangs.join(', ')}',
        isStreaming: false,
      );
      return true;
    }

    final contentAction = BrowserAction(
      action: BrowserActionType.getPageContent,
      params: {},
    );
    final contentResult = await bridge.executeAction(contentAction);
    if (!contentResult.success) {
      state = state.copyWith(error: 'Erreur extraction contenu : ${contentResult.error}', isStreaming: false);
      return true;
    }

    final content = contentResult.data!['content'] as String? ?? '';
    final title = contentResult.data!['title'] as String? ?? '';
    final truncated = content.length > 2000 ? '${content.substring(0, 2000)}...' : content;

    // Utiliser l'IA pour traduire (injecter comme prompt)
    final langNames = {
      'fr': 'français', 'en': 'anglais', 'es': 'espagnol', 'de': 'allemand',
      'it': 'italien', 'pt': 'portugais', 'ja': 'japonais', 'zh': 'chinois',
      'ar': 'arabe', 'ru': 'russe', 'ko': 'coréen', 'nl': 'néerlandais',
    };
    final langName = langNames[targetLang] ?? targetLang;

    final translatePrompt = 'Traduis le contenu suivant en **$langName**. '
        'Conserve la structure (titres, paragraphes, listes). '
        'Titre original : "$title"\n\n'
        'Contenu à traduire :\n\n$truncated';

    await sendMessage(translatePrompt);
    return true;
  }

  Future<bool> _handleSlashSearchPage(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      state = state.copyWith(error: 'Usage : /searchpage <terme>', isStreaming: false);
      return true;
    }
    final searchTerm = cmd.args.join(' ');

    final action = BrowserAction(
      action: BrowserActionType.getPageContent,
      params: {},
    );
    final result = await bridge.executeAction(action);
    if (!result.success) {
      state = state.copyWith(error: 'Erreur extraction page : ${result.error}', isStreaming: false);
      return true;
    }

    final content = result.data!['content'] as String? ?? '';
    final lowerContent = content.toLowerCase();
    final lowerTerm = searchTerm.toLowerCase();

    final occurrences = <int>[];
    var idx = lowerContent.indexOf(lowerTerm);
    while (idx != -1 && occurrences.length < 20) {
      occurrences.add(idx);
      idx = lowerContent.indexOf(lowerTerm, idx + 1);
    }

    if (occurrences.isEmpty) {
      _addAssistantMessage('Terme **"$searchTerm"** non trouvé dans la page.\n'
          '💡 Essayez `/summarize` pour un résumé, ou `/metadata` pour les mots-clés de la page.');
    } else {
      final buffer = StringBuffer();
      buffer.writeln('**"$searchTerm"** trouvé **${occurrences.length} fois** dans la page :\n');
      for (var i = 0; i < occurrences.length && i < 10; i++) {
        final pos = occurrences[i];
        final start = pos > 80 ? pos - 80 : 0;
        final end = pos + searchTerm.length + 80 < content.length ? pos + searchTerm.length + 80 : content.length;
        final context = content.substring(start, end).replaceAll('\n', ' ');
        final prefix = start > 0 ? '...' : '';
        final suffix = end < content.length ? '...' : '';
        buffer.writeln('${i + 1}. $prefix${context}${suffix}');
      }
      if (occurrences.length > 10) buffer.writeln('\net ${occurrences.length - 10} autres occurrences...');
      buffer.writeln('\n💡 `/extract` pour extraire une section spécifique. `/summarize` pour un résumé complet.');
      _addAssistantMessage(buffer.toString());
    }
    return true;
  }

  Future<bool> _handleSlashDocgen(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.length < 2) {
      state = state.copyWith(
        error: 'Usage : /docgen <format> <sujet> [nom_fichier]',
        isStreaming: false,
      );
      return true;
    }

    final normalizedFormat = _normalizeDocFormat(cmd.args[0]);
    final allowed = {'pdf', 'word', 'powerpoint', 'excel', 'markdown', 'text'};
    if (!allowed.contains(normalizedFormat)) {
      state = state.copyWith(
        error: 'Format non supporte: ${cmd.args[0]}. Utilisez pdf, word, powerpoint, excel, markdown, text.',
        isStreaming: false,
      );
      return true;
    }

    final topic = cmd.args[1];
    final customFileName = cmd.args.length > 2 ? cmd.args[2] : null;

    state = state.copyWith(error: null, isStreaming: true, isSearching: true);

    try {
      final appLang = ref.read(lang.languageProvider);
      final searchService = ref.read(searchServiceProvider);
      List<WebSearchResult> searchResults = [];
      String searchContext = '';
      try {
        searchResults = await searchService.searchWithFallback(topic, lang: appLang.name);
        searchContext = searchService.formatForAi(searchResults, topic);
      } catch (e) {
        debugPrint('[Docgen] Search failed, continuing without web context: $e');
      }

      final isPro = await ref.read(isProProvider.future).catchError((_) => false);
      final draft = await _generateDocumentDraft(
        topic: topic,
        format: normalizedFormat,
        searchContext: searchContext,
        isPro: isPro,
      );

      final title = _extractDocumentTitle(draft, fallbackTopic: topic);
      final sources = searchResults
          .map((r) => '${r.title} — ${r.url}')
          .toList(growable: false);

      final generated = await ref.read(documentGenerationServiceProvider).generate(
        format: normalizedFormat,
        title: title,
        body: draft,
        sources: sources,
        preferredFileName: customFileName,
      );

      // Download / share the generated document
      bool downloadOk = false;
      String? downloadError;

      if (bridge.isExtension) {
        final action = BrowserAction(
          action: BrowserActionType.downloadData,
          params: {
            'contentBase64': generated.base64Content,
            'mimeType': generated.mimeType,
            'filename': generated.fileName,
          },
        );
        final result = await bridge.executeAction(action);
        downloadOk = result.success;
        downloadError = result.error;
      } else if (PlatformService.isMobile) {
        // Mobile: share the file via system share sheet
        try {
          final xFile = XFile.fromData(
            generated.bytes,
            name: generated.fileName,
            mimeType: generated.mimeType,
          );
          await Share.shareXFiles(
            [xFile],
            subject: generated.fileName,
            text: 'Document genere par Corely: ${generated.fileName}',
          );
          downloadOk = true;
        } catch (e) {
          downloadError = 'Partage echoue: $e';
          debugPrint('[Docgen] Mobile share failed: $e');
        }
      }

      // Fallback: embed document content in chat message
      if (!downloadOk) {
        final shortPreview = draft.length > 800 ? '${draft.substring(0, 800)}...' : draft;
        final downloadHint = bridge.isExtension
            ? '\n\n_Telechargement echoue: ${downloadError ?? "inconnu"}._'
            : PlatformService.isMobile
                ? '\n\n_Partage echoue: ${downloadError ?? "inconnu"}._'
                : '\n\n_Le document sera disponible via le partage._';
        _addAssistantMessage(
          'Document genere: **${generated.fileName}** (${generated.sizeBytes} octets)\n'
          'Format: $normalizedFormat\n\n'
          '---\n\n$shortPreview\n'
          '---$downloadHint\n\n'
          'La generation combine les connaissances IA et les resultats web recents.',
        );
      } else {
        final shortPreview = draft.length > 500 ? '${draft.substring(0, 500)}...' : draft;
        _addAssistantMessage(
          'Document genere: ${generated.fileName} (${generated.sizeBytes} octets).\n'
          'Format: $normalizedFormat\n\n'
          'Apercu:\n$shortPreview\n\n'
          'La generation combine les connaissances IA et les resultats web recents.',
        );
      }
    } on AiException catch (e) {
      state = state.copyWith(
        error: _formatAiError(e),
        isStreaming: false,
        isSearching: false,
      );
    } catch (e) {
      state = state.copyWith(
        error: 'Erreur generation document: $e',
        isStreaming: false,
        isSearching: false,
      );
    } finally {
      if (state.isStreaming || state.isSearching) {
        state = state.copyWith(isStreaming: false, isSearching: false);
      }
    }

    return true;
  }

  String _normalizeDocFormat(String raw) {
    final lower = raw.toLowerCase();
    if (lower == 'txt' || lower == 'text') return 'text';
    if (lower == 'md' || lower == 'markdown') return 'markdown';
    if (lower == 'doc' || lower == 'docx' || lower == 'word') return 'word';
    if (lower == 'ppt' || lower == 'pptx' || lower == 'powerpoint') return 'powerpoint';
    if (lower == 'xls' || lower == 'xlsx' || lower == 'excel') return 'excel';
    if (lower == 'pdf') return 'pdf';
    return lower;
  }

  Future<String> _generateDocumentDraft({
    required String topic,
    required String format,
    required String searchContext,
    required bool isPro,
  }) async {
    final system = 'Tu es un redacteur expert. Tu produis des documents finalisables '
      'avec structure claire, sections numerotees, contenu factuel verifiable, '
        'et un bloc "Images suggerees" qui decrit les visuels utiles.';

    final user = 'Genere un document complet sur: "$topic". '
      'Format cible: $format. '
      'Utilise a la fois tes connaissances et le contexte web ci-dessous. '
      'Le document doit inclure: titre, resume executif, sections detaillees, '
      'plan d\'actions, references et images suggerees (description + utilite). '
        'Ecris en francais sauf si le sujet impose une autre langue.\n\n'
        'Contexte web:\n$searchContext';

    final history = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];

    final stream = _getDirectAiStream(history, isPro);
    final buffer = StringBuffer();
    await for (final token in stream) {
      buffer.write(token);
    }

    final generated = buffer.toString().trim();
    if (generated.isEmpty) {
      throw const AiException('Generation vide');
    }
    return generated;
  }

  String _extractDocumentTitle(String draft, {required String fallbackTopic}) {
    final h1 = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(draft)?.group(1);
    if (h1 != null && h1.trim().isNotEmpty) {
      return h1.trim();
    }

    final firstLine = draft
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => fallbackTopic)
        .replaceAll(RegExp(r'^[\-\d.\s]+'), '');

    final safe = firstLine.isEmpty ? fallbackTopic : firstLine;
    return safe.length > 80 ? safe.substring(0, 80) : safe;
  }

  String _jsonStr(String s) => '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')}"';

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

    // Slash commands: intercept before AI processing.
    // Sur mobile, handleSlashCommand renvoie une erreur explicite.
    if (trimmed.startsWith('/')) {
      final handled = await handleSlashCommand(trimmed);
      if (handled) return;
      state = state.copyWith(
        error: 'Commande slash inconnue ou non supportee: $trimmed',
        isStreaming: false,
      );
      return;
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

    final attachmentContext = _buildAttachmentContextForHistory(
      text: trimmed,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      fileName: fileName,
      fileContent: fileContent,
      isPro: isPro,
    );

    // 1. Persister le message utilisateur dans le repo
    final userMsg = isDemoMode
        ? await mockChatRepository.addMessage(
            conversationId: arg,
            role: Role.user,
            content: trimmed,
            imageBase64: imageBase64,
            imageMimeType: imageMimeType,
            fileName: fileName,
            fileContext: attachmentContext,
          )
        : await ref.read(chatRepositoryProvider).addMessage(
            conversationId: arg,
            role: Role.user,
            content: trimmed,
            imageBase64: imageBase64,
            imageMimeType: imageMimeType,
            fileName: fileName,
            fileContext: attachmentContext,
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

    // Recherche enrichie (météo, vols, hôtels, produits, events, restaurants, etc.)
    // indépendamment de shouldSearch, pour supporter toutes les langues.
    List<WebSearchResult>? searchResults;
    InstantAnswer? instantAnswer;
    String? enhancedResultMarkdown;

    final appLang = ref.read(lang.languageProvider);
    final extractor = SearchIntentExtractor();
    final searchParams = extractor.extract(userMsg.content, appLang);
    final intent = searchParams.intent;

    if (intent != 'general') {
      try {
        enhancedResultMarkdown = await _performEnhancedSearch(
            userMsg.content, intent, _extractSearchQuery(userMsg.content), appLang, searchParams);
        // Record successful extraction for learning
        extractor.memory.recordSuccess(intent, userMsg.content, searchParams);
      } catch (e) {
        debugPrint('[ChatNotifier] Recherche enrichie echouee : $e');
      }
    }

    // Recherche web classique — uniquement si l'utilisateur l'a activée OU si l'intent le nécessite
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
            enhancedContext: enhancedResultMarkdown,
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

      // Prepend enhanced search results (products, flights, hotels, weather)
      if (enhancedResultMarkdown != null && enhancedResultMarkdown.isNotEmpty) {
        finalContent = '$enhancedResultMarkdown\n\n$finalContent';
      }

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

  String? _buildAttachmentContextForHistory({
    required String text,
    String? imageBase64,
    String? imageMimeType,
    String? fileName,
    String? fileContent,
    required bool isPro,
  }) {
    if (fileContent != null && fileContent.isNotEmpty) {
      var doc = FileUploadService.truncateForContext(fileContent, isPro: isPro);
      if (doc.length > 6000) {
        doc = '${doc.substring(0, 6000)}\n\n[... contexte fichier compacté ...]';
      }
      final label = fileName ?? 'document';
      if (imageBase64 != null && imageBase64.isNotEmpty) {
        final mime = imageMimeType ?? 'image/jpeg';
        return 'Document utilisateur: $label\n'
            'Aperçu image extrait: $mime\n\n$doc';
      }
      return 'Document utilisateur: $label\n\n$doc';
    }

    if (imageBase64 != null && imageBase64.isNotEmpty) {
      final mime = imageMimeType ?? 'image/jpeg';
      final prompt = text.isNotEmpty ? text : 'Analyse cette image';
      return 'Image utilisateur jointe ($mime).\nDemande associée: $prompt';
    }

    return null;
  }

  Future<Stream<String>> _buildStream(
    Message userMsg,
    bool isPro, {
    List<WebSearchResult>? searchResults,
    InstantAnswer? instantAnswer,
    String? fileContent,
    String? fileName,
    String? enhancedContext,
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

    // Réinjecter un contexte fichier persistant pour les tours suivants.
    // On ne le fait pas lorsqu'un nouveau document est déjà fourni dans ce tour.
    if (fileContent == null || fileContent.isEmpty) {
      final fileContexts = historyMessages
          .where((m) => m.fileContext != null && m.fileContext!.isNotEmpty)
          .toList();
      for (final ctx in fileContexts.reversed.take(3).toList().reversed) {
        historyMessages.insert(0, Message(
          id: 'file_ctx_hist_${ctx.id}',
          conversationId: arg,
          role: Role.system,
          content: 'Contexte fichier deja partage plus tot dans cette conversation. '
              'Utilise-le si la question courante y fait reference.\n\n${ctx.fileContext!}',
          createdAt: DateTime.now(),
        ));
      }
    }

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

    if (enhancedContext != null && enhancedContext.isNotEmpty) {
      historyMessages.insert(0, Message(
        id: 'enhanced_context_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: arg,
        role: Role.system,
        content: 'Voici les résultats de recherche structurée (vols, hôtels, '
            'météo, produits) pour la question de l\'utilisateur. '
            'Présente ces résultats de façon naturelle et utile. '
            'Si les résultats contiennent des liens, mentionne-les. '
            'Ne dis JAMAIS que tu n\'as pas accès aux systèmes de réservation '
            'puisque les données sont déjà là ci-dessous.\n\n'
            '$enhancedContext',
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
  /// Priorite : Ollama (si configure) > OpenRouter GPT-4o-mini > DeepSeek chat.
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
      try {
        yield* DeepSeekClient(apiKey: deepSeekKey).streamChat(
          messages: history,
          model: AppConstants.deepSeekVisionModel,
          // Plusieurs APIs vision refusent la recherche web en mode image.
          enableSearch: false,
        );
        return;
      } on AiException catch (e) {
        debugPrint('[ChatNotifier] DeepSeek vision error: ${e.message}');
      }
    }

    throw const AiException(
      'Analyse d\'image indisponible. Verifiez la cle DeepSeek (vision) '
      'ou ajoutez une cle OpenRouter.',
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
      return 'Analyse d\'image indisponible avec le fournisseur actuel. '
          'Verifiez d\'abord la cle DeepSeek, puis OpenRouter si besoin.';
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
    // Mots-clés déclencheurs : informations factuelles/temporelles (multilingue)
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
      'le moins cher', 'meilleur prix', 'pas cher', 'acheter', 'comparer',
      'billet d\'avion', 'vol direct', 'vols pas', 'vol pour',
      'hotel', 'hôtel', 'logement', 'airbnb', 'réservation',
      'pleuvoir', 'température', 'quel temps', 'pluie',
      'site pour', 'où acheter', 'trouve le', 'trouve moi',
      'cherche le', 'cherche moi', 'recherche le',
      'xiaomi', 'iphone', 'samsung', 'téléphone', 'smartphone',
      // EN
      'what is', 'who is', 'where is', 'when is', 'why is', 'how is',
      'how much', 'how many', 'price of', 'cost of',
      'weather', 'forecast', 'rain', 'stock', 'score of',
      'cheapest', 'best price', 'buy', 'where to buy',
      'flight', 'flights', 'plane ticket',
      // ES
      'qué es', 'quién es', 'dónde está', 'cuándo es', 'cuánto',
      'clima', 'lluvia', 'pronóstico', 'precio de',
      'más barato', 'comprar', 'vuelo', 'vuelos',
      // DE
      'was ist', 'wer ist', 'wo ist', 'wann ist', 'wie viel',
      'wetter', 'regen', 'vorhersage', 'preis von',
      'günstigste', 'kaufen', 'flug', 'flüge',
      // IT
      'cosa è', 'chi è', 'dov\'è', 'quando è', 'quanto',
      'meteo', 'pioggia', 'previsioni', 'prezzo di',
      'più economico', 'comprare', 'volo', 'voli',
      // PT
      'o que é', 'quem é', 'onde está', 'quando é', 'quanto',
      'clima', 'chuva', 'previsão', 'preço de',
      'mais barato', 'comprar', 'voo', 'voos',
    ];
    // Mots-clés exclus : créativité, code, opinion, conversation (multilingue)
    final excludeWords = [
      'écris', 'ecris', 'rédige', 'redige', 'raconte', 'invente',
      'imagine', 'crée', 'cree', 'dessine', 'compose',
      'code', 'programme', 'fonction', 'script', 'algorithme',
      'explique-moi', 'explique comment', 'pourquoi le',
      'qu\'en penses-tu', 'ton avis', 'selon toi',
      'story', 'poème', 'poeme', 'chanson', 'blague',
      // EN
      'write a', 'compose a', 'imagine', 'create a', 'draw',
      'code a', 'program', 'function', 'what do you think',
      'your opinion', 'story', 'poem', 'song', 'joke',
      // ES
      'escribe', 'redacta', 'imagina', 'crea', 'dibuja',
      'programa', 'función', 'qué opinas', 'poema', 'canción',
      // DE
      'schreibe', 'erfinde', 'erstelle', 'zeichne',
      'programmiere', 'funktion', 'was denkst du', 'gedicht',
      // IT
      'scrivi', 'inventa', 'immagina', 'crea', 'disegna',
      'programma', 'funzione', 'cosa pensi', 'poesia',
      // PT
      'escreve', 'inventa', 'imagina', 'cria', 'desenha',
      'programa', 'função', 'o que achas', 'poema',
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

  // ── Enhanced search ────────────────────────────────────────────────────────

  /// Classify search intent from user message.
  /// Returns 'products', 'flights', 'hotels', 'weather', or 'general'.
  /// Kept as static for test backward compatibility; delegates to LanguageService.
  static String classifySearchIntent(String message) {
    return lang.classifySearchIntent(message, lang.AppLanguage.fr);
  }

  /// Execute enhanced search and return formatted markdown.
  Future<String?> _performEnhancedSearch(
      String message, String intent, String searchQuery, lang.AppLanguage language,
      [SearchParams? params]) async {
    final service = ref.read(enhancedSearchServiceProvider);
    switch (intent) {
      case 'products':
        final productQuery = _buildProductSearchQuery(searchQuery, params);
        var products = await service.searchProducts(productQuery,
            hl: language.serpApiHl, gl: language.serpApiGl);
        if (products.isEmpty) {
          products = await service.searchGoogleShopping(productQuery,
              hl: language.serpApiHl, gl: language.serpApiGl);
        }
        if (products.isNotEmpty) {
          return EnhancedSearchService.formatProducts(products, productQuery);
        }
        return null;

      case 'bestdeal':
        final dealQuery = _buildProductSearchQuery(searchQuery, params);
        final dealProducts = await service.searchBestDeal(dealQuery,
            hl: language.serpApiHl, gl: language.serpApiGl);
        if (dealProducts.isNotEmpty) {
          return EnhancedSearchService.formatBestDeal(dealProducts, dealQuery);
        }
        return null;

      case 'secondhand':
        final condition = params?.condition ?? 'used';
        final usedQuery = _buildProductSearchQuery(searchQuery, params);
        final usedProducts = await service.searchSecondHand(usedQuery,
            hl: language.serpApiHl, gl: language.serpApiGl, condition: condition);
        if (usedProducts.isNotEmpty) {
          return EnhancedSearchService.formatSecondHand(usedProducts, usedQuery);
        }
        return null;

      case 'flights':
        var parsed = params?.fromLocation != null
            ? {
                'from': params!.fromLocation!,
                'to': params.toLocation ?? '',
                'departDate': params.departDate ?? '',
                if (params.returnDate != null) 'returnDate': params.returnDate!,
              }
            : null;

        // Validate: if extracted params look like garbage (too many words,
        // contain flight-related terms), fall back to the reliable parser
        if (parsed != null && !_isValidCityPair(parsed['from']!, parsed['to']!)) {
          parsed = parseFlightParams(message);
        }

        parsed ??= parseFlightParams(message);
        if (parsed == null) return null;
        final flights = await service.searchFlights(
          from: parsed['from']!,
          to: parsed['to']!,
          departDate: parsed['departDate']!,
          returnDate: parsed['returnDate'],
          hl: language.serpApiHl,
          gl: language.serpApiGl,
        );
        if (flights.isNotEmpty) {
          return EnhancedSearchService.formatFlights(flights);
        }
        return null;

      case 'hotels':
        final hotelQuery = params?.location?.isNotEmpty == true
            ? params!.location!
            : searchQuery;
        final hotels = await service.searchHotels(
          hotelQuery,
          hl: language.serpApiHl,
          gl: language.serpApiGl,
          checkIn: params?.checkIn,
          checkOut: params?.checkOut,
          guests: params?.guests,
        );
        if (hotels.isNotEmpty) {
          return EnhancedSearchService.formatHotels(hotels, hotelQuery);
        }
        return null;

      case 'events':
        final events = await service.searchEvents(searchQuery,
            hl: language.serpApiHl, gl: language.serpApiGl, domain: params?.domain);
        if (events.isNotEmpty) {
          return EnhancedSearchService.formatEvents(events, searchQuery, domain: params?.domain);
        }
        return null;

      case 'restaurants':
        final location = params?.location ?? searchQuery;
        final restaurants = await service.searchRestaurants(searchQuery, location,
            hl: language.serpApiHl, gl: language.serpApiGl);
        if (restaurants.isNotEmpty) {
          return EnhancedSearchService.formatRestaurants(restaurants, searchQuery);
        }
        return null;

      case 'rentals':
        final rentals = await service.searchRentals(searchQuery,
            checkIn: params?.checkIn,
            checkOut: params?.checkOut,
            guests: params?.guests,
            hl: language.serpApiHl,
            gl: language.serpApiGl);
        if (rentals.isNotEmpty) {
          return EnhancedSearchService.formatRentals(rentals, searchQuery);
        }
        return null;

      case 'weather':
        final weatherService = ref.read(weatherServiceProvider);
        WeatherData? weather;
        final city = extractCity(message);
        final zip = extractZipCode(message);

        if (city != null) {
          weather = await weatherService.getCurrentWeather(city: city, lang: language.owmLang);
        } else if (zip != null) {
          weather = await weatherService.getCurrentWeather(postalCode: zip, lang: language.owmLang);
        } else {
          final locationService = ref.read(locationServiceProvider);
          final location = await locationService.getCurrentLocation();
          if (location != null) {
            weather = await weatherService.getCurrentWeather(
              lat: location.latitude,
              lon: location.longitude,
              lang: language.owmLang,
            );
          }
        }

        if (weather != null) {
          return WeatherService.formatMarkdown(weather);
        }
        return '_Données météo indisponibles. Essayez avec un nom de ville._';

      default:
        return null;
    }
  }

  static String _buildProductSearchQuery(String searchQuery, SearchParams? params) {
    final tokens = <String>[searchQuery.trim()];
    void add(String? value) {
      if (value == null || value.trim().isEmpty) return;
      final v = value.trim();
      if (!tokens.any((t) => t.toLowerCase().contains(v.toLowerCase()))) {
        tokens.add(v);
      }
    }

    add(params?.category);
    add(params?.color);
    if (params?.condition == 'refurbished') add('reconditionné');
    if (params?.condition == 'used') add('occasion');
    if (params?.priceRange == 'cheapest') add('meilleur prix');

    return tokens.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ── Flight/Weather parameter parsers ──────────────────────────────────────

  /// Validate that extracted city names look like actual cities, not random
  /// words from the query. City names should be 1-3 words and not contain
  /// flight-related terms.
  static bool _isValidCityPair(String from, String to) {
    const garbageTerms = [
      'trouve', 'trouver', 'cherche', 'chercher', 'billet', 'billets',
      'vol', 'vols', 'avion', 'aller', 'retour', 'direct', 'recherche',
      'reservation', 'reserver', 'partir', 'depart', 'arrivee',
      'flight', 'flights', 'ticket', 'find', 'search', 'cheap',
    ];
    final fromWords = from.split(' ').length;
    final toWords = to.split(' ').length;
    // City names are 1-3 words (e.g., "New York", "Sao Paulo", "Buenos Aires")
    if (fromWords > 3 || toWords > 3) return false;
    final fromLower = from.toLowerCase();
    final toLower = to.toLowerCase();
    for (final term in garbageTerms) {
      if (fromLower == term || toLower == term) return false;
      if (fromLower.contains(' $term ') || toLower.contains(' $term ')) return false;
      if (fromLower.startsWith('$term ') || toLower.startsWith('$term ')) return false;
      if (fromLower.endsWith(' $term') || toLower.endsWith(' $term')) return false;
    }
    return true;
  }

  /// Parse flight search parameters from natural language.
  /// Handles: "Paris-Zagreb du 29 mai au 2 juin",
  /// "vol Paris-Zagreb du 29/05 au 02/06",
  /// "billet avion Paris Zagreb 15 juin", etc.
  static Map<String, String>? parseFlightParams(String message) {
    // Try original message first (handles properly capitalized input)
    var result = _tryParseFlightParams(message);
    if (result != null) return result;

    // Fallback: clean stop words + capitalize for lowercase queries
    final cleaned = _sanitizeFlightQuery(message);
    final capitalized = cleaned.replaceAllMapped(
      RegExp(r'\b([a-zà-ÿ])'),
      (m) => m.group(1)!.toUpperCase(),
    );
    if (capitalized != cleaned) {
      return _tryParseFlightParams(capitalized);
    }
    return null;
  }

  /// Remove common flight-related stop words that interfere with city extraction.
  static String _sanitizeFlightQuery(String msg) {
    const stopWords = [
      'vol', 'vols', 'billet', 'billets', 'avion', 'avions',
      'aller', 'retour', 'direct', 'directs', 'cher', 'chers',
      'moins', 'trouver', 'trouve', 'cherche', 'chercher',
      'recherche', 'rechercher', 'depart', 'arrivee', 'reservation',
      'reserver', 'partir', 'pour', 'via', 'avec', 'sur',
      'flight', 'flights', 'ticket', 'tickets', 'cheap', 'find',
      'search', 'one', 'way', 'round', 'trip', 'from', 'and',
      'pas', 'les', 'des', 'une', 'mon', 'mes', 'ton', 'tes',
      'son', 'ses', 'notre', 'nos', 'votre', 'vos', 'leur', 'leurs',
      'quel', 'quels', 'quelle', 'quelles', 'est', 'sont',
      'me', 'le', 'la', 'du', 'de', 'au', 'aux',
    ];
    var cleaned = msg;
    for (final w in stopWords) {
      cleaned = cleaned.replaceAll(RegExp('\\b$w\\b', caseSensitive: false), ' ');
    }
    // Collapse multiple spaces
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Map<String, String>? _tryParseFlightParams(String message) {
    const cityName = r'[A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?';
    const numericDate = r'\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}';
    const months =
        r'[Jj]anvier|[Ff]évrier|[Ff]evrier|[Mm]ars|[Aa]vril|[Mm]ai|'
        r'[Jj]uillet|[Jj]uin|[Aa]oût|[Aa]out|[Ss]eptembre|[Oo]ctobre|'
        r'[Nn]ovembre|[Dd]écembre|[Dd]ecembre|'
        r'[Jj]anuary|[Ff]ebruary|[Mm]arch|[Aa]pril|[Mm]ay|'
        r'[Jj]uly|[Jj]une|[Aa]ugust|[Ss]eptember|[Oo]ctober|'
        r'[Nn]ovember|[Dd]ecember';

    // Pattern A: "City1-City2 du DD mois au DD mois" (hyphen, text dates)
    // Matches: "Paris-Zagreb du 29 mai au 2 juin"
    final hyphenTextDates = RegExp(
      '($cityName)\\s*-\\s*($cityName)\\b'
      r'.{0,30}?'
      r'(?:d[ue]|le|départ\s+le)\s+(\d{1,2})\s+'
      '($months)'
      r'(?:\s*(?:au|retour(?:\s+le)?)\s+(\d{1,2})\s+(' + months + r'))?',
    );
    final matchA = hyphenTextDates.firstMatch(message);
    if (matchA != null) {
      final d1 = int.parse(matchA.group(3)!);
      final m1 = lang.parseMonth(matchA.group(4)!);
      final y = DateTime.now().year;
      final departDate =
          '$y-${m1.toString().padLeft(2, '0')}-${d1.toString().padLeft(2, '0')}';
      String? returnDate;
      if (matchA.group(5) != null) {
        final d2 = int.parse(matchA.group(5)!);
        final m2 = lang.parseMonth(matchA.group(6)!);
        returnDate =
            '$y-${m2.toString().padLeft(2, '0')}-${d2.toString().padLeft(2, '0')}';
      }
      return {
        'from': matchA.group(1)!.trim(),
        'to': matchA.group(2)!.trim(),
        'departDate': departDate,
        if (returnDate != null) 'returnDate': returnDate,
      };
    }

    // Pattern B: "City1-City2 du date1 au date2" (hyphen, numeric dates)
    // Matches: "Paris-Zagreb du 29/05/2026 au 02/06/2026"
    final hyphenNumDates = RegExp(
      '($cityName)\\s*-\\s*($cityName)\\b'
      r'.{0,20}?'
      '(?:d[ue]|le)\\s+(' + numericDate + r')'
      r'(?:\s+(?:au|retour)\s+(' + numericDate + r'))?',
    );
    final matchB = hyphenNumDates.firstMatch(message);
    if (matchB != null) {
      return {
        'from': matchB.group(1)!.trim(),
        'to': matchB.group(2)!.trim(),
        'departDate': normalizeDate(matchB.group(3)!),
        if (matchB.group(4) != null)
          'returnDate': normalizeDate(matchB.group(4)!),
      };
    }

    // Pattern C: "City1 City2 du DD mois au DD mois" (space/separator, text dates)
    // Matches: "vol Paris Zagreb du 29 mai au 2 juin", "vol direct Paris Zagreb 29 mai 2026"
    final spaceTextDates = RegExp(
      '($cityName)\\s+'
      r'(?:à|vers|pour|-)?\s*'
      '($cityName)\\b'
      r'.{0,30}?'
      r'(?:d[ue]|le\s+)?(\d{1,2})\s+'
      '($months)'
      r'(?:\s*(?:au|retour)\s+(\d{1,2})\s+(' + months + r'))?',
    );
    final matchC = spaceTextDates.firstMatch(message);
    if (matchC != null) {
      final d1 = int.parse(matchC.group(3)!);
      final m1 = lang.parseMonth(matchC.group(4)!);
      final y = DateTime.now().year;
      final departDate =
          '$y-${m1.toString().padLeft(2, '0')}-${d1.toString().padLeft(2, '0')}';
      String? returnDate;
      if (matchC.group(5) != null) {
        final d2 = int.parse(matchC.group(5)!);
        final m2 = lang.parseMonth(matchC.group(6)!);
        returnDate =
            '$y-${m2.toString().padLeft(2, '0')}-${d2.toString().padLeft(2, '0')}';
      }
      return {
        'from': matchC.group(1)!.trim(),
        'to': matchC.group(2)!.trim(),
        'departDate': departDate,
        if (returnDate != null) 'returnDate': returnDate,
      };
    }

    // Pattern D: "City1 City2 numericDate" — compact with numeric date
    final compact = RegExp(
      '(?:de\\s+)?($cityName)\\s+'
      r'(?:à|vers|pour|-)?\s*'
      '($cityName)',
    );
    final matchD = compact.firstMatch(message);
    final dateFinder = RegExp('($numericDate)');
    final dateMatch = dateFinder.firstMatch(message);
    if (matchD != null && dateMatch != null) {
      return {
        'from': matchD.group(1)!.trim(),
        'to': matchD.group(2)!.trim(),
        'departDate': normalizeDate(dateMatch.group(1)!),
      };
    }

    return null;
  }

  /// Extract city name from weather-related message.
  static String? extractCity(String message) {
    var result = _tryExtractCity(message);
    if (result != null) return result;

    // Fallback: capitalize first letter of each word for lowercase queries
    final capitalized = message.replaceAllMapped(
      RegExp(r'\b([a-zà-ÿ])'),
      (m) => m.group(1)!.toUpperCase(),
    );
    if (capitalized != message) {
      return _tryExtractCity(capitalized);
    }
    return null;
  }

  static String? _tryExtractCity(String message) {
    // Pattern: "météo Paris", "temps à Lyon", "weather in London", etc.
    const city = r'([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?)';
    final patterns = [
      RegExp(r'(?:météo|meteo|temps|pleuvoir|température|temperature|weather|clima|tempo|wetter)\s+(?:à|de|pour|sur|in|en|a|em|bei)\s+' + city),
      RegExp(r'(?:météo|meteo|temps|pleuvoir|température|temperature|weather|clima|tempo|wetter)\s+' + city),
      RegExp(r'(?:fait-il|fera-t-il|how is the weather|como está el clima|wie ist das wetter)\s+(?:à|de|pour|sur|in|en|a|em|bei)\s+' + city),
      RegExp(r"(?:est-ce qu'il|va-t-il)\s+\w+\s+(?:à|de|pour|sur|in|en|a|em|bei)\s+" + city),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(message);
      if (match != null) return match.group(1)!.trim();
    }
    return null;
  }

  /// Extract postal code from weather-related message.
  static String? extractZipCode(String message) {
    final match = RegExp(r'\b(\d{5})\b').firstMatch(message);
    if (match != null) return match.group(1);
    return null;
  }

  static String normalizeDate(String raw) {
    // Accept dd/mm/yyyy, dd-mm-yyyy, dd.mm.yyyy → yyyy-mm-dd
    final parts = raw.trim().split(RegExp(r'[/.-]'));
    if (parts.length == 3) {
      try {
        final d = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        var y = int.parse(parts[2]);
        if (y < 100) y += 2000;
        return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }

  static int parseMonth(String name) {
    return lang.parseMonth(name);
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
