/// Breakpoints pour le layout responsive Corely Desktop.
///
/// Mobile  : < 600px  — chat plein ecran (comportement actuel)
/// Tablet  : 600-900px — chat + drawer optionnel
/// Desktop : > 900px  — sidebar gauche + chat + info panel droit
abstract class ResponsiveBreakpoints {
  static const double mobileMax = 600;
  static const double tabletMax = 900;

  /// Vrai si la largeur correspond au layout mobile.
  static bool isMobile(double width) => width < mobileMax;

  /// Vrai si la largeur correspond au layout tablette.
  static bool isTablet(double width) =>
      width >= mobileMax && width < tabletMax;

  /// Vrai si la largeur correspond au layout desktop.
  static bool isDesktop(double width) => width >= tabletMax;
}
