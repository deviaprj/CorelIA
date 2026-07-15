import 'package:flutter/material.dart';
import '../../app/corely_theme.dart';

/// Panneau d'information contextuel (droite) pour le layout desktop.
///
/// Affiche selon le contexte : sources web, status agent, aide, etc.
class DesktopInfoPanel extends StatelessWidget {
  final String title;
  final List<Widget>? children;
  final Widget? emptyWidget;

  const DesktopInfoPanel({
    super.key,
    required this.title,
    this.children,
    this.emptyWidget,
  });

  @override
  Widget build(BuildContext context) {
    final hasContent = children != null && children!.isNotEmpty;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: CorelyTokens.primary,
                  ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          if (hasContent)
            ...children!
          else if (emptyWidget != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: emptyWidget,
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'Selectionnez une conversation\nou lancez une recherche',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.4),
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
