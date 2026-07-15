import 'package:flutter/material.dart';
import 'responsive_breakpoints.dart';

/// Layout responsive pour Corely Desktop.
///
/// S'adapte automatiquement a la largeur de l'ecran :
/// - Mobile  (< 600px) : body uniquement (plein ecran)
/// - Tablet  (600-900px) : body + drawer optionnel
/// - Desktop (> 900px) : sidebar gauche + body + info panel droit
class ResponsiveLayout extends StatelessWidget {
  final Widget body;
  final Widget? sidebar;
  final Widget? infoPanel;
  final bool showInfoPanel;

  const ResponsiveLayout({
    super.key,
    required this.body,
    this.sidebar,
    this.infoPanel,
    this.showInfoPanel = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // Mobile : body plein ecran
        if (ResponsiveBreakpoints.isMobile(width)) {
          return body;
        }

        // Tablet : body + sidebar en drawer
        if (ResponsiveBreakpoints.isTablet(width)) {
          if (sidebar == null) return body;
          return Row(
            children: [
              SizedBox(
                width: 250,
                child: sidebar,
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          );
        }

        // Desktop : sidebar + body + info panel
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sidebar != null) ...[
              SizedBox(
                width: 280,
                child: sidebar,
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(child: body),
            if (showInfoPanel && infoPanel != null) ...[
              const VerticalDivider(width: 1),
              SizedBox(
                width: 320,
                child: infoPanel,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Variante simplifiee : body centre avec largeur max, sans sidebars.
///
/// Utile pour les ecrans non-chat (settings, onboarding, login).
class CenteredLayout extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const CenteredLayout({
    super.key,
    required this.child,
    this.maxWidth = 600,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
