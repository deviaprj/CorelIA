import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'chat_notifier.dart';
import 'chat_bubble.dart';
import 'input_bar.dart';
import 'voice_conversation_service.dart';
import 'aurora_splash.dart';
import '../data/image_upload_service.dart';
import '../data/file_upload_service.dart';
import '../data/file_quota_service.dart';
import '../data/search_quota_service.dart';
import '../data/voice_quota_service.dart';
import '../../../core/platform/platform_service.dart';
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
  AttachmentData? _pendingAttachment;

  @override
  void dispose() {
    _scrollController.dispose();
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
    if (granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bonus accordé ! Vous pouvez continuer.'),
          duration: Duration(seconds: 2),
        ),
      );
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

    final isExtension = PlatformService.isExtension;
    final isVoiceActive = voiceConv.state != VoiceConversationState.idle;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/chats'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chat', style: TextStyle(fontSize: 18)),
            if (state.useSearch)
              Text(
                state.isSearching ? 'Recherche web en cours...' : 'Recherche web active',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
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
                          return ChatBubble(
                            message: state.displayedMessages[msgIdx],
                          );
                        },
                      ),
              ),
              // Bandeau publicitaire (mobile uniquement, pas extension)
              if (!isExtension) const AdBannerWidget(),
              // Toolbar d'actions secondaires (visible, mutualisee)
              _ChatToolbar(
                useSearch: state.useSearch,
                isStreaming: state.isStreaming,
                isVoiceActive: isVoiceActive,
                onToggleSearch: notifier.toggleSearch,
                onAttachment: () => _showAttachmentSheet(notifier),
                onToggleVoiceConv: () async {
                  if (isVoiceActive) {
                    await voiceConvNotifier.stop();
                  } else {
                    voiceConvNotifier.startConversation();
                  }
                },
              ),
              InputBar(
                isLoading: state.isStreaming,
                attachment: _pendingAttachment,
                onCancelAttachment: () => setState(() => _pendingAttachment = null),
                onSend: (text, {imageBase64, imageMimeType, fileName, fileContent}) {
                  notifier.sendMessage(
                    text,
                    imageBase64: imageBase64,
                    imageMimeType: imageMimeType,
                    fileName: fileName,
                    fileContent: fileContent,
                  );
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
    final result = fromCamera
        ? await service.pickFromCamera()
        : await service.pickFromGallery();
    if (result == null || !mounted) return;

    final sizeKB = (result.sizeBytes / 1024).toStringAsFixed(0);
    setState(() {
      _pendingAttachment = AttachmentData(
        imageBase64: result.base64,
        imageMimeType: result.mimeType,
        previewLabel: 'Image ($sizeKB Ko) — tapez votre question',
      );
    });
  }

  Future<void> _handleFilePick(ChatNotifier notifier) async {
    final isPro = await notifier.ref.read(isProProvider.future).catchError((_) => false);
    final service = FileUploadService();
    try {
      final result = await service.pickAndExtract(isPro: isPro);
      if (result == null || !mounted) return;

      final preview = result.fileName.length > 40
          ? '${result.fileName.substring(0, 40)}...'
          : result.fileName;
      setState(() {
        _pendingAttachment = AttachmentData(
          fileName: result.fileName,
          fileContent: result.extractedText,
          previewLabel: '$preview — tapez votre question',
        );
      });
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
    required this.useSearch,
    required this.isStreaming,
    required this.isVoiceActive,
    required this.onToggleSearch,
    required this.onAttachment,
    required this.onToggleVoiceConv,
  });

  final bool useSearch;
  final bool isStreaming;
  final bool isVoiceActive;
  final VoidCallback onToggleSearch;
  final VoidCallback onAttachment;
  final VoidCallback onToggleVoiceConv;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Row(
        children: [
          // Toggle recherche web — texte + icone visible
          ActionChip(
            avatar: Icon(
              useSearch ? Icons.travel_explore : Icons.travel_explore_outlined,
              size: 18,
              color: useSearch ? colorScheme.onPrimaryContainer : colorScheme.outline,
            ),
            label: Text(
              useSearch ? 'Web ON' : 'Web OFF',
              style: TextStyle(
                fontSize: 12,
                color: useSearch ? colorScheme.onPrimaryContainer : colorScheme.outline,
              ),
            ),
            backgroundColor:
                useSearch ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
            side: BorderSide(
              color: useSearch ? colorScheme.primary : colorScheme.outlineVariant,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: onToggleSearch,
          ),
          const SizedBox(width: 8),
          // Piece jointe (image + fichier)
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
      case VoiceConversationState.processingStt:
        label = 'Transcription...';
        icon = Icons.transcribe;
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
            'Propulsé par DeepSeek-V3',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}
