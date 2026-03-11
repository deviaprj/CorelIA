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

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project, required this.userId});
  final Project project;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(
        child: Icon(Icons.folder_outlined),
      ),
      title: Text(project.name),
      subtitle: Text(
        '${project.conversationIds.length} conversation(s)',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
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
