import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/project.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../monetization/subscription/subscription_service.dart';

// ── Repository ────────────────────────────────────────────────────────────────
final projectsStreamProvider =
    StreamProvider.family<List<Project>, String>(
  (ref, userId) => ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(userId)
      .collection('projects')
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((snap) =>
          snap.docs.map(Project.fromFirestore).toList()),
);

// Provider pour les conversations d'un projet
final projectConversationsProvider =
    StreamProvider.family<List<String>, String>(
  (ref, projectId) => ref
      .watch(firestoreProvider)
      .collection('projects')
      .doc(projectId)
      .collection('conversations')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => d.id).toList()),
);

// ── Screen ────────────────────────────────────────────────────────────────────
class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isPro = ref.watch(isProProvider).valueOrNull ?? false;

    if (user == null) return const SizedBox.shrink();

    // Grille Pro uniquement
    if (!isPro) {
      return Scaffold(
        appBar: AppBar(title: const Text('Projets')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_special_outlined,
                  size: 64, color: Colors.amber),
              const SizedBox(height: 16),
              const Text('Fonctionnalité Pro',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  'Organisez vos conversations en projets',
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.push('/paywall'),
                icon: const Icon(Icons.workspace_premium),
                label: const Text('Passer en Pro'),
              ),
            ],
          ),
        ),
      );
    }

    final asyncProjects = ref.watch(projectsStreamProvider(user.uid));

    return Scaffold(
      appBar: AppBar(title: const Text('Projets')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context, ref, user.uid),
        child: const Icon(Icons.add),
      ),
      body: asyncProjects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (projects) => projects.isEmpty
            ? const _EmptyProjects()
            : ListView.builder(
                itemCount: projects.length,
                itemBuilder: (_, i) => _ProjectTile(
                  project: projects[i],
                  userId: user.uid,
                ),
              ),
      ),
    );
  }

  Future<void> _showCreateDialog(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau projet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                  labelText: 'Description (optionnel)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Créer')),
        ],
      ),
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final name = nameCtrl.text.trim();

      // Vérifier si un projet avec ce nom existe déjà
      final existing = await ref
          .read(firestoreProvider)
          .collection('users')
          .doc(userId)
          .collection('projects')
          .where('name', isEqualTo: name)
          .get();

      if (existing.docs.isNotEmpty && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Un projet avec ce nom existe déjà')),
        );
        nameCtrl.dispose();
        descCtrl.dispose();
        return;
      }

      final project = Project.create(
        userId: userId,
        name: name,
        description: descCtrl.text.trim(),
      );

      nameCtrl.dispose();
      descCtrl.dispose();
      await ref
          .read(firestoreProvider)
          .collection('users')
          .doc(userId)
          .collection('projects')
          .doc(project.id)
          .set(project.toFirestore());
    }

    nameCtrl.dispose();
    descCtrl.dispose();
  }
}

class _ProjectTile extends ConsumerWidget {
  const _ProjectTile({required this.project, required this.userId});
  final Project project;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const CircleAvatar(
        child: Icon(Icons.folder_outlined),
      ),
      title: Text(project.name),
      subtitle: Text(
        '${project.conversationIds.length} conversation(s)',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => _onMenuSelected(v, context, ref),
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'open',
            child: Text('Ouvrir'),
          ),
          const PopupMenuItem(
            value: 'edit',
            child: Text('Modifier'),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Supprimer'),
          ),
        ],
      ),
      onTap: () => _openProject(context, ref),
    );
  }

  void _openProject(BuildContext context, WidgetRef ref) {
    // Navigation vers les conversations du projet
    // Pour l'instant, on affiche un message car la feature n'est pas complète
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Projet "${project.name}" — Feature en développement'),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
      ),
    );
  }

  Future<void> _onMenuSelected(
    String value,
    BuildContext context,
    WidgetRef ref,
  ) async {
    switch (value) {
      case 'open':
        _openProject(context, ref);
        break;
      case 'edit':
        await _editProject(context, ref);
        break;
      case 'delete':
        await _deleteProject(context, ref);
        break;
    }
  }

  Future<void> _editProject(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController(text: project.name);
    final descCtrl = TextEditingController(text: project.description);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier le projet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optionnel)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final updatedProject = project.copyWith(
        name: nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
        updatedAt: DateTime.now(),
      );
      await ref
          .read(firestoreProvider)
          .collection('users')
          .doc(userId)
          .collection('projects')
          .doc(project.id)
          .set(updatedProject.toFirestore());
    }

    nameCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _deleteProject(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le projet ?'),
        content: const Text(
          'Cette action est irréversible. Les conversations associées ne seront pas supprimées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref
          .read(firestoreProvider)
          .collection('users')
          .doc(userId)
          .collection('projects')
          .doc(project.id)
          .delete();
    }
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_outlined, size: 64),
          SizedBox(height: 16),
          Text('Aucun projet'),
          SizedBox(height: 8),
          Text('Appuyez sur + pour créer un projet'),
        ],
      ),
    );
  }
}
