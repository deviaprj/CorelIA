import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'chat_notifier.dart';
import 'chat_bubble.dart';
import 'input_bar.dart';
import 'voice_conversation_service.dart';
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
    final state = ref.watch(chatNotifierProvider(widget.conversationId));
    final notifier = ref.read(chatNotifierProvider(widget.conversationId).notifier);
    final voiceConv = ref.watch(voiceConversationProvider);
    final voiceConvNotifier = ref.read(voiceConversationProvider.notifier);

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
          // Toggle recherche web
          IconButton(
            icon: Icon(
              state.useSearch ? Icons.travel_explore : Icons.travel_explore_outlined,
              color: state.useSearch
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: state.useSearch ? 'Recherche web activée' : 'Recherche web désactivée',
            onPressed: state.isStreaming
                ? null
                : () => notifier.toggleSearch(),
          ),
          // Mode conversation vocale
          IconButton(
            icon: Icon(
              isVoiceActive ? Icons.mic : Icons.mic_none_outlined,
              color: isVoiceActive
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
            tooltip: isVoiceActive ? 'Arrêter la conversation vocale' : 'Conversation vocale',
            onPressed: () {
              if (isVoiceActive) {
                voiceConvNotifier.stop();
              } else {
                voiceConvNotifier.startConversation();
              }
            },
          ),
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
          // Indicateur conversation vocale
          if (isVoiceActive)
            _VoiceConversationBanner(
              status: voiceConv,
              onStop: () => voiceConvNotifier.stop(),
            ),
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
            onSend: (text) => notifier.sendMessage(text),
          ),
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
