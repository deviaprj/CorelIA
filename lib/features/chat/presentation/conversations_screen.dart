import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../domain/conversation.dart';
import 'chat_notifier.dart';
import '../data/firestore_chat_repository.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../shared/widgets/loading_widget.dart';

class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  bool _hasAutoNavigated = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final asyncConversations =
        ref.watch(conversationsStreamProvider(user.uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('AironBot'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
            tooltip: 'Paramètres',
          ),
        ],
      ),
      body: asyncConversations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: ErrorDisplayWidget(
            message: 'Erreur: $e',
            onRetry: () => ref.invalidate(conversationsStreamProvider(user.uid)),
          ),
        ),
        data: (conversations) {
          if (conversations.isEmpty) {
            if (!_hasAutoNavigated) {
              _hasAutoNavigated = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _createNewConversation(context, ref, user.uid);
              });
            }
            return const Center(child: CircularProgressIndicator());
          }
          return _ConversationList(
            conversations: conversations,
            userId: user.uid,
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createNewConversation(context, ref, user.uid),
        tooltip: 'Nouvelle conversation',
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _createNewConversation(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) async {
    final repo = ref.read(chatRepositoryProvider);
    final conv = await repo.createConversation(userId: userId);
    if (context.mounted) {
      context.push('/chat/${conv.id}');
    }
  }
}

class _ConversationList extends ConsumerWidget {
  const _ConversationList({
    required this.conversations,
    required this.userId,
  });

  final List<Conversation> conversations;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = conversations.where((c) => c.isPinned).toList();
    final unpinned = conversations.where((c) => !c.isPinned).toList();

    return ListView(
      children: [
        if (pinned.isNotEmpty) ...[
          _SectionHeader(title: 'Épinglées'),
          for (final conv in pinned)
            _ConversationTile(conv: conv, userId: userId),
        ],
        if (unpinned.isNotEmpty) ...[
          _SectionHeader(title: 'Récentes'),
          for (final conv in unpinned)
            _ConversationTile(conv: conv, userId: userId),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conv, required this.userId});
  final Conversation conv;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr = DateFormat('dd/MM HH:mm').format(conv.updatedAt);

    return Dismissible(
      key: Key(conv.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async => _confirmDelete(context),
      onDismissed: (_) {
        ref.read(chatRepositoryProvider).deleteConversation(conv.id);
      },
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            conv.isPinned ? Icons.push_pin : Icons.chat_bubble_outline,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          conv.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${conv.messageCount} message${conv.messageCount > 1 ? 's' : ''} · $dateStr',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => _onMenuSelected(v, context, ref),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'pin',
              child: Text(conv.isPinned ? 'Désépingler' : 'Épingler'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Supprimer'),
            ),
          ],
        ),
        onTap: () => context.push('/chat/${conv.id}'),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Supprimer ?'),
            content: const Text(
                'Cette conversation sera supprimée définitivement.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _onMenuSelected(
    String value,
    BuildContext context,
    WidgetRef ref,
  ) async {
    final repo = ref.read(chatRepositoryProvider);
    switch (value) {
      case 'pin':
        await repo.updateConversation(
            conv.id, {'isPinned': !conv.isPinned});
      case 'delete':
        if (await _confirmDelete(context) && context.mounted) {
          await repo.deleteConversation(conv.id);
        }
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNewChat});
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.smart_toy_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('Pas encore de conversations',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Commencez une nouvelle conversation',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onNewChat,
            icon: const Icon(Icons.add),
            label: const Text('Nouvelle conversation'),
          ),
        ],
      ),
    );
  }
}
