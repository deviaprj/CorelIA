import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/attachment.dart';
import '../../../core/providers/app_providers.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../subscription/data/role_providers.dart';
import '../../subscription/domain/quota_policy.dart';
import '../../subscription/presentation/quota_exceeded_dialog.dart';
import '../data/file_upload_service.dart';
import '../data/image_upload_service.dart';
import 'chat_bubble.dart';
import 'chat_notifier.dart';
import 'input_bar.dart';

/// Écran de chat unique et épuré : liste de messages + champ de saisie.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();
  final _inputBarKey = GlobalKey<InputBarState>();
  final List<Attachment> _pendingAttachments = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatNotifierProvider.notifier).start();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addAttachments(List<Attachment> attachments) async {
    if (attachments.isEmpty) return;
    final currentTotal =
        _pendingAttachments.fold<int>(0, (sum, a) => sum + a.sizeBytes);
    final added = attachments.fold<int>(0, (sum, a) => sum + a.sizeBytes);
    if (currentTotal + added > AppConfig.maxAttachmentBytes) {
      _showError(
        'Taille limite dépassée '
        '(${AppConfig.maxAttachmentBytes ~/ (1024 * 1024)} Mo par message).',
      );
      return;
    }
    setState(() => _pendingAttachments.addAll(attachments));
  }

  Future<void> _pickImage({required bool fromCamera}) async {
    try {
      final service = ImageUploadService();
      final results = fromCamera
          ? await service.pickFromCamera()
          : await service.pickFromGallery();
      await _addAttachments(results);
    } on ImageUploadException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Impossible de charger l\'image : $e');
    }
  }

  Future<void> _pickDocument() async {
    try {
      await _addAttachments(await FileUploadService().pickAndExtract());
    } on FileUploadException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Impossible de lire le fichier : $e');
    }
  }

  Future<void> _showAttachmentSheet() {
    return showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Caméra'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(fromCamera: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Galerie'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(fromCamera: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('Document'),
              subtitle: const Text('PDF, Word, Excel, CSV, TXT, MD'),
              onTap: () {
                Navigator.pop(ctx);
                _pickDocument();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatNotifierProvider);
    final notifier = ref.read(chatNotifierProvider.notifier);
    final themeMode = ref.watch(themeModeProvider);
    final role = ref.watch(userRoleProvider);
    final policy = QuotaPolicies.forRole(role);

    ref.listen(chatNotifierProvider, (_, next) {
      _scrollToBottom();
      final error = next.error;
      if (error == kQuotaExceededError) {
        showQuotaExceededDialog(
          context,
          role: role,
          dailyLimit: policy.dailyRequests ?? 0,
          onUpgrade: () => context.push('/subscription'),
        );
        notifier.clearError();
      } else if (error != null) {
        _showError(error);
        notifier.clearError();
      }
    });

    final messages = state.messages;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.avatarGradient,
              ),
              alignment: Alignment.center,
              child: const Text(
                'C',
                style: TextStyle(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Assistant CorelIA',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: const BoxDecoration(
                          color: AppColors.onlineGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Text(
                        'En ligne',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.onlineGreen,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (policy.limited && state.remainingRequests != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Tooltip(
                message: 'Requêtes restantes aujourd\'hui',
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '${state.remainingRequests}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: state.useSearch
                ? 'Recherche Internet activée'
                : 'Recherche Internet désactivée',
            onPressed: notifier.toggleSearch,
            icon: Icon(
              state.useSearch ? Icons.public : Icons.public_off,
              color: state.useSearch ? AppColors.primary : null,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'subscription':
                  context.push('/subscription');
                case 'theme':
                  await ref.read(themeModeProvider.notifier).setTheme(
                        themeMode == ThemeMode.dark
                            ? ThemeMode.light
                            : ThemeMode.dark,
                      );
                case 'logout':
                  await ref.read(authNotifierProvider.notifier).signOut();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'subscription',
                child: Text(
                  role.isFull ? 'Mon abonnement' : 'Passer à l\'Agent IA Full',
                ),
              ),
              PopupMenuItem(
                value: 'theme',
                child: Text(
                  themeMode == ThemeMode.dark
                      ? 'Thème clair'
                      : 'Thème sombre',
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Text('Se déconnecter'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.isSearching)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.primaryContainer,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Recherche Internet en cours...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: messages.isEmpty
                ? const _WelcomeHint()
                : ListView.builder(
                    controller: _scrollController,
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final msg = messages[i];
                      return ChatBubble(
                        message: msg,
                        onEdit: msg.isUser && msg.content.isNotEmpty
                            ? () => _inputBarKey.currentState?.setText(msg.content)
                            : null,
                      );
                    },
                  ),
          ),
          InputBar(
            key: _inputBarKey,
            isLoading: state.isStreaming,
            pendingAttachments: _pendingAttachments,
            onRemoveAttachment: () =>
                setState(() => _pendingAttachments.clear()),
            searchEnabled: state.useSearch,
            onToggleSearch: notifier.toggleSearch,
            onAttach: _showAttachmentSheet,
            onSend: (text) {
              final attachments = List<Attachment>.from(_pendingAttachments);
              notifier.sendMessage(text, attachments: attachments);
              setState(() => _pendingAttachments.clear());
            },
          ),
        ],
      ),
    );
  }
}

class _WelcomeHint extends StatelessWidget {
  const _WelcomeHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.avatarGradient,
                boxShadow: AppColors.bubbleShadow,
              ),
              alignment: Alignment.center,
              child: const Text(
                'C',
                style: TextStyle(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Assistant CorelIA',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Posez votre première question',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.primary.withOpacity(0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
