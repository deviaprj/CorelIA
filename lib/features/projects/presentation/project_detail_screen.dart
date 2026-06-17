import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/project.dart';
import '../../chat/domain/conversation.dart';

/// Clé composite (userId, projectId) pour les providers `family`.
/// Value type immutable — requis pour l'indexation par Riverpod.
@immutable
class ProjectKey {
  final String userId;
  final String projectId;
  const ProjectKey(this.userId, this.projectId);

  @override
  bool operator ==(Object other) =>
      other is ProjectKey &&
      other.userId == userId &&
      other.projectId == projectId;

  @override
  int get hashCode => Object.hash(userId, projectId);
}

/// Stream d'un projet : `users/{uid}/projects/{projectId}`.
/// Émet `null` si le document n'existe pas (projet supprimé).
final projectDocProvider =
    StreamProvider.family<Project?, ProjectKey>(
  (ref, key) => ref
      .watch(firestoreProvider)
      .collection(AppConstants.colUsers)
      .doc(key.userId)
      .collection(AppConstants.colProjects)
      .doc(key.projectId)
      .snapshots()
      .map((doc) => doc.exists ? Project.fromFirestore(doc) : null),
);

/// Conversations liées à un projet.
///
/// Source de vérité : le champ `projectId` sur les documents `conversations`
/// (top-level). On filtre par `userId` pour isoler les données de l'utilisateur
/// courant. NOTE : `Project.conversationIds` est un mécanisme redondant — on
/// s'appuie ici sur la requête Firestore, plus robuste face aux désynchronisations.
final projectConversationsStreamProvider =
    StreamProvider.family<List<Conversation>, ProjectKey>(
  (ref, key) => ref
      .watch(firestoreProvider)
      .collection(AppConstants.colConversations)
      .where('userId', isEqualTo: key.userId)
      .where('projectId', isEqualTo: key.projectId)
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Conversation.fromFirestore).toList()),
);

/// Écran de détail d'un projet : header (nom + description) + liste des
/// conversations associées.
class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({super.key, required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Utilisateur non connecté')));
    }

    final key = ProjectKey(user.uid, projectId);
    final projectAsync = ref.watch(projectDocProvider(key));
    final convosAsync = ref.watch(projectConversationsStreamProvider(key));

    return Scaffold(
      appBar: AppBar(
        title: projectAsync.when(
          data: (p) => Text(p?.name ?? 'Projet'),
          loading: () => const Text('Projet'),
          error: (_, __) => const Text('Projet'),
        ),
      ),
      body: projectAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (project) {
          if (project == null) {
            return const Center(child: Text('Projet introuvable ou supprimé.'));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (project.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    project.description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              Expanded(child: _buildConversations(context, convosAsync)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConversations(
    BuildContext context,
    AsyncValue<List<Conversation>> async,
  ) {
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
      data: (convos) {
        if (convos.isEmpty) return const _EmptyProjectConversations();
        return ListView.builder(
          itemCount: convos.length,
          itemBuilder: (_, i) {
            final c = convos[i];
            return ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(c.title),
              subtitle: Text('${c.messageCount} message(s)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/chat/${c.id}'),
            );
          },
        );
      },
    );
  }
}

class _EmptyProjectConversations extends StatelessWidget {
  const _EmptyProjectConversations();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.forum_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Aucune conversation dans ce projet'),
            const SizedBox(height: 8),
            Text(
              'Démarrez une conversation puis associez-la à ce projet '
              'via le menu de la conversation.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}