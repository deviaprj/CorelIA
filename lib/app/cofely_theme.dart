// ═══════════════════════════════════════════════════════════════════════════════
// SYSTÈME DE DESIGN — COFELY × CORELY
// ═══════════════════════════════════════════════════════════════════════════════
//
// ┌─ CHOIX DE DESIGN ─────────────────────────────────────────────────────────┐
// │                                                                             │
// │  PALETTE PRINCIPALE                                                         │
// │    #003F5C  Bleu foncé Cofely    → Primary, headers, CTA fort             │
// │    #58B4D1  Bleu ciel clair      → Accent, bulles utilisateur, icônes     │
// │    #F0F4F8  Gris-bleu très clair → Background du chat, scaffold           │
// │    #FFFFFF  Blanc pur            → Bulles bot, surfaces élevées           │
// │                                                                             │
// │  TYPOGRAPHIE                                                                │
// │    "Inter" (Google Fonts) — sans-serif moderne, polyvalente,              │
// │    excellente lisibilité à toutes les tailles d'écran.                     │
// │    Hiérarchie : headlineMedium 20sp / bodyLarge 16sp / labelSmall 11sp    │
// │                                                                             │
// │  BULLES DE CHAT                                                             │
// │    Radius 12 px uniforme + queue asymétrique 4 px (côté intérieur bas)    │
// │    Ombre : box-shadow 0 2px 8px rgba(0,0,0,0.10) — profondeur légère      │
// │    Bot   : fond blanc, texte #003F5C — contrast 14.7:1 (AAA)              │
// │    User  : fond #58B4D1, texte #003F5C — contrast ~4.4:1 (AA ✓)          │
// │                                                                             │
// │  AVATAR BOT                                                                 │
// │    Cercle 36 px, dégradé diagonal #003F5C → #58B4D1                       │
// │    Lettre "C" blanche, fontWeight Bold — identité Cofely immédiate        │
// │    Présent devant chaque bulle bot, absent des bulles utilisateur         │
// │                                                                             │
// │  BOUTON D'ENVOI                                                             │
// │    FilledButton circulaire fond #003F5C, icône flèche blanche              │
// │    AnimatedScale au press : 0.85 → 1.0 — feedback tactile immédiat        │
// │    Surface tactile ≥ 48 dp (cible Android/WCAG 2.5.5)                     │
// │                                                                             │
// │  TOOLBAR & CHIPS                                                            │
// │    Chips "Fichier" / "Vocal ON|OFF" avec fond #E8EEF4, bordure #CDD8E0   │
// │    Chip vocal actif : fond #CCE8F4, bordure #003F5C                        │
// │                                                                             │
// │  HEADER CHAT                                                                │
// │    Barre fixe : fond blanc, ombre bas fine 0 1px 4px rgba(0,0,0,0.08)    │
// │    Logo "C" dégradé 28 px | "Assistant Cofely" gras | dot vert "En ligne" │
// │                                                                             │
// │  RESPONSIVE                                                                 │
// │    Mobile  : plein écran (sans contrainte)                                 │
// │    Desktop/Web : centré, maxWidth 400 px                                   │
// │                                                                             │
// │  ACCESSIBILITÉ                                                              │
// │    Tooltips sur tous les boutons d'action                                  │
// │    Semantics labels pour lecteurs d'écran                                  │
// │    Contraste WCAG AA respecté sur toutes les surfaces                      │
// │                                                                             │
// ├─ VARIANTE CHALEUREUSE ──────────────────────────────────────────────────────┤
// │  Ambiance verte naturelle, conviviale, énergies renouvelables              │
// │                                                                             │
// │  // static const Color primary = Color(0xFF2D6A4F); // Vert forêt         │
// │  // static const Color accent  = Color(0xFF74C69D); // Menthe fraîche     │
// │  // static const Color chatBg  = Color(0xFFF0F7F4); // Fond vert très pâle│
// │  // static const Color onAccent = Color(0xFF1A3D2B); // Foncé sur menthe  │
// │                                                                             │
// ├─ VARIANTE INSTITUTIONNELLE ─────────────────────────────────────────────────┤
// │  Autorité, sobriété, marque corporate rigoureuse                           │
// │                                                                             │
// │  // static const Color primary = Color(0xFF1B3B6F); // Marine profond     │
// │  // static const Color accent  = Color(0xFF4A90D9); // Bleu ciel officiel │
// │  // static const Color chatBg  = Color(0xFFF0F4FA); // Fond bleu pâle     │
// │  // static const Color onAccent = Color(0xFF0F2444); // Foncé sur bleu ciel│
// │                                                                             │
// └─────────────────────────────────────────────────────────────────────────────┘

import 'package:flutter/material.dart';

/// Tokens de design Cofely — source unique de vérité pour toute l'UI Corely.
abstract class CofelyTokens {
  // ── Palette principale ────────────────────────────────────────────────────
  static const Color primary   = Color(0xFF003F5C); // Bleu foncé Cofely
  static const Color accent    = Color(0xFF58B4D1); // Bleu ciel clair Cofely
  static const Color chatBg    = Color(0xFFF0F4F8); // Fond interface chat
  static const Color botBubble = Color(0xFFFFFFFF); // Fond bulle bot
  static const Color userBubble = accent;           // Fond bulle user

  // ── Couleurs de texte ──────────────────────────────────────────────────────
  static const Color onPrimary  = Color(0xFFFFFFFF); // Blanc pur sur primary
  static const Color onAccent   = Color(0xFF003F5C); // Primary sur accent (WCAG ~4.4:1)
  static const Color onSurface  = Color(0xFF1A2E3B); // Texte principal (sombre)

  // ── Status / sémantique ───────────────────────────────────────────────────
  static const Color onlineGreen  = Color(0xFF22C55E); // Point "En ligne"
  static const Color errorRed     = Color(0xFFB00020);
  static const Color warningAmber = Color(0xFFF59E0B);

  // ── Dégradé avatar bot ────────────────────────────────────────────────────
  static const LinearGradient avatarGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Ombres ────────────────────────────────────────────────────────────────
  /// box-shadow: 0 2px 8px rgba(0,0,0,0.10)
  static const List<BoxShadow> bubbleShadow = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// Ombre fine AppBar : 0 1px 4px rgba(0,0,0,0.08)
  static const List<BoxShadow> headerShadow = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  // ── Dimensions ────────────────────────────────────────────────────────────
  static const double bubbleRadius = 12.0;  // Coins arrondis bulle
  static const double tailRadius   =  4.0;  // Queue intérieure bulle
  static const double inputRadius  = 24.0;  // Champ de saisie
  static const double chipRadius   = 20.0;  // ActionChip toolbar
  static const double avatarSize   = 36.0;  // Diamètre avatar bot
  static const double avatarFontSz = 16.0;  // Taille lettre "C"
  static const double sendBtnPad   = 14.0;  // Padding bouton envoi
  static const double maxChatWidth = 400.0; // Max-width desktop

  // ── Durées d'animation ────────────────────────────────────────────────────
  static const Duration scaleAnim = Duration(milliseconds: 150);
  static const Duration dotAnim   = Duration(milliseconds: 500);
  static const Duration dotStagger = Duration(milliseconds: 150);

  // ═══════════════════════════════════════════════════════════════════════════
  // THÈME CLAIR COFELY
  // ═══════════════════════════════════════════════════════════════════════════
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: primary,
          onPrimary: onPrimary,
          primaryContainer: Color(0xFFCCE8F4),
          onPrimaryContainer: primary,
          secondary: accent,
          onSecondary: onAccent,
          secondaryContainer: Color(0xFFDEF0F8),
          onSecondaryContainer: primary,
          tertiary: Color(0xFF0077A8),
          onTertiary: onPrimary,
          tertiaryContainer: Color(0xFFB8E2F2),
          onTertiaryContainer: Color(0xFF004B6A),
          error: errorRed,
          onError: onPrimary,
          errorContainer: Color(0xFFFFDAD6),
          onErrorContainer: Color(0xFF410002),
          surface: botBubble,
          onSurface: onSurface,
          surfaceContainerHighest: Color(0xFFE8EEF4),
          onSurfaceVariant: Color(0xFF4A6375),
          outline: Color(0xFF8DAABB),
          outlineVariant: Color(0xFFCDD8E0),
          scrim: Color(0xFF000000),
          inverseSurface: Color(0xFF1A2E3B),
          onInverseSurface: Color(0xFFECF2F7),
          inversePrimary: accent,
          surfaceTint: primary,
        ),
        scaffoldBackgroundColor: chatBg,

        // ── AppBar ──────────────────────────────────────────────────────────
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
          backgroundColor: botBubble,
          foregroundColor: primary,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: primary,
          ),
          iconTheme: IconThemeData(color: primary),
        ),

        // ── TextField ────────────────────────────────────────────────────────
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFE8EEF4),
          hintStyle: const TextStyle(color: Color(0xFF8DAABB)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(inputRadius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(inputRadius),
            borderSide: const BorderSide(color: accent, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),

        // ── FilledButton (bouton envoi) ───────────────────────────────────────
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: onPrimary,
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(sendBtnPad),
            elevation: 2,
            shadowColor: primary.withAlpha(80),
          ),
        ),

        // ── ElevatedButton ────────────────────────────────────────────────────
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: onPrimary,
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(bubbleRadius),
            ),
          ),
        ),

        // ── OutlinedButton ────────────────────────────────────────────────────
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: const BorderSide(color: primary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(bubbleRadius),
            ),
          ),
        ),

        // ── TextButton ────────────────────────────────────────────────────────
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: primary),
        ),

        // ── Chip / ActionChip (toolbar) ───────────────────────────────────────
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFE8EEF4),
          labelStyle:
              const TextStyle(color: Color(0xFF4A6375), fontSize: 12),
          side: const BorderSide(color: Color(0xFFCDD8E0)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(chipRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          selectedColor: const Color(0xFFCCE8F4),
          checkmarkColor: primary,
        ),

        // ── Switch ────────────────────────────────────────────────────────────
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? onPrimary : null),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? primary : null),
        ),

        // ── ListTile ──────────────────────────────────────────────────────────
        listTileTheme: const ListTileThemeData(
          iconColor: primary,
          leadingAndTrailingTextStyle: TextStyle(color: Color(0xFF4A6375)),
        ),

        // ── Divider ───────────────────────────────────────────────────────────
        dividerTheme: const DividerThemeData(
          color: Color(0xFFCDD8E0),
          thickness: 1,
        ),

        // ── BottomSheet ────────────────────────────────────────────────────────
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: botBubble,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),

        // ── Dialog ────────────────────────────────────────────────────────────
        dialogTheme: DialogThemeData(
          backgroundColor: botBubble,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titleTextStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
        ),

        // ── SnackBar ──────────────────────────────────────────────────────────
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1A2E3B),
          contentTextStyle:
              const TextStyle(color: Colors.white, fontFamily: 'Inter'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          behavior: SnackBarBehavior.floating,
        ),

        // ── ProgressIndicator ─────────────────────────────────────────────────
        progressIndicatorTheme:
            const ProgressIndicatorThemeData(color: primary),
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // THÈME SOMBRE COFELY
  // ═══════════════════════════════════════════════════════════════════════════
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: accent,                  // bleu clair en mode sombre
          onPrimary: primary,
          primaryContainer: Color(0xFF004B6A),
          onPrimaryContainer: Color(0xFFCCE8F4),
          secondary: Color(0xFF7ECDE8),
          onSecondary: Color(0xFF002F45),
          secondaryContainer: Color(0xFF1A3F54),
          onSecondaryContainer: Color(0xFFDEF0F8),
          tertiary: Color(0xFF58B4D1),
          onTertiary: Color(0xFF003044),
          tertiaryContainer: Color(0xFF004B6A),
          onTertiaryContainer: Color(0xFFB8E2F2),
          error: Color(0xFFCF6679),
          onError: Color(0xFF000000),
          errorContainer: Color(0xFF8C0009),
          onErrorContainer: Color(0xFFFFDAD6),
          surface: Color(0xFF0D1E28),
          onSurface: Color(0xFFDCECF5),
          surfaceContainerHighest: Color(0xFF1A2E3B),
          onSurfaceVariant: Color(0xFF8DAABB),
          outline: Color(0xFF4A6375),
          outlineVariant: Color(0xFF2A3D4A),
          scrim: Color(0xFF000000),
          inverseSurface: Color(0xFFDCECF5),
          onInverseSurface: Color(0xFF0D1E28),
          inversePrimary: primary,
          surfaceTint: accent,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A1820),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Color(0xFF0D1E28),
          foregroundColor: Color(0xFFDCECF5),
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFFDCECF5),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A2E3B),
          hintStyle: const TextStyle(color: Color(0xFF4A6375)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(inputRadius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(inputRadius),
            borderSide: const BorderSide(color: accent, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: primary,
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(sendBtnPad),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF1A2E3B),
          labelStyle: const TextStyle(color: Color(0xFF8DAABB), fontSize: 12),
          side: const BorderSide(color: Color(0xFF2A3D4A)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(chipRadius),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF2A3D4A),
          thickness: 1,
        ),
      );
}
