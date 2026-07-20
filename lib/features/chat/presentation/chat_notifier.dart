import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../data/ai_client.dart';
import '../data/chat_api_service.dart';
import '../data/worker_chat_client.dart';
import '../data/model_router.dart';
import '../data/firestore_chat_repository.dart';
import '../data/mock_chat_repository.dart';
import '../data/quota_service.dart';
import '../data/search_service.dart';
import '../data/enhanced_search_service.dart';
import '../data/search_service_global.dart';
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
import '../domain/attachment.dart';
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
import '../../retention/data/retention_providers.dart';
import '../../retention/data/user_profile_service.dart';
import '../../retention/data/usage_stats_service.dart';
import '../data/learning_repository.dart';
import '../data/knowledge_base_service.dart';
import 'feedback_collector.dart';
import '../../monetization/data/consent_data_service.dart';
import '../../monetization/data/anonymized_insight_service.dart';

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
final searchServiceGlobalProvider =
    Provider((ref) => SearchServiceGlobal());
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
  final String selectedModel;
  final int displayCount;

  const ChatState({
    this.messages = const [],
    this.isStreaming = false,
    this.error,
    this.remainingRequests,
    this.isSearching = false,
    this.useSearch = false,
    this.selectedModel = 'auto',
    this.displayCount = 30,
  });

  ChatState copyWith({
    List<Message>? messages,
    bool? isStreaming,
    String? error,
    int? remainingRequests,
    bool? isSearching,
    bool? useSearch,
    String? selectedModel,
    int? displayCount,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        error: error,
        remainingRequests: remainingRequests ?? this.remainingRequests,
        isSearching: isSearching ?? this.isSearching,
        useSearch: useSearch ?? this.useSearch,
        selectedModel: selectedModel ?? this.selectedModel,
        displayCount: displayCount ?? this.displayCount,
      );

  bool get canLoadMore => messages.length > displayCount;
  List<Message> get displayedMessages =>
      messages.length <= displayCount
          ? messages
          : messages.sublist(messages.length - displayCount);
}

/// Parametres d'un message bloque par quota, stockes pour retry auto.
class _PendingMessage {
  final String text;
  final String? imageBase64;
  final String? imageMimeType;
  final String? fileName;
  final String? fileContent;
  final List<Attachment>? attachments;
  final bool isVoiceConversation;
  final String? modelOverride;
  final bool bypassSlashCheck;

  const _PendingMessage({
    required this.text,
    this.imageBase64,
    this.imageMimeType,
    this.fileName,
    this.fileContent,
    this.attachments,
    this.isVoiceConversation = false,
    this.modelOverride,
    this.bypassSlashCheck = false,
  });
}

class ChatNotifier extends FamilyNotifier<ChatState, String> {
  /// Message en attente quand le quota bloque l'envoi.
  /// Permet de relancer automatiquement apres bonus (video ou Pro).
  _PendingMessage? _pendingMessage;

  List<String> _lastLinksForDownload = const [];
  String _lastLinksFilter = 'all';
  String? _lastUsedModelId;

  // ── Apprentissage et feedback ───────────────────────────────────────────────
  late final LearningRepository _learningRepo;
  late final FeedbackCollector _feedback;
  late final KnowledgeBaseService _knowledgeBase;
  late final ConsentDataService _consentData;
  late final AnonymizedInsightService _insights;

  @override
  ChatState build(String conversationId) {
    // Initialiser les services d'apprentissage
    final db = isDemoMode ? null : ref.read(firestoreProvider);
    final userId = isDemoMode ? null : ref.read(currentUserProvider)?.uid;
    _learningRepo = LearningRepository(db: db, userId: userId);
    _feedback = FeedbackCollector(_learningRepo);
    _knowledgeBase = KnowledgeBaseService();
    _consentData = ConsentDataService();
    _insights = AnonymizedInsightService(_consentData);
    _knowledgeBase.init();

    // Enregistrer le demarrage de session pour les insights
    _insights.recordSessionStart();

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

    // Commandes réservées à l'extension Chrome (DOM uniquement)
    const extensionOnlyCommands = {
      'scroll', 'open', 'click', 'fill', 'screenshot', 'back', 'forward',
      'forms', 'tables', 'media', 'autofill', 'inspect', 'highlight',
      'waitfor', 'monitor', 'translate', 'searchpage',
    };
    // Commandes universelles (mobile + extension, backend requis pour certaines)
    const universalCommands = {
      'download', 'links', 'pdf', 'summarize', 'extract', 'metadata',
      'export', 'docgen', 'scrape', 'crawl',
    };

    if (!isExtension && extensionOnlyCommands.contains(parsed.command.name)) {
      await _persistAssistantMessage(
        '❌ Commande non disponible sur mobile\n\n'
        'La commande `/${parsed.command.name}` nécessite l\'extension Chrome.\n\n'
        '💡 Installez l\'extension Chrome Corely pour utiliser les commandes '
        'de navigation DOM (/scroll, /open, /click, /screenshot, etc.).',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }

    // Sur mobile, les commandes universelles nécessitent le backend
    if (!isExtension && universalCommands.contains(parsed.command.name)) {
      if (!AppConstants.isWorkerConfigured) {
        await _persistAssistantMessage(
          '❌ Backend non configuré\n\n'
          'La commande `/${parsed.command.name}` nécessite le backend Cloudflare Worker.\n\n'
          '💡 Configurez `BACKEND_URL` et `API_SECRET_KEY` dans `.env` puis redéployez.\n'
          'Ou utilisez `/docgen` qui fonctionne sans backend.',
        );
        state = state.copyWith(isStreaming: false);
        return true;
      }
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

    // Annonce pré-exécution : explique ce que la commande va faire
    await _persistAssistantMessage(
      '▶️ **Commande** `${parsed.fullText}`\n\n'
      '$naturalText',
    );

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
      case 'scrape':
        return await _handleSlashScrape(parsed, bridge);
      case 'crawl':
        return await _handleSlashCrawl(parsed, bridge);
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

    final targetUrl = urlsToDownload.firstOrNull;
    if (targetUrl == null) {
      await _persistAssistantMessage('❌ Aucune URL à télécharger.');
      state = state.copyWith(isStreaming: false);
      return true;
    }

    // Detect video/gallery sites that need backend extraction
    final videoHosts = RegExp(
      r'(youtube\.com|youtu\.be|vimeo\.com|dailymotion\.com|tiktok\.com|'
      r'twitch\.tv|facebook\.com/watch|instagram\.com/reel|soundcloud\.com|'
      r'reddit\.com|twitter\.com|x\.com|streamable\.com|rumble\.com)',
      caseSensitive: false,
    );
    final isVideoSite = videoHosts.hasMatch(targetUrl);
    final hasFileExt = RegExp(r'\.(mp4|webm|mkv|avi|mov|mp3|wav|ogg|pdf|zip|rar|jpg|jpeg|png|webp|gif)$', caseSensitive: false)
        .hasMatch(Uri.parse(targetUrl).path);
    // URLs déjà directes (ex: googlevideo.com/videoplayback) — pas besoin de backend
    final isDirectMediaUrl = RegExp(
      r'(googlevideo\.com/videoplayback|\.m3u8|itag=\d+|mime=video|mime=audio)',
      caseSensitive: false,
    ).hasMatch(targetUrl);

    // Try backend media extraction for video sites and pages without direct file extensions
    if (!isDirectMediaUrl && (isVideoSite || !hasFileExt)) {
      final backendUrl = AppConstants.backendBaseUrl;
      if (backendUrl.isNotEmpty && !backendUrl.contains('localhost')) {
        try {
          final globalService = ref.read(searchServiceGlobalProvider);
          final mediaResult = await globalService.downloadMedia(targetUrl);

          if (mediaResult['success'] == true) {
            final mediaType = mediaResult['type'] as String? ?? '';

            if (mediaType == 'video') {
              // Video from yt-dlp — pick best merged format
              final title = mediaResult['title'] as String? ?? 'Vidéo';
              final thumbnail = mediaResult['thumbnail'] as String? ?? '';
              final duration = mediaResult['duration'] as int?;
              final directUrl = mediaResult['direct_url'] as String? ?? '';
              final formats = (mediaResult['formats'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

              if (directUrl.isNotEmpty) {
                // Trigger download with the direct URL
                final dlAction = BrowserAction(
                  action: BrowserActionType.download,
                  params: {'url': directUrl, if (filename != null) 'filename': filename},
                );
                final dlResult = await bridge.executeAction(dlAction);
                final ok = dlResult.success;

                final durationStr = duration != null
                    ? '${duration ~/ 60}m${duration % 60}s'
                    : '';
                final msg = StringBuffer()
                  ..writeln('📹 **$title**')
                  ..writeln()
                  ..writeln('Téléchargement ${ok ? "lancé" : "échoué"} ${durationStr.isNotEmpty ? "($durationStr)" : ""}.')
                  ..writeln()
                  ..writeln('Formats extraits : ${formats.length}');
                if (formats.isNotEmpty) {
                  msg.writeln('\\n| Qualité | Format | Audio+Vidéo |');
                  msg.writeln('|--------|--------|-------------|');
                  for (final f in formats.take(8)) {
                    final q = f['quality'] ?? f['format_id'] ?? '?';
                    final ext = f['ext'] ?? '?';
                    final av = (f['has_audio'] == true && f['has_video'] == true) ? '✅' : '⚠️';
                    msg.writeln('| $q | $ext | $av |');
                  }
                }
                await _persistAssistantMessage(msg.toString());
                state = state.copyWith(error: null, isStreaming: false);
                return true;
              }
            }

            if (mediaType == 'playlist') {
              // YouTube channel/playlist — show list of videos, store for bulk download
              final title = mediaResult['title'] as String? ?? 'Playlist';
              final uploader = mediaResult['uploader'] as String? ?? '';
              final entries = (mediaResult['entries'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

              if (entries.isNotEmpty) {
                final msg = StringBuffer()
                  ..writeln('📋 **$title** ${uploader.isNotEmpty ? 'par $uploader' : ''}')
                  ..writeln()
                  ..writeln('**${entries.length} vidéos trouvées** :');
                for (var i = 0; i < entries.length && i < 15; i++) {
                  final e = entries[i];
                  final eTitle = e['title'] as String? ?? 'Vidéo';
                  final eUrl = e['url'] as String? ?? '';
                  final eDuration = e['duration'] as int?;
                  final durStr = eDuration != null ? ' (${eDuration ~/ 60}m${eDuration % 60}s)' : '';
                  msg.writeln('${i + 1}. [$eTitle]($eUrl)$durStr');
                }
                if (entries.length > 15) {
                  msg.writeln('... et ${entries.length - 15} autres');
                }
                msg.writeln('\n💡 Lancez `/download <url>` sur une vidéo spécifique.');
                await _persistAssistantMessage(msg.toString());
                _lastLinksForDownload = entries
                    .map((e) => e['url'] as String?)
                    .whereType<String>()
                    .where((u) => u.isNotEmpty)
                    .toList(growable: false);
                _lastLinksFilter = 'video';
                state = state.copyWith(error: null, isStreaming: false);
                return true;
              }
            }

            if (mediaType == 'page_media') {
              // Generic page — show images and videos found
              final title = mediaResult['title'] as String? ?? 'Page';
              final videos = (mediaResult['videos'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
              final images = (mediaResult['images'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

              final msg = StringBuffer()
                ..writeln('🌐 **$title**')
                ..writeln()
                ..writeln('Médias trouvés sur la page :');

              if (videos.isNotEmpty) {
                msg.writeln('\\n**Vidéos (${videos.length})**');
                for (var i = 0; i < videos.length && i < 10; i++) {
                  final v = videos[i];
                  msg.writeln('${i + 1}. [${v['tag'] ?? 'video'}](${v['url']})');
                }
                if (videos.length > 10) {
                  msg.writeln('... et ${videos.length - 10} autres');
                }
              }

              if (images.isNotEmpty) {
                msg.writeln('\\n**Images (${images.length})**');
                for (var i = 0; i < images.length && i < 15; i++) {
                  final img = images[i];
                  final alt = (img['alt'] as String? ?? '').isNotEmpty ? ' — ${img['alt']}' : '';
                  msg.writeln('${i + 1}. [Image ${i + 1}$alt](${img['url']})');
                }
                if (images.length > 15) {
                  msg.writeln('... et ${images.length - 15} autres');
                }
              }

              if (videos.isEmpty && images.isEmpty) {
                msg.writeln('\\n_Aucun média trouvé._');
              }

              await _persistAssistantMessage(msg.toString());
              state = state.copyWith(error: null, isStreaming: false);
              return true;
            }
          }
        } catch (e) {
          debugPrint('[Download] Backend extraction failed: $e');
          // En mode combo (urls stockées par /links), on tente le téléchargement
          // direct même si le backend échoue — mieux vaut un fichier HTML que rien.
          if (cmd.args.isEmpty) {
            // Fall through to direct download below
          } else {
            final errStr = e.toString();
            final isTimeout = errStr.contains('timeout') || errStr.contains('Timed out');
            final is404 = errStr.contains('404') || errStr.contains('Not Found');
            final isConn = errStr.contains('Connection') || errStr.contains('SocketException') || errStr.contains('refused');

            String detail;
            if (is404) {
              detail = 'Le endpoint `/download_media` n\'est pas disponible sur le backend. '
                  'Vérifiez que le backend a été redémarré après `pip install -r requirements.txt`.';
            } else if (isTimeout) {
              detail = 'Le backend a mis trop de temps à répondre. '
                  'yt-dlp peut être lent sur les chaînes YouTube avec beaucoup de vidéos. '
                  'Essayez avec une URL de vidéo directe (pas une chaîne).';
            } else if (isConn) {
              detail = 'Impossible de joindre le backend à `$backendUrl`. '
                  'Vérifiez que le serveur est démarré et accessible.';
            } else {
              detail = 'Erreur backend : $errStr';
            }

            await _persistAssistantMessage(
              '❌ Échec extraction vidéo\n\n'
              '$detail\n\n'
              '💡 **Solutions** :\n'
              '- Redémarrez le backend : `cd backend && uvicorn backend.main:app --reload`\n'
              '- Vérifiez que yt-dlp est installé : `pip show yt-dlp`\n'
              '- Pour les fichiers directs (MP4, WebM, etc.), utilisez `/download <url_directe>`\n'
              '- Sur desktop, utilisez une extension comme "Video DownloadHelper"',
            );
            state = state.copyWith(isStreaming: false);
            return true;
          }
        }
      } else if (isVideoSite) {
        // Backend URL vide ou localhost
        if (cmd.args.isEmpty) {
          // Mode combo : tenter le téléchargement direct même sans backend
        } else {
          await _persistAssistantMessage(
            '❌ Backend non configuré\n\n'
            'BACKEND_URL est vide ou contient localhost. '
            'Ajoutez `BACKEND_URL=https://api.corelia.app` dans `.env` et recompilez.',
          );
          state = state.copyWith(isStreaming: false);
          return true;
        }
      }
    }

    // Direct file download (existing behavior)
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
        await _persistAssistantMessage(
          'Téléchargement lancé pour $count fichier(s) depuis le dernier `/links` '
          '(filtre `${_lastLinksFilter}`, ${_lastLinksForDownload.length} lien(s) en mémoire).',
        );
      } else {
        await _persistAssistantMessage('Téléchargement lancé pour $count fichier(s).');
      }
    } else {
      await _persistAssistantMessage(
        '❌ Échec téléchargement\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que les URLs sont valides et accessibles.',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashCrawl(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      await _persistAssistantMessage(
        '❌ Usage incorrect\n\n'
        'Commande `/crawl` nécessite une URL.\n\n'
        '💡 **Usage** : `/crawl <url> [max_depth] [max_pages]`',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }
    final url = cmd.args[0];
    final maxDepth = cmd.args.length > 1 ? int.tryParse(cmd.args[1]) ?? 2 : 2;
    final maxPages = cmd.args.length > 2 ? int.tryParse(cmd.args[2]) ?? 20 : 20;

    final globalService = ref.read(searchServiceGlobalProvider);
    try {
      await _persistAssistantMessage(
        '🔍 Crawling de `$url` en cours...\n'
        'Profondeur: $maxDepth | Pages max: $maxPages\n\n'
        '_Cela peut prendre quelques secondes..._',
      );
      final data = await globalService.crawl(url, maxDepth: maxDepth, maxPages: maxPages);
      final pagesCrawled = data['pages_crawled'] as int? ?? 0;
      final totalLinks = data['total_links_found'] as int? ?? 0;
      final videos = (data['videos'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final images = (data['images'] as List<dynamic>? ?? []).cast<String>();
      final errors = (data['errors'] as List<dynamic>? ?? []).cast<String>();

      final buf = StringBuffer();
      buf.writeln('🕸️ **Résultat du crawl**\n');
      buf.writeln('- Pages parcourues : $pagesCrawled');
      buf.writeln('- Liens découverts : $totalLinks');
      buf.writeln('- Vidéos trouvées : ${videos.length}');
      buf.writeln('- Images trouvées : ${images.length}');
      if (errors.isNotEmpty) {
        buf.writeln('- Erreurs : ${errors.length}');
      }
      buf.writeln();

      if (videos.isNotEmpty) {
        buf.writeln('## 🎬 Vidéos (${videos.length})');
        for (var i = 0; i < videos.length && i < 15; i++) {
          final v = videos[i];
          buf.writeln('${i + 1}. [${v['tag'] ?? 'vidéo'}](${v['url']})');
        }
        if (videos.length > 15) {
          buf.writeln('... et ${videos.length - 15} autres');
        }
        buf.writeln();
      }

      if (images.isNotEmpty) {
        buf.writeln('## 🖼️ Images (${images.length})');
        for (var i = 0; i < images.length && i < 10; i++) {
          buf.writeln('${i + 1}. [Image ${i + 1}](${images[i]})');
        }
        if (images.length > 10) {
          buf.writeln('... et ${images.length - 10} autres');
        }
        buf.writeln();
      }

      if (errors.isNotEmpty) {
        buf.writeln('## ⚠️ Erreurs');
        for (final err in errors.take(5)) {
          buf.writeln('- $err');
        }
        buf.writeln();
      }

      buf.writeln('💡 Lancez `/download <url>` sur un lien vidéo pour le télécharger.');

      // Store video links for bulk download
      _lastLinksForDownload = videos
          .map((v) => v['url'] as String?)
          .whereType<String>()
          .where((u) => u.isNotEmpty)
          .toList(growable: false);
      _lastLinksFilter = 'video';

      await _persistAssistantMessage(buf.toString());
    } catch (e) {
      await _persistAssistantMessage(
        '❌ Échec crawl\n\n'
        'Erreur : $e\n\n'
        '💡 Vérifiez que l\'URL est accessible et que le backend est disponible.',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashPdf(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    // /pdf [filename] — PDF de la page courante
    // Combo : /open <url> attendre chargement, puis /pdf [filename]
    final filename = cmd.args.isNotEmpty ? cmd.args[0] : null;

    final action = BrowserAction(
      action: BrowserActionType.saveAsPdf,
      params: {
        if (filename != null) 'filename': filename,
      },
    );
    final result = await bridge.executeAction(action);
    if (result.success) {
      state = state.copyWith(error: null, isStreaming: false);
      await _persistAssistantMessage('Fenêtre d\'impression ouverte. Choisissez "Enregistrer au format PDF".');
    } else {
      await _persistAssistantMessage(
        '❌ Échec PDF\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que la page est chargée dans l\'extension.',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashLinks(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final firstArg = cmd.args.isNotEmpty ? cmd.args[0] : 'all';
    final String? url = firstArg.startsWith('http') ? firstArg : null;
    final rawFilter = url != null ? (cmd.args.length > 1 ? cmd.args[1] : 'all') : firstArg;

    if (url != null) {
      final globalService = ref.read(searchServiceGlobalProvider);

      // YouTube is a SPA — BeautifulSoup cannot extract video links from rendered HTML.
      // Skip scrape and go directly to backend media extraction.
      final isYouTube = url.contains('youtube.com') || url.contains('youtu.be');

      if (!isYouTube) {
        try {
          final data = await globalService.scrape(url);
          final allLinks = (data['data'] as List? ?? [])
              .where((d) => d['field'] == 'links')
              .expand((d) => (d['values'] as List? ?? []).cast<Map>());
          final filtered = allLinks.where((m) {
            final href = (m['url'] ?? '').toString();
            switch (rawFilter.toLowerCase()) {
              case 'video':
                return href.contains('video') || href.endsWith('.mp4') || href.endsWith('.webm');
              case 'image':
                return href.contains('image') || href.endsWith('.jpg') || href.endsWith('.jpeg') || href.endsWith('.png') || href.endsWith('.gif') || href.endsWith('.webp');
              case 'audio':
                return href.contains('audio') || href.endsWith('.mp3') || href.endsWith('.wav');
              case 'document':
                return href.endsWith('.pdf') || href.endsWith('.doc') || href.endsWith('.docx') || href.endsWith('.xls') || href.endsWith('.xlsx');
              default:
                return true;
            }
          });
          final linksDisplay = filtered.toList();
          final linksText = linksDisplay.map((m) => '- [${m['text'] ?? 'Lien'}](${m['url']})').join('\n');

          if (linksDisplay.isNotEmpty) {
            // Sauvegarder les liens pour /download ultérieur
            _lastLinksForDownload = linksDisplay
                .map((m) => (m['url'] ?? '').toString())
                .where((u) => u.isNotEmpty)
                .toList(growable: false);
            _lastLinksFilter = rawFilter.toLowerCase();
            await _persistAssistantMessage(
              'Liens extraits de $url (filtre: $rawFilter, ${linksDisplay.length} lien(s)) :\n\n'
              '$linksText\n\n'
              '💡 Lancez `/download` sans paramètre pour télécharger toute cette liste.',
            );
            return true;
          }
        } catch (e) {
          debugPrint('[Links] Scrape failed for $url: $e');
        }
      }

      // Fallback / primary path for YouTube and empty scrape results
      try {
        final media = await globalService.downloadMedia(url, mediaType: 'video');
        if (media['success'] == true) {
          final mediaType = media['type'] as String? ?? '';

          if (mediaType == 'playlist') {
            final entries = (media['entries'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
            final title = media['title'] as String? ?? 'Playlist';
            final uploader = media['uploader'] as String? ?? '';
            if (entries.isNotEmpty) {
              final buf = StringBuffer()
                ..writeln('📋 **$title** ${uploader.isNotEmpty ? 'par $uploader' : ''}')
                ..writeln()
                ..writeln('Vidéos trouvées (${entries.length}) :');
              for (var i = 0; i < entries.length && i < 15; i++) {
                final e = entries[i];
                final eTitle = e['title'] as String? ?? 'Vidéo';
                final eUrl = e['url'] as String? ?? '';
                final eDuration = e['duration'] as int?;
                final durStr = eDuration != null ? ' (${eDuration ~/ 60}m${eDuration % 60}s)' : '';
                buf.writeln('${i + 1}. [$eTitle]($eUrl)$durStr');
              }
              if (entries.length > 15) {
                buf.writeln('... et ${entries.length - 15} autres');
              }
              buf.writeln('\n💡 Lancez `/download <url>` sur un lien pour le télécharger.');
              await _persistAssistantMessage(buf.toString());
              _lastLinksForDownload = entries
                  .map((e) => e['url'] as String?)
                  .whereType<String>()
                  .where((u) => u.isNotEmpty)
                  .toList(growable: false);
              _lastLinksFilter = 'video';
              return true;
            }
          }

          if (mediaType == 'video' || mediaType == 'page_media') {
            final videos = (media['videos'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
            final title = media['title'] as String? ?? 'Page';
            if (videos.isNotEmpty) {
              final buf = StringBuffer()
                ..writeln('🎬 **$title**')
                ..writeln()
                ..writeln('Vidéos trouvées (${videos.length}) :');
              for (var i = 0; i < videos.length && i < 15; i++) {
                final v = videos[i];
                buf.writeln('${i + 1}. [${v['tag'] ?? 'vidéo'}](${v['url']})');
              }
              if (videos.length > 15) {
                buf.writeln('... et ${videos.length - 15} autres');
              }
              buf.writeln('\n💡 Lancez `/download <url>` sur un lien pour le télécharger.');
              await _persistAssistantMessage(buf.toString());
              _lastLinksForDownload = videos
                  .map((v) => v['url'] as String?)
                  .whereType<String>()
                  .where((u) => u.isNotEmpty)
                  .toList(growable: false);
              _lastLinksFilter = 'video';
              return true;
            }
          }
        }
      } catch (e) {
        debugPrint('[Links] downloadMedia failed for $url: $e');
      }

      await _persistAssistantMessage(
        'Aucun lien trouvé sur $url (filtre: $rawFilter).\n\n'
        '💡 **Note** : les pages de chaînes YouTube ne peuvent pas être extraites '
        'par le Worker Cloudflare. Utilisez `/links` sur une page de vidéo '
        'individuelle (ex: `/links https://www.youtube.com/watch?v=...`).',
      );
      return true;
    }

    if (!bridge.isExtension) {
      await _persistAssistantMessage(
        '❌ Usage incorrect\n\n'
        'Commande `/links` sur mobile nécessite une URL.\n\n'
        '💡 **Usage** : `/links <url> [all|video|image|audio|document]`',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }

    final aliases = <String, String>{
      'videos': 'video',
      'images': 'image',
      'documents': 'document',
      'docs': 'document',
      'files': 'document',
      'audios': 'audio',
    };
    final filter = aliases[rawFilter.toLowerCase()] ?? rawFilter.toLowerCase();

    // ── Extension universelle : pour video/image, utiliser le backend
    // Le backend combine yt-dlp (1000+ sites) + BeautifulSoup (tout le reste).
    // Le DOM statique ne trouve que les liens de page, pas les URLs directes.
    final metaAction = BrowserAction(
      action: BrowserActionType.pageMetadata,
      params: {},
    );
    final metaResult = await bridge.executeAction(metaAction);
    final currentUrl = metaResult.success ? (metaResult.data?['url'] as String? ?? '') : '';
    final currentTitle = metaResult.success ? (metaResult.data?['title'] as String? ?? '') : '';

    final shouldUseBackend = filter == 'video' || filter == 'image';

    if (shouldUseBackend) {
      final backendUrl = AppConstants.backendBaseUrl;
      if (backendUrl.isNotEmpty && !backendUrl.contains('localhost')) {
        try {
          final globalService = ref.read(searchServiceGlobalProvider);
          // mediaType: 'auto' → le backend détecte automatiquement (yt-dlp ou scraper)
          final media = await globalService.downloadMedia(currentUrl, mediaType: 'auto');
          if (media['success'] == true) {
            final mediaType = media['type'] as String? ?? '';

            // ── Playlist / chaîne (yt-dlp) ──
            if (mediaType == 'playlist' && filter == 'video') {
              final entries = (media['entries'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
              final title = media['title'] as String? ?? 'Playlist';
              final uploader = media['uploader'] as String? ?? '';
              if (entries.isNotEmpty) {
                final buf = StringBuffer()
                  ..writeln('📋 **$title** ${uploader.isNotEmpty ? 'par $uploader' : ''}')
                  ..writeln()
                  ..writeln('Vidéos trouvées (${entries.length}) :');
                for (var i = 0; i < entries.length && i < 15; i++) {
                  final e = entries[i];
                  final eTitle = e['title'] as String? ?? 'Vidéo';
                  final eUrl = e['url'] as String? ?? '';
                  final eDuration = e['duration'] as int?;
                  final durStr = eDuration != null ? ' (${eDuration ~/ 60}m${eDuration % 60}s)' : '';
                  buf.writeln('${i + 1}. [$eTitle]($eUrl)$durStr');
                }
                if (entries.length > 15) {
                  buf.writeln('... et ${entries.length - 15} autres');
                }
                buf.writeln('\n💡 Lancez `/download <url>` sur une vidéo spécifique.');
                await _persistAssistantMessage(buf.toString());
                // Ne pas stocker de playlist pour /download bulk — chaque URL
                // nécessite une résolution backend individuelle.
                _lastLinksForDownload = [];
                _lastLinksFilter = 'video';
                return true;
              }
            }

            // ── Vidéo directe (yt-dlp a extrait une URL de streaming) ──
            if (mediaType == 'video' && filter == 'video') {
              final title = media['title'] as String? ?? 'Vidéo';
              final directUrl = media['direct_url'] as String? ?? '';
              final duration = media['duration'] as int?;
              final formats = (media['formats'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
              final durStr = duration != null ? ' (${duration ~/ 60}m${duration % 60}s)' : '';

              final buf = StringBuffer()
                ..writeln('📹 **$title**$durStr')
                ..writeln()
                ..writeln('URL directe extraite : ${directUrl.isNotEmpty ? "Oui" : "Non"}.')
                ..writeln()
                ..writeln('💡 Lancez `/download` sans paramètre pour télécharger cette vidéo.');
              if (formats.isNotEmpty) {
                buf.writeln('\n| Qualité | Format | Audio+Vidéo |');
                buf.writeln('|--------|--------|-------------|');
                for (final f in formats.take(8)) {
                  final q = f['quality'] ?? f['format_id'] ?? '?';
                  final ext = f['ext'] ?? '?';
                  final av = (f['has_audio'] == true && f['has_video'] == true) ? '✅' : '⚠️';
                  buf.writeln('| $q | $ext | $av |');
                }
              }
              await _persistAssistantMessage(buf.toString());
              _lastLinksForDownload = directUrl.isNotEmpty ? [directUrl] : [];
              _lastLinksFilter = 'video';
              return true;
            }

            // ── Médias de page (scraper universel — tout site) ──
            if (mediaType == 'page_media') {
              final videos = (media['videos'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
              final images = (media['images'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
              final title = media['title'] as String? ?? 'Page';

              if (filter == 'video' && videos.isNotEmpty) {
                final buf = StringBuffer()
                  ..writeln('🎬 **$title**')
                  ..writeln()
                  ..writeln('Vidéos trouvées (${videos.length}) :');
                for (var i = 0; i < videos.length && i < 15; i++) {
                  final v = videos[i];
                  buf.writeln('${i + 1}. [${v['tag'] ?? 'vidéo'}](${v['url']})');
                }
                if (videos.length > 15) {
                  buf.writeln('... et ${videos.length - 15} autres');
                }
                buf.writeln('\n💡 Lancez `/download` sans paramètre pour télécharger toute cette liste.');
                await _persistAssistantMessage(buf.toString());
                _lastLinksForDownload = videos
                    .map((v) => v['url'] as String?)
                    .whereType<String>()
                    .where((u) => u.isNotEmpty)
                    .toList(growable: false);
                _lastLinksFilter = 'video';
                return true;
              }

              if (filter == 'image' && images.isNotEmpty) {
                final buf = StringBuffer()
                  ..writeln('🖼️ **$title**')
                  ..writeln()
                  ..writeln('Images trouvées (${images.length}) :');
                for (var i = 0; i < images.length && i < 15; i++) {
                  final img = images[i];
                  final alt = (img['alt'] as String? ?? '').isNotEmpty ? ' — ${img['alt']}' : '';
                  buf.writeln('${i + 1}. [Image ${i + 1}$alt](${img['url']})');
                }
                if (images.length > 15) {
                  buf.writeln('... et ${images.length - 15} autres');
                }
                buf.writeln('\n💡 Lancez `/download` sans paramètre pour télécharger toute cette liste.');
                await _persistAssistantMessage(buf.toString());
                _lastLinksForDownload = images
                    .map((img) => img['url'] as String?)
                    .whereType<String>()
                    .where((u) => u.isNotEmpty)
                    .toList(growable: false);
                _lastLinksFilter = 'image';
                return true;
              }
            }
          }
        } catch (e) {
          debugPrint('[Links] Backend extraction failed for $currentUrl: $e');
          // Fall through to DOM extraction
        }
      }
    }

    // ── Fallback DOM extraction (non-video sites ou échec backend)
    final action = BrowserAction(
      action: BrowserActionType.extractLinks,
      params: {'filter': filter},
    );
    final result = await bridge.executeAction(action);
    if (result.success && result.data != null) {
      final links = result.data!['links'] as List? ?? [];
      final count = result.data!['count'] as int? ?? links.length;
      final appliedFilter = result.data!['filter'] as String? ?? 'all';
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
      await _persistAssistantMessage(
        'Liens trouvés sur "$currentTitle" ($appliedFilter, $count au total) :\n'
        '$linksText$more\n\n'
        '💡 Lancez `/download` sans paramètre pour télécharger toute cette liste.',
      );
    } else {
      final errorMsg = result.error ?? 'Erreur inconnue';
      if (errorMsg.contains('timed out') || errorMsg.contains('Timeout')) {
        await _persistAssistantMessage(
          '❌ Échec extraction liens\n\n'
          'Erreur : Action timed out\n\n'
          '💡 **Causes possibles :**\n'
          '1. Aucune page web n\'est ouverte dans un onglet Chrome\n'
          '2. La page n\'est pas encore chargée (attendez la fin du chargement)\n'
          '3. L\'extension n\'est pas rechargée après le build\n\n'
          '🔄 **Solution :** rechargez l\'extension dans chrome://extensions, '
          'ouvrez une page web, patientez 2 secondes, puis réessayez.\n\n'
          '💡 **Alternative :** `/links <url>` fonctionne sans DOM via le backend.',
        );
      } else {
        await _persistAssistantMessage(
          '❌ Échec extraction liens\n\n'
          'Erreur : $errorMsg\n\n'
          '💡 Vérifiez que la page est chargée dans l\'extension.',
        );
      }
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashSummarize(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final url = cmd.args.isNotEmpty && cmd.args[0].startsWith('http') ? cmd.args[0] : null;

    if (url != null) {
      final globalService = ref.read(searchServiceGlobalProvider);
      try {
        final data = await globalService.scrape(url);
        final allTexts = (data['data'] as List? ?? [])
            .where((d) => d['field'] == 'cards' || d['field'] == 'prices')
            .expand((d) => (d['values'] as List? ?? []).map((v) => v is Map ? v['text'] ?? '' : v.toString()))
            .where((t) => t.toString().isNotEmpty)
            .join('\n');
        final title = data['title'] as String? ?? url;
        if (allTexts.isEmpty) {
          await _persistAssistantMessage('Aucun contenu extrait de $url.');
          return true;
        }
        final summarizePrompt = 'Résume le contenu suivant de la page "$title" ($url) :\n\n$allTexts';
        await sendMessage(summarizePrompt, bypassSlashCheck: true);
        return true;
      } catch (e) {
        await _persistAssistantMessage(
          '❌ Échec résumé\n\n'
          'Erreur backend : $e\n\n'
          '💡 Vérifiez que l\'URL est accessible ou utilisez l\'extension Chrome.',
        );
        state = state.copyWith(isStreaming: false);
        return true;
      }
    }

    if (!bridge.isExtension) {
      await _persistAssistantMessage(
        '❌ Usage incorrect\n\n'
        'Commande `/summarize` sur mobile nécessite une URL.\n\n'
        '💡 **Usage** : `/summarize <url>`',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }

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
      await sendMessage(summarizePrompt, bypassSlashCheck: true);
      return true;
    } else {
      await _persistAssistantMessage(
        '❌ Échec résumé\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que la page est chargée dans l\'extension.',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashExtract(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final firstArg = cmd.args.isNotEmpty ? cmd.args[0] : '';
    final String? url = firstArg.startsWith('http') ? firstArg : null;
    final selector = url != null
        ? (cmd.args.length > 1 ? cmd.args[1] : 'body')
        : (cmd.args.isNotEmpty ? cmd.args[0] : 'body');

    if (url != null) {
      final globalService = ref.read(searchServiceGlobalProvider);
      try {
        final selectors = selector != 'body' ? {'content': selector} : null;
        final data = await globalService.scrape(url, selectors: selectors);
        final contentItems = (data['data'] as List? ?? [])
            .where((d) => d['field'] == 'content')
            .expand((d) => (d['values'] as List? ?? []))
            .where((t) => t.toString().isNotEmpty)
            .join('\n');
        final allTexts = contentItems.isNotEmpty
            ? contentItems
            : (data['data'] as List? ?? [])
                .where((d) => d['field'] == 'cards' || d['field'] == 'prices')
                .expand((d) => (d['values'] as List? ?? []).map((v) => v is Map ? v['text'] ?? '' : v.toString()))
                .where((t) => t.toString().isNotEmpty)
                .join('\n');
        if (allTexts.isEmpty) {
          await _persistAssistantMessage('Aucun contenu extrait de $url.');
          return true;
        }
        await _persistAssistantMessage('Contenu extrait de $url ($selector):\n\n$allTexts');
        return true;
      } catch (e) {
        await _persistAssistantMessage(
          '❌ Échec extraction\n\n'
          'Erreur backend : $e\n\n'
          '💡 Vérifiez que l\'URL est accessible ou utilisez l\'extension Chrome.',
        );
        state = state.copyWith(isStreaming: false);
        return true;
      }
    }

    if (!bridge.isExtension) {
      await _persistAssistantMessage(
        '❌ Usage incorrect\n\n'
        'Commande `/extract` sur mobile nécessite une URL.\n\n'
        '💡 **Usage** : `/extract <url> [sélecteur CSS]`',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }

    final action = BrowserAction(
      action: BrowserActionType.extractText,
      params: {'selector': selector},
    );
    final result = await bridge.executeAction(action);
    if (!result.success || result.data == null) {
      await _persistAssistantMessage(
        '❌ Échec extraction\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que la page est chargée dans l\'extension.',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }

    final text = result.data!['text'] as String? ?? '';
    if (text.isEmpty) {
      await _persistAssistantMessage('Aucun texte extrait de "$selector".');
      return true;
    }

    final rawPreview = text.length > 3000 ? '${text.substring(0, 3000)}...' : text;

    // LLM : nettoyage et structuration du texte
    final truncatedForLlm = text.length > 6000 ? '${text.substring(0, 6000)}\n[... contenu tronqué ...]' : text;
    final llmPrompt = 'Nettoie et structure le texte extrait suivant (sélecteur CSS: "$selector"). '
        'Supprime le bruit (menus, publicités, scripts). '
        'Organise en sections claires. Conserve les informations utiles.\n\n$truncatedForLlm';
    try {
      await sendMessage(llmPrompt, bypassSlashCheck: true);
    } catch (e) {
      await _persistAssistantMessage('Texte extrait de "$selector" (${text.length} caractères) :\n\n$rawPreview');
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
      await _persistAssistantMessage('Défilé ${direction == 'up' ? 'vers le haut' : 'vers le bas'} de $amount px.');
    } else {
      await _persistAssistantMessage(
        '❌ Échec défilement\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que la page est chargée dans l\'extension.',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashOpen(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      await _persistAssistantMessage(
        '❌ Usage incorrect\n\n'
        '💡 **Usage** : `/open <url>`',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }
    final action = BrowserAction(
      action: BrowserActionType.openUrl,
      params: {'url': cmd.args[0]},
    );
    final result = await bridge.executeAction(action);
    if (result.success) {
      state = state.copyWith(error: null, isStreaming: false);
      await _persistAssistantMessage('Onglet ouvert : ${cmd.args[0]}');
    } else {
      await _persistAssistantMessage(
        '❌ Échec ouverture\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que l\'URL est valide.',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashClick(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      await _persistAssistantMessage(
        '❌ Usage incorrect\n\n'
        '💡 **Usage** : `/click <sélecteur CSS>`',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }
    final action = BrowserAction(
      action: BrowserActionType.clickElement,
      params: {'selector': cmd.args[0]},
    );
    final result = await bridge.executeAction(action);
    if (result.success) {
      state = state.copyWith(error: null, isStreaming: false);
      await _persistAssistantMessage('Cliqué sur "${cmd.args[0]}".');
    } else {
      await _persistAssistantMessage(
        '❌ Échec clic\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que le sélecteur CSS est correct.',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashFill(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.length < 2) {
      await _persistAssistantMessage(
        '❌ Usage incorrect\n\n'
        '💡 **Usage** : `/fill <sélecteur CSS> <valeur>`',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }
    final action = BrowserAction(
      action: BrowserActionType.fillForm,
      params: {'selector': cmd.args[0], 'value': cmd.args.sublist(1).join(' ')},
    );
    final result = await bridge.executeAction(action);
    if (result.success) {
      state = state.copyWith(error: null, isStreaming: false);
      await _persistAssistantMessage('Champ "${cmd.args[0]}" rempli.');
    } else {
      await _persistAssistantMessage(
        '❌ Échec remplissage\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que le sélecteur CSS correspond à un champ de formulaire.',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashScreenshot(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final action = BrowserAction(action: BrowserActionType.screenshot, params: {});
    final result = await bridge.executeAction(action);
    if (result.success) {
      state = state.copyWith(error: null, isStreaming: false);
      final dataUrl = result.data?['dataUrl'] as String? ?? '';
      if (dataUrl.isNotEmpty && dataUrl.startsWith('data:image')) {
        final base64 = dataUrl.substring(dataUrl.indexOf(',') + 1);
        final downloadAction = BrowserAction(
          action: BrowserActionType.downloadData,
          params: {
            'contentBase64': base64,
            'mimeType': 'image/png',
            'filename': 'corely_screenshot_${DateTime.now().millisecondsSinceEpoch}.png',
          },
        );
        await bridge.executeAction(downloadAction);
        await _persistAssistantMessage('Capture d\'écran téléchargée (PNG).');
      } else {
        await _persistAssistantMessage('Capture d\'écran effectuée.');
      }
    } else {
      await _persistAssistantMessage(
        '❌ Échec capture d\'écran\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que la page est chargée dans l\'extension.',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashBack(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final action = BrowserAction(action: BrowserActionType.navigateBack, params: {});
    final result = await bridge.executeAction(action);
    if (result.success) {
      state = state.copyWith(error: null, isStreaming: false);
      await _persistAssistantMessage('Retour à la page précédente.');
    } else {
      await _persistAssistantMessage(
        '❌ Échec navigation\n\n'
        'Erreur : ${result.error}',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashForward(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final action = BrowserAction(action: BrowserActionType.navigateForward, params: {});
    final result = await bridge.executeAction(action);
    if (result.success) {
      state = state.copyWith(error: null, isStreaming: false);
      await _persistAssistantMessage('Page suivante.');
    } else {
      await _persistAssistantMessage(
        '❌ Échec navigation\n\n'
        'Erreur : ${result.error}',
      );
      state = state.copyWith(isStreaming: false);
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
        await _persistAssistantMessage('Aucun formulaire trouvé sur cette page.');
      } else {
        final buffer = StringBuffer();
        final requestedIndex = cmd.args.isNotEmpty ? int.tryParse(cmd.args[0]) : null;

        if (requestedIndex != null) {
          if (requestedIndex < 0 || requestedIndex >= forms.length) {
            await _persistAssistantMessage(
              '❌ Index de formulaire invalide : $requestedIndex\n\n'
              '💡 Indices valides : 0 à ${forms.length - 1}',
            );
            state = state.copyWith(isStreaming: false);
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
        await _persistAssistantMessage(buffer.toString());
      }
    } else {
      await _persistAssistantMessage(
        '❌ Échec extraction formulaires\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que la page est chargée dans l\'extension.',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashTables(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final action = BrowserAction(action: BrowserActionType.extractTables, params: {});
    final result = await bridge.executeAction(action);
    if (result.success && result.data != null) {
      final tables = result.data!['tables'] as List? ?? [];
      if (tables.isEmpty) {
        await _persistAssistantMessage('Aucun tableau trouvé sur cette page.');
      } else {
        final requestedIndex = cmd.args.isNotEmpty ? int.tryParse(cmd.args[0]) : null;
        final buffer = StringBuffer();

        if (requestedIndex != null && (requestedIndex < 0 || requestedIndex >= tables.length)) {
          await _persistAssistantMessage(
            '❌ Index de tableau invalide : $requestedIndex\n\n'
            '💡 Indices valides : 0 à ${tables.length - 1}',
          );
          state = state.copyWith(isStreaming: false);
          return true;
        }

        final start = requestedIndex ?? 0;
        final end = requestedIndex ?? (tables.length - 1);
        final shownCount = end - start + 1;
        buffer.writeln('**$shownCount tableau(x) affiché(s)** | ${result.data!['totalRows'] ?? 0} lignes au total\n');

        for (var i = start; i <= end; i++) {
          final t = tables[i] as Map;
          buffer.writeln('### Tableau ${i + 1} : ${t['rowCount'] ?? '?'} lignes × ${t['colCount'] ?? '?'} colonnes');
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
          if ((t['rowCount'] as int? ?? 0) > 10) buffer.writeln('  ... et ${(t['rowCount'] as int? ?? 0) - 10} autres lignes');
          buffer.writeln();
        }
        buffer.writeln('💡 Utilisez `/export csv` pour exporter les tableaux en CSV.');
        await _persistAssistantMessage(buffer.toString());
      }
    } else {
      await _persistAssistantMessage(
        '❌ Échec extraction tableaux\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que la page est chargée dans l\'extension.',
      );
      state = state.copyWith(isStreaming: false);
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
      await _persistAssistantMessage(buffer.toString());
    } else {
      await _persistAssistantMessage(
        '❌ Échec extraction médias\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que la page est chargée dans l\'extension.',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashMetadata(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final url = cmd.args.isNotEmpty && cmd.args[0].startsWith('http') ? cmd.args[0] : null;

    if (url != null) {
      final globalService = ref.read(searchServiceGlobalProvider);
      try {
        final data = await globalService.scrape(url);
        final buffer = StringBuffer();
        buffer.writeln('**Métadonnées de $url**\n');
        buffer.writeln('| Propriété | Valeur |');
        buffer.writeln('|-----------|--------|');
        buffer.writeln('| Titre | ${data['title'] ?? 'N/A'} |');
        buffer.writeln('| URL | $url |');
        final metaItems = (data['data'] as List? ?? [])
            .where((d) => d['field'] == 'metadata')
            .expand((d) => (d['values'] as List? ?? []).cast<Map>())
            .map((m) => '| ${m['name'] ?? ''} | ${(m['content'] ?? '').toString().replaceAll('\n', ' ').substring(0, (m['content'] ?? '').toString().length < 100 ? (m['content'] ?? '').toString().length : 100)}${(m['content'] ?? '').toString().length > 100 ? '...' : ''} |');
        buffer.writeln(metaItems.join('\n'));
        await _persistAssistantMessage(buffer.toString());
        return true;
      } catch (e) {
        await _persistAssistantMessage(
          '❌ Échec extraction métadonnées\n\n'
          'Erreur backend : $e\n\n'
          '💡 Vérifiez que l\'URL est accessible ou utilisez l\'extension Chrome.',
        );
        state = state.copyWith(isStreaming: false);
        return true;
      }
    }

    if (!bridge.isExtension) {
      await _persistAssistantMessage(
        '❌ Usage incorrect\n\n'
        'Commande `/metadata` sur mobile nécessite une URL.\n\n'
        '💡 **Usage** : `/metadata <url>`',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }

    final action = BrowserAction(action: BrowserActionType.pageMetadata, params: {});
    final result = await bridge.executeAction(action);
    if (!result.success || result.data == null) {
      await _persistAssistantMessage(
        '❌ Échec extraction métadonnées\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que la page est chargée dans l\'extension.',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }

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
    final rawMeta = buffer.toString();

    // LLM : interprétation SEO et suggestions
    final llmPrompt = 'Analyse les métadonnées suivantes d\'une page web. '
        'Identifie le thème principal, évalue le SEO (titre, description, OpenGraph), '
        'signale les métadonnées manquantes importantes, suggère des améliorations. '
        'Réponds en français en 3-4 phrases.\n\n$rawMeta';
    try {
      await sendMessage(llmPrompt);
    } catch (e) {
      await _persistAssistantMessage('$rawMeta\n\n/summarize pour résumer. /export json pour exporter. /links pour les liens.');
    }
    return true;
  }

  Future<bool> _handleSlashAutofill(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    // Étape 1 : Extraire la structure du formulaire
    final formAction = BrowserAction(action: BrowserActionType.extractForms, params: {});
    final formResult = await bridge.executeAction(formAction);

    if (!formResult.success || formResult.data == null) {
      return await _handleSlashAutofillFallback(bridge);
    }

    final forms = formResult.data!['forms'] as List? ?? [];
    if (forms.isEmpty) {
      await _persistAssistantMessage('Aucun formulaire trouvé sur cette page.');
      return true;
    }

    // Étape 2 : Décrire la structure pour le LLM
    final structureBuffer = StringBuffer();
    for (var fi = 0; fi < forms.length; fi++) {
      final f = forms[fi] as Map;
      final inputs = (f['inputs'] as List? ?? []).cast<Map>();
      structureBuffer.writeln('\nFormulaire $fi:');
      for (final input in inputs.take(30)) {
        final name = (input['name'] ?? '').toString();
        final type = (input['type'] ?? 'text').toString();
        final placeholder = (input['placeholder'] ?? '').toString();
        final label = (input['label'] ?? '').toString();
        final required = input['required'] == true ? ' [requis]' : '';
        if (name.isNotEmpty) {
          structureBuffer.writeln('- name="$name" type="$type" placeholder="$placeholder" label="$label"$required');
        }
      }
    }
    final formStructure = structureBuffer.toString();
    if (formStructure.trim().isEmpty) {
      return await _handleSlashAutofillFallback(bridge);
    }

    // Étape 3 : Demander au LLM des valeurs cohérentes
    String? llmJson;
    try {
      final history = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'Tu génères des données de test pour des formulaires web. '
            'Réponds UNIQUEMENT en JSON : {"name1": "valeur1", "name2": "valeur2"}. '
            'Adapte les valeurs au contexte. Pas de markdown, pas d\'explication.'},
        {'role': 'user', 'content': 'Génère des données de test cohérentes pour ce formulaire:\n$formStructure'},
      ];
      final isPro = await ref.read(isProProvider.future).catchError((_) => false);
      final stream = _getDirectAiStream(history, isPro);
      final buf = StringBuffer();
      await for (final token in stream) {
        buf.write(token);
      }
      llmJson = buf.toString().trim();
    } catch (e) {
      debugPrint('[Autofill] LLM failed: $e');
    }

    // Étape 4 : Parser et remplir
    Map<String, String>? fieldValues;
    if (llmJson != null) {
      try {
        final jsonMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(llmJson);
        final jsonStr = jsonMatch?.group(1)?.trim() ?? llmJson;
        final parsed = jsonDecode(jsonStr);
        if (parsed is Map<String, dynamic>) {
          fieldValues = parsed.map((k, v) => MapEntry(k, v.toString()));
        }
      } catch (e) {
        debugPrint('[Autofill] JSON parse failed: $e');
      }
    }

    if (fieldValues != null && fieldValues.isNotEmpty) {
      var filledCount = 0;
      for (final entry in fieldValues.entries) {
        final selector = 'input[name="${entry.key}"], textarea[name="${entry.key}"], select[name="${entry.key}"]';
        final fillAction = BrowserAction(
          action: BrowserActionType.fillForm,
          params: {'selector': selector, 'value': entry.value},
        );
        final fillResult = await bridge.executeAction(fillAction);
        if (fillResult.success) filledCount++;
      }
      await _persistAssistantMessage('Formulaire rempli intelligemment : **$filledCount / ${fieldValues.length}** champ(s).\n\n'
          'Valeurs générées par IA selon le contexte de la page.\n'
          '/fill <sélecteur> <valeur> pour modifier un champ. /forms pour voir les formulaires.');
    } else {
      return await _handleSlashAutofillFallback(bridge);
    }
    return true;
  }

  Future<bool> _handleSlashAutofillFallback(ExtensionBridge bridge) async {
    final action = BrowserAction(action: BrowserActionType.autoFillPage, params: {});
    final result = await bridge.executeAction(action);
    if (result.success && result.data != null) {
      final filled = result.data!['filledCount'] as int? ?? 0;
      final total = result.data!['totalInputs'] as int? ?? 0;
      await _persistAssistantMessage('Formulaire rempli automatiquement : **$filled / $total** champ(s).\n\n'
          'Données de test utilisées (Jean Dupont). Modifiez les champs si nécessaire.\n'
          '/fill <sélecteur> <valeur> pour modifier un champ spécifique. /forms pour voir les formulaires.');
    } else {
      await _persistAssistantMessage(
        '❌ Échec remplissage automatique\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez qu\'un formulaire est présent sur la page.',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashInspect(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      await _persistAssistantMessage(
        '❌ Usage incorrect\n\n'
        '💡 **Usage** : `/inspect <sélecteur CSS>`',
      );
      state = state.copyWith(isStreaming: false);
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
      await _persistAssistantMessage(buffer.toString());
    } else {
      await _persistAssistantMessage(
        '❌ Échec inspection\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que le sélecteur CSS est correct.',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashHighlight(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      await _persistAssistantMessage(
        '❌ Usage incorrect\n\n'
        '💡 **Usage** : `/highlight <sélecteur CSS>`',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }
    final action = BrowserAction(
      action: BrowserActionType.highlightElement,
      params: {'selector': cmd.args[0]},
    );
    final result = await bridge.executeAction(action);
    if (result.success) {
      await _persistAssistantMessage('Élément `${cmd.args[0]}` surligné pendant 3 secondes.');
    } else {
      await _persistAssistantMessage(
        '❌ Échec surbrillance\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que le sélecteur CSS est correct.',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashWaitFor(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      await _persistAssistantMessage(
        '❌ Usage incorrect\n\n'
        '💡 **Usage** : `/waitfor <sélecteur CSS> [timeout_ms]`',
      );
      state = state.copyWith(isStreaming: false);
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
      await _persistAssistantMessage('Élément `${cmd.args[0]}` apparu après ${waited}ms.\n'
          '💡 `/inspect ${cmd.args[0]}` pour l\'analyser. `/click ${cmd.args[0]}` pour cliquer dessus.');
    } else {
      await _persistAssistantMessage(
        '❌ Timeout\n\n'
        'L\'élément `${cmd.args[0]}` n\'est pas apparu dans le délai imparti.\n\n'
        '💡 Augmentez le timeout : `/waitfor ${cmd.args[0]} 20000`',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashExport(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    // Parse args: [/export [url] [format]] or [/export [format]]
    final firstArg = cmd.args.isNotEmpty ? cmd.args[0] : 'json';
    final String? url = firstArg.startsWith('http') ? firstArg : null;
    final format = url != null
        ? (cmd.args.length > 1 ? cmd.args[1] : 'json')
        : firstArg;

    String title;
    String content;
    String pageUrl;

    if (url != null) {
      // Backend fallback: scrape the URL directly
      final globalService = ref.read(searchServiceGlobalProvider);
      try {
        final data = await globalService.scrape(url);
        title = data['title'] as String? ?? url;
        final contentItems = (data['data'] as List? ?? [])
            .where((d) => d['field'] == 'cards' || d['field'] == 'prices' || d['field'] == 'metadata')
            .expand((d) => (d['values'] as List? ?? []).map((v) => v is Map ? v['text'] ?? v.toString() : v.toString()))
            .where((t) => t.toString().isNotEmpty)
            .join('\n');
        content = contentItems.isNotEmpty
            ? contentItems
            : (data['data'] as List? ?? [])
                .where((d) => d['field'] == 'content')
                .expand((d) => (d['values'] as List? ?? []))
                .where((t) => t.toString().isNotEmpty)
                .join('\n');
        if (content.isEmpty) {
          content = '_Aucun contenu extrait._';
        }
        pageUrl = url;
      } catch (e) {
        await _persistAssistantMessage(
          '❌ Échec export\n\n'
          'Erreur backend : $e\n\n'
          '💡 Vérifiez que l\'URL est accessible ou utilisez l\'extension Chrome.',
        );
        state = state.copyWith(isStreaming: false);
        return true;
      }
    } else if (bridge.isExtension) {
      // Extension mode: extract current page content
      final contentAction = BrowserAction(
        action: BrowserActionType.getPageContent,
        params: {},
      );
      final contentResult = await bridge.executeAction(contentAction);

      if (!contentResult.success) {
        await _persistAssistantMessage(
          '❌ Échec export\n\n'
          'Erreur : ${contentResult.error}\n\n'
          '💡 Vérifiez que la page est chargée dans l\'extension.',
        );
        state = state.copyWith(isStreaming: false);
        return true;
      }

      title = contentResult.data!['title'] as String? ?? 'page';
      content = contentResult.data!['content'] as String? ?? '';
      pageUrl = contentResult.data!['url'] as String? ?? '';
    } else {
      await _persistAssistantMessage(
        '❌ Usage incorrect\n\n'
        'Commande `/export` sur mobile nécessite une URL.\n\n'
        '💡 **Usage** : `/export <url> [json|csv|md]`',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }

    final safeTitle = title.replaceAll(RegExp(r'[^a-zA-Z0-9À-ɏ\s-]'), '_').trim();

    switch (format) {
      case 'json':
        final json = '{\n  "title": ${_jsonStr(title)},\n  "url": ${_jsonStr(pageUrl)},\n'
            '  "content": ${_jsonStr(content.substring(0, content.length > 10000 ? 10000 : content.length))}\n}';
        await _persistAssistantMessage('**Export JSON :**\n```json\n$json\n```\n\n'
            '💡 Copiez ce contenu ou utilisez `/download <url>` pour des fichiers distants.');
        break;
      case 'md':
      case 'markdown':
        final md = '# $title\n\n> Source : $pageUrl\n\n$content';
        await _persistAssistantMessage('**Export Markdown :**\n```markdown\n${md.substring(0, md.length > 3000 ? 3000 : md.length)}\n```\n\n'
            '${md.length > 3000 ? '(tronqué à 3000 caractères)\n\n' : ''}'
            '💡 `/pdf` pour imprimer la page. `/download` pour fichiers distants.');
        break;
      case 'csv':
        if (bridge.isExtension && url == null) {
          // Exporter les tableaux comme CSV (extension only, current page)
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
            await _persistAssistantMessage('**Export CSV (tableaux) :**\n```csv\n${csvBuffer.toString().substring(0, 3000)}\n```\n\n'
                '💡 Les données CSV peuvent être ouvertes dans Excel / Google Sheets.');
          } else {
            await _persistAssistantMessage('Aucun tableau trouvé pour l\'export CSV. Utilisez `/export json` ou `/export md`.');
          }
        } else {
          await _persistAssistantMessage(
            'Export CSV depuis une URL : le contenu textuel a été extrait. '
            'Pour les tableaux, utilisez `/extract <url> table` ou l\'extension Chrome.',
          );
        }
        break;
      default:
        await _persistAssistantMessage(
          '❌ Format inconnu : `$format`\n\n'
          '💡 Formats supportés : `json`, `csv`, `md` (markdown)',
        );
        state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashMonitor(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      await _persistAssistantMessage(
        '❌ Usage incorrect\n\n'
        '💡 **Usage** : `/monitor <sélecteur CSS> [interval_sec]`',
      );
      state = state.copyWith(isStreaming: false);
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
      await _persistAssistantMessage('**Vérification ponctuelle** : `${selector}`\n\n'
          'Valeur actuelle : "${text.substring(0, text.length > 200 ? 200 : text.length)}"\n\n'
          'Relancez `/monitor $selector $clampedInterval` pour vérifier à nouveau.\n'
          '💡 Idéal pour : prix, disponibilité, score, statut. '
          'Combo : `/waitfor <selecteur>` puis `/click` quand prêt.');
    } else {
      await _persistAssistantMessage(
        '❌ Échec surveillance\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que le sélecteur CSS est correct.',
      );
      state = state.copyWith(isStreaming: false);
    }
    return true;
  }

  Future<bool> _handleSlashTranslate(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    final targetLang = cmd.args.isNotEmpty ? cmd.args[0] : 'fr';
    const supportedLangs = ['fr', 'en', 'es', 'de', 'it', 'pt', 'ja', 'zh', 'ar', 'ru', 'ko', 'nl'];
    if (!supportedLangs.contains(targetLang)) {
      await _persistAssistantMessage(
        '❌ Langue non supportée : `$targetLang`\n\n'
        '💡 Langues supportées : ${supportedLangs.join(', ')}',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }

    final contentAction = BrowserAction(
      action: BrowserActionType.getPageContent,
      params: {},
    );
    final contentResult = await bridge.executeAction(contentAction);
    if (!contentResult.success) {
      await _persistAssistantMessage(
        '❌ Échec extraction contenu\n\n'
        'Erreur : ${contentResult.error}\n\n'
        '💡 Vérifiez que la page est chargée dans l\'extension.',
      );
      state = state.copyWith(isStreaming: false);
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

    await sendMessage(translatePrompt, bypassSlashCheck: true);
    return true;
  }

  Future<bool> _handleSlashSearchPage(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      await _persistAssistantMessage(
        '❌ Usage incorrect\n\n'
        '💡 **Usage** : `/searchpage <terme>`',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }
    final searchTerm = cmd.args.join(' ');

    final action = BrowserAction(
      action: BrowserActionType.getPageContent,
      params: {},
    );
    final result = await bridge.executeAction(action);
    if (!result.success) {
      await _persistAssistantMessage(
        '❌ Échec extraction page\n\n'
        'Erreur : ${result.error}\n\n'
        '💡 Vérifiez que la page est chargée dans l\'extension.',
      );
      state = state.copyWith(isStreaming: false);
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
      await _persistAssistantMessage('Terme **"$searchTerm"** non trouvé dans la page.\n'
          'Essayez `/summarize` pour un résumé, ou `/metadata` pour les mots-clés de la page.');
      return true;
    }

    // Construire les snippets de contexte
    final buffer = StringBuffer();
    buffer.writeln('**"$searchTerm"** trouvé **${occurrences.length} fois** :\n');
    for (var i = 0; i < occurrences.length && i < 10; i++) {
      final pos = occurrences[i];
      final start = pos > 80 ? pos - 80 : 0;
      final end = pos + searchTerm.length + 80 < content.length ? pos + searchTerm.length + 80 : content.length;
      final context = content.substring(start, end).replaceAll('\n', ' ');
      final prefix = start > 0 ? '...' : '';
      final suffix = end < content.length ? '...' : '';
      buffer.writeln('${i + 1}. $prefix$context$suffix');
    }
    if (occurrences.length > 10) buffer.writeln('\net ${occurrences.length - 10} autres occurrences...');
    final rawResult = buffer.toString();

    // LLM : analyse sémantique des occurrences
    final snippet = rawResult.length > 3000 ? rawResult.substring(0, 3000) : rawResult;
    final llmPrompt = 'Analyse les occurrences du terme "$searchTerm" trouvées dans cette page. '
        'Donne un résumé sémantique : de quoi la page parle quand elle mentionne ce terme ? '
        'Quels sont les contextes principaux ? Réponds en 2-3 phrases.\n\nOccurrences:\n$snippet';
    try {
      await sendMessage(llmPrompt, bypassSlashCheck: true);
    } catch (e) {
      await _persistAssistantMessage('$rawResult\n\n/extract pour extraire une section. /summarize pour un résumé.');
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
    final allowed = {'pdf', 'word', 'powerpoint', 'excel', 'markdown', 'text', 'jpg', 'png'};
    if (!allowed.contains(normalizedFormat)) {
      state = state.copyWith(
        error: 'Format non supporte: ${cmd.args[0]}. Utilisez pdf, word, powerpoint, excel, markdown, text, jpg, png.',
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

      // Image formats skip text draft generation — use the topic directly as prompt
      final String draft;
      final String title;
      if (normalizedFormat == 'jpg' || normalizedFormat == 'png') {
        draft = topic;
        title = topic;
      } else {
        draft = await _generateDocumentDraft(
          topic: topic,
          format: normalizedFormat,
          searchContext: searchContext,
          isPro: isPro,
        );
        // For PowerPoint, force the title to be the exact user topic to avoid
        // generic LLM-generated titles like "Voici un document complet..."
        title = normalizedFormat == 'powerpoint'
            ? topic
            : _extractDocumentTitle(draft, fallbackTopic: topic);
      }

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
        await _persistAssistantMessage(
          'Document genere: **${generated.fileName}** (${generated.sizeBytes} octets)\n'
          'Format: $normalizedFormat\n\n'
          '---\n\n$shortPreview\n'
          '---$downloadHint\n\n'
          'La generation combine les connaissances IA et les resultats web recents.',
        );
      } else {
        final shortPreview = draft.length > 500 ? '${draft.substring(0, 500)}...' : draft;
        await _persistAssistantMessage(
          'Document genere: ${generated.fileName} (${generated.sizeBytes} octets).\n'
          'Format: $normalizedFormat\n\n'
          'Apercu:\n$shortPreview\n\n'
          'La generation combine les connaissances IA et les resultats web recents.',
        );
      }
    } on AiException catch (e) {
      await _persistAssistantMessage(
        '❌ Échec génération document\n\n'
        '${_formatAiError(e)}\n\n'
        '💡 Réessayez avec un sujet plus court ou vérifiez votre connexion.',
      );
      state = state.copyWith(isStreaming: false, isSearching: false);
    } catch (e) {
      await _persistAssistantMessage(
        '❌ Échec génération document\n\n'
        'Erreur : $e\n\n'
        '💡 Réessayez avec un format supporté (word, excel, powerpoint, pdf, markdown, text, jpg, png).',
      );
      state = state.copyWith(isStreaming: false, isSearching: false);
    } finally {
      if (state.isStreaming || state.isSearching) {
        state = state.copyWith(isStreaming: false, isSearching: false);
      }
    }

    return true;
  }

  Future<bool> _handleSlashScrape(ParsedSlashCommand cmd, ExtensionBridge bridge) async {
    if (cmd.args.isEmpty) {
      await _persistAssistantMessage(
        '❌ Usage incorrect\n\n'
        'Commande `/scrape` nécessite une URL.\n\n'
        '💡 **Usage** : `/scrape <url> [selectors_json]`',
      );
      state = state.copyWith(isStreaming: false);
      return true;
    }
    final url = cmd.args[0];
    Map<String, String>? selectors;
    if (cmd.args.length > 1) {
      try {
        final decoded = jsonDecode(cmd.args[1]) as Map<String, dynamic>;
        selectors = decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (e) {
        await _persistAssistantMessage(
          '❌ JSON invalide\n\n'
          'Le paramètre selectors_json n\'est pas valide : $e\n\n'
          '💡 **Exemple** : `/scrape https://example.com {"prix":".price","titre":"h1"}`',
        );
        state = state.copyWith(isStreaming: false);
        return true;
      }
    }
    final globalService = ref.read(searchServiceGlobalProvider);
    try {
      final data = await globalService.scrape(url, selectors: selectors);
      final buffer = StringBuffer();
      buffer.writeln('**Scraping de $url**\n');
      buffer.writeln('Titre: ${data['title'] ?? 'N/A'}\n');
      final dataList = data['data'] as List? ?? [];
      for (final item in dataList) {
        final field = item['field'] as String? ?? '';
        final values = item['values'] as List? ?? [];
        buffer.writeln('### $field (${values.length})');
        for (final v in values.take(10)) {
          if (v is Map) {
            buffer.writeln('- ${v['text'] ?? v['value'] ?? v}');
          } else {
            buffer.writeln('- $v');
          }
        }
        buffer.writeln();
      }
      if (dataList.isEmpty) {
        buffer.writeln('_Aucune donnée structurée trouvée._');
      }
      await _persistAssistantMessage(buffer.toString());
    } catch (e) {
      await _persistAssistantMessage(
        '❌ Échec scrape\n\n'
        'Erreur : $e\n\n'
        '💡 Vérifiez que l\'URL est accessible et que le backend est disponible.',
      );
      state = state.copyWith(isStreaming: false);
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
    if (lower == 'jpg' || lower == 'jpeg') return 'jpg';
    if (lower == 'png') return 'png';
    if (lower == 'pdf') return 'pdf';
    return lower;
  }

  Future<String> _generateDocumentDraft({
    required String topic,
    required String format,
    required String searchContext,
    required bool isPro,
  }) async {
    final isPowerpoint = format == 'powerpoint';

    final system = isPowerpoint
        ? 'Tu es un concepteur de presentations PowerPoint expert. '
            'Tu produis des presentations avec structure claire, sections numerotees, '
            'contenu concis et percutant adapte aux diapositives. '
            'NE mets PAS de \"DIAPOSITIVE X\" dans les titres. '
            'Pour chaque section importante, suggere une illustration via un bloc '
            '\"Image suggeree : Description : [description detaillee]. Utilite : [but].\" '
            'apres le contenu de la section.'
        : 'Tu es un redacteur expert. Tu produis des documents finalisables '
            'avec structure claire, sections numerotees, contenu factuel verifiable, '
            'et un bloc "Images suggerees" qui decrit les visuels utiles.';

    final user = isPowerpoint
        ? 'Genere une presentation complete sur: "$topic". '
            'Format: presentation PowerPoint. '
            'Structure requise:\n'
            '1. TITRE (une seule ligne, le sujet exact: "$topic")\n'
            '2. SOMMAIRE (liste des sections)\n'
            '3. INTRODUCTION (contexte et objectifs)\n'
            '4. SECTIONS DETAILLEES (4-6 sections max, titres courts et percutants, '
            'PAS de numeros de diapositives, chaque section suivie d\'un bloc "Image suggeree")\n'
            '5. CONCLUSION / PLAN D\'ACTIONS\n'
            '6. SOURCES (URLs des references)\n\n'
            'Regles:\n'
            '- Les titres de sections doivent etre courts (pas de "DIAPOSITIVE X –")\n'
            '- Chaque section doit etre suivie d\'un bloc "Image suggeree : Description : [description]. Utilite : [but]."\n'
            '- Contenu concis, adapte a une presentation orale\n'
            '- Ecris en francais sauf si le sujet impose une autre langue.\n\n'
            'Contexte web:\n$searchContext'
        : 'Genere un document complet sur: "$topic". '
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

  /// Ajoute un message assistant au state ET le persiste dans le repo.
  Future<void> _persistAssistantMessage(String text) async {
    // Retention : extraire les sujets favoris de la reponse IA
    try {
      await ref.read(userProfileServiceProvider).extractInterestsFromText(text);
    } catch (e) {
      debugPrint('[Retention] Error extracting interests: $e');
    }

    final msg = Message(
      id: 'slash_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: arg,
      role: Role.assistant,
      content: text,
      isStreaming: false,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(messages: [...state.messages, msg]);

    // Apprentissage : stocker la reponse slash dans la base de connaissances
    try {
      await _knowledgeBase.add(text, text);
      await _insights.recordFeatureUsage('slash_command');
    } catch (e) {
      debugPrint('[ChatNotifier] Learning hook error in _persistAssistantMessage: $e');
    }
    try {
      if (isDemoMode) {
        await mockChatRepository.addMessage(
          conversationId: arg,
          role: Role.assistant,
          content: text,
        );
      } else {
        await ref.read(chatRepositoryProvider).addMessage(
          conversationId: arg,
          role: Role.assistant,
          content: text,
        );
      }
    } catch (_) {
      // Non-bloquant : le message est déjà dans le state local
    }
  }

  Future<void> sendMessage(
    String text, {
    String? imageBase64,
    String? imageMimeType,
    String? fileName,
    String? fileContent,
    List<Attachment>? attachments,
    bool isVoiceConversation = false,
    String? modelOverride,
    bool bypassSlashCheck = false,
  }) async {
    final trimmed = text.trim();
    final hasAttachment = imageBase64 != null || fileContent != null || (attachments != null && attachments.isNotEmpty);
    if (trimmed.isEmpty && !hasAttachment) return;
    if (trimmed.length > 10000 || (state.isStreaming && !bypassSlashCheck)) return;

    // Vérification limite 5MB agrégée
    final attachmentList = attachments ?? [];
    final totalSize = attachmentList.fold<int>(0, (s, a) => s + a.sizeBytes);
    if (totalSize > maxAttachmentsTotalBytes) {
      state = state.copyWith(
        error: 'Taille limite dépassée (5MB par message). Vous pouvez ajouter plusieurs fichiers, mais la taille totale ne doit pas dépasser 5MB.',
        isStreaming: false,
      );
      return;
    }

    // Message par défaut pour les pièces jointes sans texte
    final effectiveText = trimmed.isEmpty && hasAttachment
        ? 'Analyse ce document'
        : trimmed;

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

    // Nouveau message valide : effacer tout pending precedent.
    _pendingMessage = null;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final isPro = await ref.read(isProProvider.future).catchError((_) => false);
    if (!isPro) {
      // Helper local : bloque le message avec le quota depasse.
      // Capture les parametres de sendMessage pour eviter la duplication x6.
      void _blockForQuota(String errorKey) {
        _pendingMessage = _PendingMessage(
          text: text,
          imageBase64: imageBase64,
          imageMimeType: imageMimeType,
          fileName: fileName,
          fileContent: fileContent,
          attachments: attachments,
          isVoiceConversation: isVoiceConversation,
          modelOverride: modelOverride,
          bypassSlashCheck: bypassSlashCheck,
        );
        state = state.copyWith(error: errorKey, isStreaming: false);
      }

      try {
        final remaining =
            await ref.read(quotaServiceProvider).checkAndDecrement();
        state = state.copyWith(remainingRequests: remaining);
      } on QuotaExceededException {
        _blockForQuota('quota_exceeded');
        return;
      } on FirebaseFunctionsException catch (e) {
        debugPrint('[Quota] Cloud Function unavailable: ${e.message}');
        // Fallback local : credit service
        try {
          final remaining = await ref.read(creditServiceProvider).decrement();
          state = state.copyWith(remainingRequests: remaining);
        } on CreditsExhaustedException {
          _blockForQuota('quota_exceeded');
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
          _blockForQuota('quota_exceeded');
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
          _blockForQuota('quota_files_exceeded');
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
          _blockForQuota('quota_search_exceeded');
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
          _blockForQuota('quota_voice_exceeded');
          return;
        } catch (e) {
          debugPrint('[VoiceQuota] Error: $e');
        }
      }
    }

    final attachmentContext = _buildAttachmentContextForHistory(
      text: effectiveText,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      fileName: fileName,
      fileContent: fileContent,
      attachments: attachments ?? attachmentList,
      isPro: isPro,
    );

    // 1. Persister le message utilisateur dans le repo
    final userMsg = isDemoMode
        ? await mockChatRepository.addMessage(
            conversationId: arg,
            role: Role.user,
            content: effectiveText,
            imageBase64: imageBase64,
            imageMimeType: imageMimeType,
            fileName: fileName,
            attachments: attachments ?? attachmentList,
            fileContext: attachmentContext,
          )
        : await ref.read(chatRepositoryProvider).addMessage(
            conversationId: arg,
            role: Role.user,
            content: effectiveText,
            imageBase64: imageBase64,
            imageMimeType: imageMimeType,
            fileName: fileName,
            attachments: attachments ?? attachmentList,
            fileContext: attachmentContext,
          );

    // Retention : enregistrer l'usage
    try {
      await ref.read(usageStatsServiceProvider).recordMessageSent();
      await ref.read(userProfileServiceProvider).extractInterestsFromText(effectiveText);
    } catch (e) {
      debugPrint('[Retention] Error recording usage: $e');
    }

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
        // ── NOUVEAU : SearchServiceGlobal unifié ──────────────────────────
        final globalService = ref.read(searchServiceGlobalProvider);
        final smartResponse = await globalService.search(userMsg.content);
        if (smartResponse.hasConcreteResults || smartResponse.links.isNotEmpty) {
          enhancedResultMarkdown = SearchServiceGlobal.formatMarkdown(
              smartResponse, userMsg.content);
          debugPrint('[ChatNotifier] SearchServiceGlobal OK: '
              'intent=${smartResponse.intent}, results=${smartResponse.results.length}');
        } else {
          // Fallback sur l'ancien système
          enhancedResultMarkdown = await _performEnhancedSearch(
              userMsg.content, intent, _extractSearchQuery(userMsg.content), appLang, searchParams);
        }
        // Record successful extraction for learning
        extractor.memory.recordSuccess(intent, userMsg.content, searchParams);
        // Record anonymized insight
        await _insights.recordSearch(userMsg.content, intent);
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
            attachments: attachments,
            enhancedContext: enhancedResultMarkdown,
            modelOverride: modelOverride,
            isVoiceConversation: isVoiceConversation,
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
          // Marquer le modèle comme rate-limited sur 429
          if (e.statusCode == 429) {
            ModelRouter.markRateLimited(_lastUsedModelId ?? 'unknown');
          }
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

      final model = _lastUsedModelId ?? AppConstants.deepSeekModel;

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

      // 6. Apprentissage : stocker Q/R dans la base de connaissances
      try {
        await _knowledgeBase.add(userMsg.content, finalContent);
        await _insights.recordFeatureUsage('chat_response');
      } catch (e) {
        debugPrint('[ChatNotifier] Learning hook error: $e');
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
    List<Attachment>? attachments,
    required bool isPro,
  }) {
    final buffer = StringBuffer();

    // Nouveau format : pièces jointes multiples
    if (attachments != null && attachments.isNotEmpty) {
      for (final att in attachments) {
        if (att.isImage && att.imageBase64 != null) {
          final prompt = text.isNotEmpty ? text : 'Analyse cette image';
          buffer.writeln('Image utilisateur jointe (${att.mimeType}). Demande: $prompt');
        } else if (att.extractedText != null && att.extractedText!.isNotEmpty) {
          final doc = FileUploadService.truncateForContext(att.extractedText!, isPro: isPro);
          buffer.writeln('Document utilisateur: ${att.name}');
          buffer.writeln(doc);
          buffer.writeln();
        }
      }
      if (buffer.isNotEmpty) return buffer.toString().trim();
    }

    // Legacy fallback
    if (fileContent != null && fileContent.isNotEmpty) {
      final doc = FileUploadService.truncateForContext(fileContent, isPro: isPro);
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
    List<Attachment>? attachments,
    String? enhancedContext,
    String? modelOverride,
    bool isVoiceConversation = false,
  }) async {
    // ── 0. Prompt système Corely ───────────────────────────────────────────
    final corelySystemPrompt = ref.read(systemPromptProvider);

    var fullSystemPrompt = PlatformService.isExtension
        ? '$corelySystemPrompt\n\n$_browserActionSystemContext'
        : corelySystemPrompt;

    // Prompt jovial pour les conversations vocales
    if (isVoiceConversation) {
      fullSystemPrompt =
          '$fullSystemPrompt\n\n'
          'MODE VOCAL ACTIF — Réponds comme un ami au téléphone : '
          'jovial, naturel, concis (2-3 phrases max), pas de listes, pas de markdown. '
          'Tutoie, sois chaleureux et dynamique. Pas de "En tant qu\'IA" ni d\'excuses inutiles. '
          'Va droit au but avec le sourire.\n\n'
          'Parle avec un rythme naturel, comme à l\'oral. Marque de courtes pauses avec "..." '
          'si cela aide la fluidité. N\'hésite pas à hésiter légèrement — "euh", "hmm" — '
          'comme le ferait un vrai humain.\n\n'
          'Tu peux utiliser des balises émotionnelles au début de ta réponse pour adapter ta voix : '
          '[joyeux], [triste], [sérieux], [excité], [neutre], [amical], [enthousiaste]. '
          'Exemple : "[joyeux] Salut ! Ça va super aujourd\'hui ?"';
    }

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
    final attTypes = attachments?.map((a) => a.type.name).toList();
    return _getDirectAiStream(
      historyMaps,
      isPro,
      modelOverride: modelOverride,
      isVoiceConversation: isVoiceConversation,
      attachmentTypes: attTypes,
    );
  }

  Stream<String> _getDirectAiStream(
    List<Map<String, dynamic>> history,
    bool isPro, {
    String? modelOverride,
    bool isVoiceConversation = false,
    List<String>? attachmentTypes,
  }) {
    // 1. Les images passent TOUJOURS par un modele vision
    // Verifier UNIQUEMENT le dernier message utilisateur, pas tout l'historique
    final lastUserMsg = history.lastWhere(
      (m) => m['role'] == 'user',
      orElse: () => {'content': ''},
    );
    final lastContent = lastUserMsg['content'];
    final hasImage = lastContent is List;
    if (hasImage) {
      return _getVisionStream(history);
    }

    // 2. Cloudflare Worker — chemin primaire sécurisé (pas de clés API dans l'APK)
    if (AppConstants.isWorkerConfigured) {
      // Classifier la tâche pour choisir le meilleur modèle
      final lastUserContent = history.lastWhere(
        (m) => m['role'] == 'user',
        orElse: () => {'content': ''},
      )['content'];
      final userText = (lastUserContent is String) ? lastUserContent : '';
      final taskType = ModelRouter.classifyTaskEnhanced(
        userText,
        attachmentTypes: attachmentTypes,
      );
      final effectiveModel = modelOverride ?? state.selectedModel;
      final entry = ModelRouter.resolveModel(taskType, userOverride: effectiveModel);
      return _getWorkerStream(
        history,
        model: entry?.modelId,
        isVoiceConversation: isVoiceConversation,
      );
    }

    // 3. Fallback : appel direct aux API (développement local sans Worker)
    final lastUserContent = history.lastWhere(
      (m) => m['role'] == 'user',
      orElse: () => {'content': ''},
    )['content'];
    final userText = (lastUserContent is String) ? lastUserContent : '';
    final taskType = ModelRouter.classifyTaskEnhanced(
      userText,
      attachmentTypes: attachmentTypes,
    );
    final params = ModelRouter.resolveParams(taskType);
    final effectiveOverride = modelOverride ?? state.selectedModel;
    final entry = ModelRouter.resolveModel(taskType, userOverride: effectiveOverride);

    if (entry == null) {
      return _mockResponseStream();
    }

    debugPrint('[ChatNotifier] ${taskType.name} → ${entry.modelId} (${entry.provider}) | temp=${params.temperature} maxTokens=${params.maxTokens} thinking=${params.enableThinking}');
    _lastUsedModelId = entry.modelId;
    return _buildStreamForModel(
      entry,
      history,
      isVoiceConversation: isVoiceConversation,
      taskType: taskType,
      params: params,
    );
  }

  /// Stream via le Worker Cloudflare (chemin principal sécurisé).
  /// Le Worker gère le routing LLM, le rate limiting et la sanitization.
  Stream<String> _getWorkerStream(
    List<Map<String, dynamic>> history, {
    String? model,
    bool isVoiceConversation = false,
  }) async* {
    debugPrint('[ChatNotifier] Routing via Cloudflare Worker (model: ${model ?? 'auto'})');
    _lastUsedModelId = model ?? 'worker:auto';

    final buffer = StringBuffer();
    bool workerProducedContent = false;

    try {
      final workerClient = WorkerChatClient();
      final stream = workerClient.streamChat(
        messages: history,
        model: model,
        temperature: isVoiceConversation ? 0.95 : 0.7,
        maxTokens: isVoiceConversation ? 2048 : 4096,
      );

      await for (final chunk in stream) {
        buffer.write(chunk);
        workerProducedContent = true;
        yield chunk;
      }
      
      // Si le Worker n'a produit aucun contenu, fallback direct
      if (!workerProducedContent) {
        debugPrint('[ChatNotifier] Worker returned empty content — falling back to direct API');
        yield* _fallbackToDirectApiStream(history, isVoiceConversation: isVoiceConversation);
      }
    } on AiException catch (e) {
      debugPrint('[ChatNotifier] Worker failed: $e — falling back to direct API');
      yield* _fallbackToDirectApiStream(history, isVoiceConversation: isVoiceConversation);
    }
  }

  /// Fallback : appel direct aux API DeepSeek/OpenRouter.
  Stream<String> _fallbackToDirectApiStream(
    List<Map<String, dynamic>> history, {
    bool isVoiceConversation = false,
  }) async* {
    final taskType = TaskType.general;
    final entry = ModelRouter.resolveModel(taskType);
    if (entry != null) {
      _lastUsedModelId = entry.modelId;
      yield* _buildStreamForModel(
        entry,
        history,
        isVoiceConversation: isVoiceConversation,
        taskType: taskType,
        params: ModelRouter.resolveParams(taskType),
      );
    }
  }

  /// Construit le stream pour un modèle donné selon son provider.
  Stream<String> _buildStreamForModel(
    ModelEntry entry,
    List<Map<String, dynamic>> history, {
    String? systemPrompt,
    bool isVoiceConversation = false,
    TaskType? taskType,
    ModelParams? params,
  }) {
    final effectiveParams = params ?? ModelRouter.resolveParams(taskType ?? TaskType.general);

    if (entry.provider == 'deepseek') {
      final key = AppConstants.deepSeekApiKey;
      if (key.isEmpty) return _mockResponseStream();
      return DeepSeekClient(apiKey: key).streamChat(
        messages: history,
        model: entry.modelId,
        systemPrompt: systemPrompt,
        enableSearch: entry.supportsSearch,
        maxTokens: effectiveParams.maxTokens,
        temperature: isVoiceConversation ? 0.95 : effectiveParams.temperature,
      );
    }

    // OpenRouter
    final key = AppConstants.openRouterApiKey;
    if (key.isEmpty) return _mockResponseStream();
    return OpenRouterClient(apiKey: key).streamChat(
      messages: history,
      model: entry.modelId,
      systemPrompt: systemPrompt,
      maxTokens: effectiveParams.maxTokens,
      temperature: isVoiceConversation ? 0.95 : effectiveParams.temperature,
      topP: isVoiceConversation ? 0.95 : null,
      frequencyPenalty: isVoiceConversation ? 0.2 : null,
    );
  }

  /// Route une requete avec image vers un modele vision.
  /// Priorite : Ollama (si configure) > ModelRouter vision chain.
  Stream<String> _getVisionStream(List<Map<String, dynamic>> history) async* {
    // 0. Ollama vision locale (si configuré et disponible)
    final ollama = ref.read(ollamaVisionServiceProvider);
    await ollama.loadConfig();
    if (ollama.enabled) {
      final available = await ollama.isAvailable();
      if (available) {
        debugPrint('[ChatNotifier] Vision via Ollama');
        try {
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

    // 1. ModelRouter vision chain (gemini-flash → deepseek-chat → gpt-4o-mini)
    final entry = ModelRouter.resolveModel(TaskType.vision);
    if (entry != null) {
      debugPrint('[ChatNotifier] Vision via ${entry.modelId}');
      _lastUsedModelId = entry.modelId;
      yield* _buildStreamForModel(entry, history);
      return;
    }

    throw const AiException(
      'Analyse d\'image indisponible. Verifiez vos cles API (DeepSeek ou OpenRouter).',
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

  void selectModel(String model) {
    state = state.copyWith(selectedModel: model);
  }

  /// Relance automatiquement le dernier message bloque par quota.
  Future<void> retryPendingMessage() async {
    final pending = _pendingMessage;
    if (pending == null) return;
    _pendingMessage = null;
    await sendMessage(
      pending.text,
      imageBase64: pending.imageBase64,
      imageMimeType: pending.imageMimeType,
      fileName: pending.fileName,
      fileContent: pending.fileContent,
      attachments: pending.attachments,
      isVoiceConversation: pending.isVoiceConversation,
      modelOverride: pending.modelOverride,
      bypassSlashCheck: pending.bypassSlashCheck,
    );
  }

  /// Annule le message en attente (utilisateur a ferme le dialog sans bonus).
  void clearPendingMessage() => _pendingMessage = null;

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
    const numericDate = r'\d{1,2}[/.-]\d{1,2}(?:[/.-]\d{2,4})?';
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

    // Pattern D: "City1-City2 date" or "City1 City2 date" — compact, no du/le required
    final compactNumDates = RegExp(
      '(?:de\\s+)?($cityName)\\s+'
      r'(?:à|vers|pour|-)?\s*'
      '($cityName)\\b'
      r'.{0,20}?'
      '(?:d[ue]|le)?\\s*(' + numericDate + r')',
    );
    final matchD = compactNumDates.firstMatch(message);
    if (matchD != null) {
      return {
        'from': matchD.group(1)!.trim(),
        'to': matchD.group(2)!.trim(),
        'departDate': normalizeDate(matchD.group(3)!),
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
    // Accept dd/mm[/yyyy], dd-mm[-yyyy], dd.mm[.yyyy] → yyyy-mm-dd
    final parts = raw.trim().split(RegExp(r'[/.-]'));
    if (parts.length >= 2) {
      try {
        final d = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        var y = DateTime.now().year;
        if (parts.length >= 3) {
          y = int.parse(parts[2]);
          if (y < 100) y += 2000;
        }
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
