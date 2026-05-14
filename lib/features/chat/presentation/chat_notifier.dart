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
import '../data/enhanced_search_service.dart';
import '../data/weather_service.dart';
import '../data/location_service.dart';
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
final enhancedSearchServiceProvider =
    Provider((ref) => EnhancedSearchService());
final weatherServiceProvider = Provider((ref) => WeatherService());
final locationServiceProvider = Provider((ref) => LocationService());

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
  /// Retourne true si la commande a ete traitee (ne pas envoyer a l'IA).
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

    // Add natural language user message to conversation
    final naturalText = parsed.toNaturalLanguage();
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
        buffer.writeln('**$count formulaire(s) trouvé(s) :**\n');
        for (var i = 0; i < forms.length; i++) {
          final f = forms[i] as Map;
          final inputs = (f['inputs'] as List? ?? []).cast<Map>();
          buffer.writeln('### Formulaire ${i + 1}');
          buffer.writeln('- Action : ${f['action'] ?? 'page courante'}');
          buffer.writeln('- Méthode : ${f['method'] ?? 'GET'}');
          buffer.writeln('- ${inputs.length} champ(s) :');
          for (final input in inputs.take(15)) {
            final required = input['required'] == true ? ' *' : '';
            buffer.writeln('  - `${input['name']}` (${input['type']})$required');
          }
          if (inputs.length > 15) buffer.writeln('  - ... et ${inputs.length - 15} autres');
          buffer.writeln();
        }
        if (cmd.args.isNotEmpty) {
          final idx = int.tryParse(cmd.args[0]) ?? 0;
          buffer.writeln('💡 Utilisez `/autofill` pour remplir automatiquement le formulaire ${idx}.');
        } else {
          buffer.writeln('💡 `/forms 0` pour voir le 1er formulaire. `/autofill` pour remplissage automatique.');
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
        final buffer = StringBuffer();
        buffer.writeln('**${tables.length} tableau(x) trouvé(s)** | ${result.data!['totalRows'] ?? 0} lignes au total\n');
        for (var i = 0; i < tables.length; i++) {
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
    String? enhancedResultMarkdown;
    final shouldSearch = state.useSearch || _needsWebSearch(userMsg.content);
    if (shouldSearch) {
      try {
        state = state.copyWith(isSearching: true);
        final searchService = ref.read(searchServiceProvider);
        final searchQuery = _extractSearchQuery(userMsg.content);

        // Déterminer le type de recherche enrichie
        final intent = classifySearchIntent(userMsg.content);
        if (intent != 'general') {
          enhancedResultMarkdown = await _performEnhancedSearch(
              userMsg.content, intent, searchQuery);
        }

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
      // Enhanced search triggers
      'le moins cher', 'meilleur prix', 'pas cher', 'acheter', 'comparer',
      'billet d\'avion', 'vol direct', 'vols pas', 'vol pour',
      'hotel', 'hôtel', 'logement', 'airbnb', 'réservation',
      'pleuvoir', 'température', 'quel temps', 'pluie',
      'site pour', 'où acheter', 'trouve le', 'trouve moi',
      'cherche le', 'cherche moi', 'recherche le',
      'xiaomi', 'iphone', 'samsung', 'téléphone', 'smartphone',
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

  // ── Enhanced search ────────────────────────────────────────────────────────

  /// Classify search intent from user message.
  /// Returns 'products', 'flights', 'hotels', 'weather', or 'general'.
  static String classifySearchIntent(String message) {
    final lower = message.toLowerCase();

    // Weather patterns
    if (lower.contains('météo') || lower.contains('meteo') ||
        lower.contains('pleuvoir') || lower.contains('température') ||
        lower.contains('temperature') || lower.contains('quel temps') ||
        lower.contains('pluie') || lower.contains('temps fait') ||
        lower.contains('prévisions') || lower.contains('previsions')) {
      return 'weather';
    }

    // Flight patterns
    if (lower.contains('billet') || lower.contains('vol ') ||
        lower.contains('vols ') || lower.contains('avion') ||
        lower.contains('aller-retour') || lower.contains('aller retour') ||
        (lower.contains('direct') &&
            (lower.contains('paris') || lower.contains('vol')))) {
      return 'flights';
    }

    // Hotel patterns
    if (lower.contains('hotel') || lower.contains('hôtel') ||
        lower.contains('airbnb') || lower.contains('logement') ||
        lower.contains('booking') || lower.contains('nuit ') ||
        lower.contains('nuits ') || lower.contains('séjour') ||
        lower.contains('sejour') || lower.contains('réservation') ||
        lower.contains('reservation') || lower.contains('hebergement') ||
        lower.contains('hébergement')) {
      return 'hotels';
    }

    // Product patterns
    if (lower.contains('moins cher') || lower.contains('meilleur prix') ||
        lower.contains('acheter') || lower.contains('trouve le') ||
        lower.contains('trouve moi') || lower.contains('cherche le') ||
        lower.contains('cherche moi') || lower.contains('prix le plus bas') ||
        lower.contains('comparer') || lower.contains('le moins cher')) {
      return 'products';
    }

    return 'general';
  }

  /// Execute enhanced search and return formatted markdown.
  Future<String?> _performEnhancedSearch(
      String message, String intent, String searchQuery) async {
    switch (intent) {
      case 'products':
        final service = ref.read(enhancedSearchServiceProvider);
        var products = await service.searchProducts(searchQuery);
        if (products.isEmpty) {
          products = await service.searchGoogleShopping(searchQuery);
        }
        if (products.isNotEmpty) {
          return EnhancedSearchService.formatProducts(products, searchQuery);
        }
        return null;

      case 'flights':
        final parsed = parseFlightParams(message);
        if (parsed == null) return null;
        final service = ref.read(enhancedSearchServiceProvider);
        final flights = await service.searchFlights(
          from: parsed['from']!,
          to: parsed['to']!,
          departDate: parsed['departDate']!,
          returnDate: parsed['returnDate'],
        );
        if (flights.isNotEmpty) {
          return EnhancedSearchService.formatFlights(flights);
        }
        return null;

      case 'hotels':
        final service = ref.read(enhancedSearchServiceProvider);
        final hotels = await service.searchHotels(searchQuery);
        if (hotels.isNotEmpty) {
          return EnhancedSearchService.formatHotels(hotels, searchQuery);
        }
        return null;

      case 'weather':
        final weatherService = ref.read(weatherServiceProvider);
        WeatherData? weather;
        final city = extractCity(message);
        final zip = extractZipCode(message);

        if (city != null) {
          weather = await weatherService.getCurrentWeather(city: city);
        } else if (zip != null) {
          weather = await weatherService.getCurrentWeather(postalCode: zip);
        } else {
          final locationService = ref.read(locationServiceProvider);
          final location = await locationService.getCurrentLocation();
          if (location != null) {
            weather = await weatherService.getCurrentWeather(
              lat: location.latitude,
              lon: location.longitude,
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

  // ── Flight/Weather parameter parsers ──────────────────────────────────────

  /// Parse flight search parameters from natural language.
  static Map<String, String>? parseFlightParams(String message) {
    // Case-sensitive city pattern (must start with uppercase)
    const cityName = r'[A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?';
    const numericDate = r'\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}';
    // Longer month names first, handle case via character classes
    const months =
        r'[Jj]anvier|[Ff]évrier|[Ff]evrier|[Mm]ars|[Aa]vril|[Mm]ai|'
        r'[Jj]uillet|[Jj]uin|[Aa]oût|[Aa]out|[Ss]eptembre|[Oo]ctobre|'
        r'[Nn]ovembre|[Dd]écembre|[Dd]ecembre|'
        r'[Jj]anuary|[Ff]ebruary|[Mm]arch|[Aa]pril|[Mm]ay|'
        r'[Jj]uly|[Jj]une|[Aa]ugust|[Ss]eptember|[Oo]ctober|'
        r'[Nn]ovember|[Dd]ecember';

    // Pattern 1: "City1-City2 du date1 au date2"
    final routeDate = RegExp(
      '($cityName)\\s*[-àa]\\s*($cityName)\\s+'
      '(?:d[ue]|le|pour le)\\s+($numericDate)'
      '(?:\\s+(?:au|au retour le)\\s+($numericDate))?',
    );
    final match1 = routeDate.firstMatch(message);
    if (match1 != null) {
      return {
        'from': match1.group(1)!.trim(),
        'to': match1.group(2)!.trim(),
        'departDate': normalizeDate(match1.group(3)!),
        if (match1.group(4) != null)
          'returnDate': normalizeDate(match1.group(4)!),
      };
    }

    // Pattern 2: "vol direct City1 City2 day month year"
    final directVol = RegExp(
      '(?:[Vv]ol|[Bb]illet)\\s+(?:\\w+\\s+)*(?:de\\s+)?'
      '($cityName)\\s+'
      '(?:à|vers|pour|-)?\\s*($cityName)\\s+'
      '(?:le\\s+)?(\\d{1,2})\\s+'
      '($months)'
      '(?:\\s+(\\d{4}))?',
    );
    final match2 = directVol.firstMatch(message);
    if (match2 != null) {
      final day = match2.group(3)!;
      final monthName = match2.group(4)!;
      final year = match2.group(5) ?? DateTime.now().year.toString();
      final month = parseMonth(monthName);
      final dateStr =
          '$year-${month.toString().padLeft(2, '0')}-${int.parse(day).toString().padLeft(2, '0')}';
      return {
        'from': match2.group(1)!.trim(),
        'to': match2.group(2)!.trim(),
        'departDate': dateStr,
      };
    }

    // Pattern 3: Compact "City1 City2 YYYY-MM-DD"
    final compact = RegExp(
      '(?:de\\s+)?($cityName)\\s+'
      '(?:à|vers|pour|-)?\\s*($cityName)',
    );
    final match3 = compact.firstMatch(message);
    final dateFinder = RegExp('($numericDate)');
    final dateMatch = dateFinder.firstMatch(message);
    if (match3 != null && dateMatch != null) {
      return {
        'from': match3.group(1)!.trim(),
        'to': match3.group(2)!.trim(),
        'departDate': normalizeDate(dateMatch.group(1)!),
      };
    }

    return null;
  }

  /// Extract city name from weather-related message.
  static String? extractCity(String message) {
    // Pattern: "météo Paris", "temps à Lyon", "pleuvoir à Marseille"
    final patterns = [
      RegExp(r'(?:météo|meteo|temps|pleuvoir|température|temperature)\s+(?:à|de|pour|sur)\s+'
          r'([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?)'),
      RegExp(r'(?:météo|meteo|temps|pleuvoir|température|temperature)\s+'
          r'([A-ZÀ-Ÿ][a-zà-ÿ]+)'),
      RegExp(r'(?:fait-il|fera-t-il)\s+(?:à|de|pour|sur)\s+'
          r'([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?)'),
      RegExp(r"(?:est-ce qu'il|va-t-il)\s+\w+\s+(?:à|de|pour|sur)\s+"
          r'([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?)'),
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
    const months = {
      'janvier': 1, 'février': 2, 'fevrier': 2, 'mars': 3, 'avril': 4,
      'mai': 5, 'may': 5, 'juin': 6, 'june': 6, 'juillet': 7, 'july': 7,
      'août': 8, 'aout': 8, 'august': 8, 'septembre': 9, 'september': 9,
      'octobre': 10, 'october': 10, 'novembre': 11, 'november': 11,
      'décembre': 12, 'decembre': 12, 'december': 12,
      'january': 1, 'february': 2, 'march': 3, 'april': 4,
    };
    return months[name.toLowerCase()] ?? 1;
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
