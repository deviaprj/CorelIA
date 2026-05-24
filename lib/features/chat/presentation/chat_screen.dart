import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'chat_notifier.dart';
import 'chat_bubble.dart';
import 'input_bar.dart';
import 'slash_commands.dart';
import '../domain/message.dart';
import 'voice_conversation_service.dart';
import 'aurora_splash.dart';
import '../data/image_upload_service.dart';
import '../data/file_upload_service.dart';
import '../data/file_quota_service.dart';
import '../data/search_quota_service.dart';
import '../data/voice_quota_service.dart';
import '../../../core/platform/platform_service.dart';
import '../../../core/platform/extension_providers.dart';
import '../../../core/platform/extension_bridge.dart';
import '../../monetization/ads/ad_banner_widget.dart';
import '../../monetization/ads/quota_exceeded_dialog.dart';
import '../../monetization/subscription/subscription_service.dart';
import '../../monetization/credits/credit_service.dart';
import '../../monetization/credits/credit_providers.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();
  List<AttachmentData> _pendingAttachments = [];
  final _inputBarController = TextEditingController();
  final _inputBarKey = GlobalKey<InputBarState>();
  String? _slashFilter;
  StreamSubscription<BrowserActionResult>? _actionResultSub;

  @override
  void dispose() {
    _scrollController.dispose();
    _inputBarController.dispose();
    _actionResultSub?.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _showQuotaDialog(QuotaType type) async {
    final granted = await showQuotaExceededDialog(
      context,
      quotaType: type,
      onBonusGranted: () async {
        switch (type) {
          case QuotaType.requests:
            await ref.read(creditServiceProvider).addBonus(amount: 5);
          case QuotaType.searches:
            await ref.read(searchQuotaServiceProvider).addBonus(amount: 2);
          case QuotaType.files:
            await ref.read(fileQuotaServiceProvider).addBonus(amount: 1);
          case QuotaType.voice:
            await ref.read(voiceQuotaServiceProvider).addBonus(amount: 5);
        }
      },
    );
    final notifier = ref.read(chatNotifierProvider(widget.conversationId).notifier);
    if (granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bonus accordé ! Vous pouvez continuer.'),
          duration: Duration(seconds: 2),
        ),
      );
      // Relancer automatiquement la demande bloquee par le quota
      await notifier.retryPendingMessage();
    } else {
      // Dialog ferme sans bonus : annuler le message en attente
      notifier.clearPendingMessage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatNotifierProvider(widget.conversationId));
    final notifier = ref.read(chatNotifierProvider(widget.conversationId).notifier);
    final voiceConv = ref.watch(voiceConversationProvider(widget.conversationId));
    final voiceConvNotifier = ref.read(voiceConversationProvider(widget.conversationId).notifier);

    // Auto-scroll + afficher erreur quota
    ref.listen(chatNotifierProvider(widget.conversationId), (_, next) {
      _scrollToBottom();
      if (next.error == 'quota_exceeded') {
        _showQuotaDialog(QuotaType.requests);
        notifier.clearError();
      } else if (next.error == 'quota_files_exceeded') {
        _showQuotaDialog(QuotaType.files);
        notifier.clearError();
      } else if (next.error == 'quota_search_exceeded') {
        _showQuotaDialog(QuotaType.searches);
        notifier.clearError();
      } else if (next.error == 'quota_voice_exceeded') {
        _showQuotaDialog(QuotaType.voice);
        notifier.clearError();
      } else if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!)),
        );
        notifier.clearError();
      }
    });

    // Écouter le texte sélectionné depuis l'extension Chrome
    ref.listen(extensionSelectedTextProvider, (_, next) {
      final selectedText = next.valueOrNull;
      if (selectedText != null && selectedText.isNotEmpty) {
        _inputBarController.text = selectedText;
        _inputBarController.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputBarController.text.length),
        );
      }
    });

    // Écouter les résultats d'actions navigateur (extension Chrome)
    final isExtension = PlatformService.isExtension;
    if (isExtension) {
      final bridge = ref.read(extensionBridgeProvider);
      _actionResultSub = bridge.onActionResult.listen((result) {
        if (!mounted) return;
        final actionName = result.action.value;
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Action "$actionName" exécutée'),
              duration: const Duration(seconds: 2),
            ),
          );
        } else if (result.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Action "$actionName" échouée : ${result.error}'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    }

    final isVoiceActive = voiceConv.state != VoiceConversationState.idle;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/chats'),
        ),
        title: const Text('Chat', style: TextStyle(fontSize: 18)),
        actions: [
          if (state.remainingRequests != null && !state.isStreaming)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                label: Text('${state.remainingRequests} restants'),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Indicateur recherche web
              if (state.isSearching)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Recherche web en cours...',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              // Indicateur conversation vocale (splash en overlay, banner seul ici)
              if (isVoiceActive)
                _VoiceConversationBannerOnly(onStop: () => voiceConvNotifier.stop()),
              Expanded(
                child: state.displayedMessages.isEmpty
                    ? const _WelcomeHint()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 12),
                        itemCount: state.canLoadMore
                            ? state.displayedMessages.length + 1
                            : state.displayedMessages.length,
                        itemBuilder: (_, i) {
                          if (state.canLoadMore && i == 0) {
                            return _LoadMoreButton(
                              onTap: notifier.loadMoreHistory,
                            );
                          }
                          final msgIdx = state.canLoadMore ? i - 1 : i;
                          final msg = state.displayedMessages[msgIdx];
                          return ChatBubble(
                            message: msg,
                            onEdit: msg.role == Role.user && msg.content.isNotEmpty
                                ? () {
                                    _inputBarController.text = msg.content;
                                    _inputBarController.selection =
                                        TextSelection.fromPosition(
                                      TextPosition(offset: _inputBarController.text.length),
                                    );
                                    _inputBarKey.currentState?.requestFocus();
                                  }
                                : null,
                          );
                        },
                      ),
              ),
              // Bandeau publicitaire (mobile uniquement, pas extension)
              if (!isExtension) const AdBannerWidget(),
              // Toolbar d'actions secondaires (visible, mutualisee)
              // Slash command palette (all platforms)
              if (_slashFilter != null)
                SlashCommandPalette(
                  filter: _slashFilter!,
                  onSelected: (cmd) {
                    final inputBar = _inputBarKey.currentState;
                    if (inputBar != null) {
                      inputBar.setCommandText('/${cmd.name} ');
                    }
                    setState(() => _slashFilter = null);
                  },
                ),
              InputBar(
                key: _inputBarKey,
                isLoading: state.isStreaming,
                attachments: _pendingAttachments,
                onCancelAttachment: () => setState(() => _pendingAttachments = []),
                onSlashTextChanged: (filter) {
                  setState(() => _slashFilter = filter);
                },
                onSend: (text, {imageBase64, imageMimeType, fileName, fileContent, attachments = const []}) {
                  notifier.sendMessage(
                    text,
                    imageBase64: imageBase64,
                    imageMimeType: imageMimeType,
                    fileName: fileName,
                    fileContent: fileContent,
                    attachments: attachments,
                  );
                  setState(() => _pendingAttachments = []);
                },
              ),
              // Barre d'actions secondaires (fichier + vocal) sous la zone de saisie
              _ChatToolbar(
                isStreaming: state.isStreaming,
                isVoiceActive: isVoiceActive,
                onAttachment: () => _showAttachmentSheet(notifier),
                onToggleVoiceConv: () async {
                  if (isVoiceActive) {
                    await voiceConvNotifier.stop();
                  } else {
                    voiceConvNotifier.startConversation();
                  }
                },
              ),
            ],
          ),
          // Splash overlay - cache la conversation quand vocal est actif
          // ignorePointer: true permet de cliquer à travers le splash
          if (isVoiceActive)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: SizedBox.expand(
                  child: AuroraSplash(conversationId: widget.conversationId),
                ),
              ),
            ),
          // Bouton flottant pour ajouter une photo (visible meme en mode vocal)
          if (isVoiceActive)
            Positioned(
              right: 16,
              bottom: 80, // Au-dessus du InputBar
              child: FloatingActionButton(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                onPressed: () => _showAttachmentSheet(notifier),
                child: const Icon(Icons.camera_alt),
                tooltip: 'Prendre une photo',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleImagePick(ChatNotifier notifier, {required bool fromCamera}) async {
    final service = ImageUploadService();
    final results = fromCamera
        ? await service.pickFromCamera()
        : await service.pickFromGallery();
    if (results.isEmpty || !mounted) return;

    // Vérification limite agrégée 5MB
    var currentTotal = _pendingAttachments.fold<int>(0, (sum, a) {
      if (a.imageBase64 != null) return sum + a.imageBase64!.length;
      if (a.fileContent != null) return sum + a.fileContent!.length;
      return sum;
    });

    for (final result in results) {
      final addedSize = result.imageBase64?.length ?? result.extractedText?.length ?? 0;
      if (currentTotal + addedSize > maxAttachmentsTotalBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Taille limite dépassée (5MB par message). Vous pouvez ajouter plusieurs fichiers, mais la taille totale ne doit pas dépasser 5MB.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        break;
      }
      final sizeKB = (result.sizeBytes / 1024).toStringAsFixed(0);
      setState(() {
        _pendingAttachments.add(AttachmentData(
          imageBase64: result.imageBase64,
          imageMimeType: result.mimeType,
          previewLabel: '${result.name} ($sizeKB Ko)',
        ));
      });
      currentTotal += addedSize;
    }
  }

  Future<void> _handleFilePick(ChatNotifier notifier) async {
    final isPro = await notifier.ref.read(isProProvider.future).catchError((_) => false);
    final service = FileUploadService();
    try {
      final results = await service.pickAndExtract();
      if (results.isEmpty || !mounted) return;

      // Vérification limite agrégée 5MB
      var currentTotal = _pendingAttachments.fold<int>(0, (sum, a) {
        if (a.imageBase64 != null) return sum + a.imageBase64!.length;
        if (a.fileContent != null) return sum + a.fileContent!.length;
        return sum;
      });

      for (final result in results) {
        final addedSize = result.sizeBytes;
        if (currentTotal + addedSize > maxAttachmentsTotalBytes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Taille limite dépassée (5MB par message). Vous pouvez ajouter plusieurs fichiers, mais la taille totale ne doit pas dépasser 5MB.'),
                duration: Duration(seconds: 4),
              ),
            );
          }
          break;
        }
        final preview = result.name.length > 40
            ? '${result.name.substring(0, 40)}...'
            : result.name;
        setState(() {
          _pendingAttachments.add(AttachmentData(
            fileName: result.name,
            fileContent: result.extractedText,
            previewLabel: '$preview (${(result.sizeBytes / 1024).toStringAsFixed(0)} Ko)',
          ));
        });
        currentTotal += addedSize;
      }
    } on FileUploadException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } on FileQuotaExceededException {
      if (mounted) {
        _showQuotaDialog(QuotaType.files);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur fichier: $e')),
        );
      }
    }
  }

  Future<void> _showAttachmentSheet(ChatNotifier notifier) async {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt_outlined,
                    color: Theme.of(ctx).colorScheme.primary),
                title: const Text('Caméra'),
                subtitle: const Text('Prendre une photo'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _handleImagePick(notifier, fromCamera: true);
                },
              ),
              ListTile(
                leading: Icon(Icons.image_outlined,
                    color: Theme.of(ctx).colorScheme.primary),
                title: const Text('Galerie'),
                subtitle: const Text('Choisir une photo existante'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _handleImagePick(notifier, fromCamera: false);
                },
              ),
              ListTile(
                leading: Icon(Icons.insert_drive_file_outlined,
                    color: Theme.of(ctx).colorScheme.primary),
                title: const Text('Document'),
                subtitle: const Text('PDF, Word, Excel, CSV, TXT, MD'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _handleFilePick(notifier);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatToolbar extends StatelessWidget {
  const _ChatToolbar({
    required this.isStreaming,
    required this.isVoiceActive,
    required this.onAttachment,
    required this.onToggleVoiceConv,
  });

  final bool isStreaming;
  final bool isVoiceActive;
  final VoidCallback onAttachment;
  final VoidCallback onToggleVoiceConv;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          // Piece jointe
          ActionChip(
            avatar: Icon(
              Icons.attach_file_outlined,
              size: 18,
              color: colorScheme.outline,
            ),
            label: Text(
              'Fichier',
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
            backgroundColor: colorScheme.surfaceContainerHighest,
            side: BorderSide(color: colorScheme.outlineVariant),
            visualDensity: VisualDensity.compact,
            onPressed: onAttachment,
          ),
          const SizedBox(width: 8),
          // Conversation vocale
          ActionChip(
            avatar: Icon(
              isVoiceActive ? Icons.mic : Icons.mic_none_outlined,
              size: 18,
              color: isVoiceActive ? colorScheme.onErrorContainer : colorScheme.outline,
            ),
            label: Text(
              isVoiceActive ? 'Vocal ON' : 'Vocal OFF',
              style: TextStyle(
                fontSize: 12,
                color: isVoiceActive ? colorScheme.onErrorContainer : colorScheme.outline,
              ),
            ),
            backgroundColor:
                isVoiceActive ? colorScheme.errorContainer : colorScheme.surfaceContainerHighest,
            side: BorderSide(
              color: isVoiceActive ? colorScheme.error : colorScheme.outlineVariant,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: onToggleVoiceConv,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _VoiceConversationBanner extends StatelessWidget {
  const _VoiceConversationBanner({
    required this.status,
    required this.onStop,
  });

  final VoiceConversationStatus status;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    String label;
    IconData icon;
    switch (status.state) {
      case VoiceConversationState.listening:
        label = 'Écoute en cours...';
        icon = Icons.mic;
        break;
      case VoiceConversationState.thinking:
        label = 'Réflexion...';
        icon = Icons.psychology;
        break;
      case VoiceConversationState.speaking:
        label = 'Réponse vocale...';
        icon = Icons.record_voice_over;
        break;
      case VoiceConversationState.error:
        label = 'Erreur vocale';
        icon = Icons.error_outline;
        break;
      default:
        label = 'Conversation vocale';
        icon = Icons.mic;
    }

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (status.transcript != null && status.transcript!.isNotEmpty)
            Expanded(
              child: Text(
                '"${status.transcript}"',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.stop),
            color: Theme.of(context).colorScheme.error,
            onPressed: onStop,
            tooltip: 'Arrêter',
            iconSize: 18,
          ),
        ],
      ),
    );
  }
}

/// Banner de contrôle solo (bouton stop) pour le mode vocal
class _VoiceConversationBannerOnly extends StatelessWidget {
  const _VoiceConversationBannerOnly({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.stop, size: 20),
            color: Theme.of(context).colorScheme.error,
            onPressed: onStop,
            tooltip: 'Arrêter le vocal',
            iconSize: 20,
          ),
        ],
      ),
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(Icons.arrow_upward, size: 16, color: colorScheme.primary),
          label: Text(
            'Charger l\'historique',
            style: TextStyle(color: colorScheme.primary),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: colorScheme.primary.withOpacity(0.4)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeHint extends StatelessWidget {
  const _WelcomeHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome,
              size: 56,
              color: Theme.of(context).colorScheme.secondary),
          const SizedBox(height: 16),
          Text(
            'Posez votre première question',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Posez-moi n\'importe quoi',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}
