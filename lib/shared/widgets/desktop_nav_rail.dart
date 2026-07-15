import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/corely_theme.dart';

/// Barre de navigation laterale persistante pour le layout desktop.
///
/// Affiche : logo Corely, navigation (Chats, Projets, Agent, Parametres),
/// et le toggle Agent mode.
class DesktopNavRail extends ConsumerWidget {
  final String currentRoute;
  final VoidCallback? onToggleAgent;
  final bool agentMode;

  const DesktopNavRail({
    super.key,
    required this.currentRoute,
    this.onToggleAgent,
    this.agentMode = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          // Logo + marque
          const SizedBox(height: 24),
          _BrandHeader(),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Navigation principale
          _NavItem(
            icon: Icons.chat_bubble_outline_rounded,
            selectedIcon: Icons.chat_bubble_rounded,
            label: 'Chats',
            selected: currentRoute.startsWith('/chat') ||
                currentRoute == '/chats',
            onTap: () => context.go('/chats'),
          ),
          _NavItem(
            icon: Icons.folder_outlined,
            selectedIcon: Icons.folder_rounded,
            label: 'Projets',
            selected: currentRoute.startsWith('/projects'),
            onTap: () => context.go('/projects'),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Mode Agent
          if (onToggleAgent != null)
            _AgentToggle(
              agentMode: agentMode,
              onToggle: onToggleAgent,
            ),

          _NavItem(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_rounded,
            label: 'Parametres',
            selected: currentRoute == '/settings',
            onTap: () => context.go('/settings'),
          ),

          const Spacer(),

          // Footer : version
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Corely v1.1.0',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.4),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Logo "C" cercle
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: CorelyTokens.avatarGradient,
            ),
            alignment: Alignment.center,
            child: const Text(
              'C',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Corely',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? CorelyTokens.primary
        : Theme.of(context).colorScheme.onSurface.withOpacity(0.6);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? CorelyTokens.primary.withOpacity(0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(selected ? selectedIcon : icon, size: 22, color: color),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentToggle extends StatelessWidget {
  final bool agentMode;
  final VoidCallback onToggle;

  const _AgentToggle({required this.agentMode, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: agentMode
            ? CorelyTokens.accent.withOpacity(0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  agentMode ? Icons.smart_toy_rounded : Icons.smart_toy_outlined,
                  size: 22,
                  color: agentMode
                      ? CorelyTokens.accent
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Agent',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: agentMode
                              ? CorelyTokens.primary
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6),
                        ),
                      ),
                      Text(
                        agentMode ? 'Autonome ON' : 'Autonome OFF',
                        style: TextStyle(
                          fontSize: 11,
                          color: agentMode
                              ? CorelyTokens.accent
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: agentMode,
                  onChanged: (_) => onToggle(),
                  activeColor: CorelyTokens.accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
