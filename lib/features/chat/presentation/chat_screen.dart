import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'chat_notifier.dart';
import 'chat_bubble.dart';
import 'input_bar.dart';
import '../../../core/platform/platform_service.dart';
import '../../monetization/ads/ad_banner_widget.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
        chatNotifierProvider(widget.conversationId));
    final notifier = ref.read(
        chatNotifierProvider(widget.conversationId).notifier);

    // Auto-scroll + afficher erreur quota
    ref.listen(chatNotifierProvider(widget.conversationId), (_, next) {
      _scrollToBottom();
      if (next.error == 'quota_exceeded') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Quota journalier atteint. Passez en Pro !'),
            action: SnackBarAction(
              label: 'Pro',
              onPressed: () => context.push('/paywall'),
            ),
          ),
        );
        notifier.clearError();
      } else if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!)),
        );
        notifier.clearError();
      }
    });

    final isExtension = PlatformService.isExtension;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/chats'),
        ),
        title: const Text('Chat'),
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
      body: Column(
        children: [
          Expanded(
            child: state.messages.isEmpty
                ? const _WelcomeHint()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 12),
                    itemCount: state.messages.length,
                    itemBuilder: (_, i) =>
                        ChatBubble(message: state.messages[i]),
                  ),
          ),
          // Bandeau publicitaire (mobile uniquement, pas extension)
          if (!isExtension) const AdBannerWidget(),
          InputBar(
            isLoading: state.isStreaming,
            onSend: (text) =>
                notifier.sendMessage(text),
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
