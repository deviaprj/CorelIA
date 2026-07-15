// ═══════════════════════════════════════════════════════════════════════════════
// SYSTÈME DE DESIGN — CORELY (MAPBOX INSPIRED)
// ═══════════════════════════════════════════════════════════════════════════════
//
// CHANGELOG v2.1 (2026-07-15) — Mapbox-inspired refresh
//   • Couleurs: remplacement palette achromatique RTTB par hiérarchie Mapbox.
//     ink: #1A1A1A → #0D1E28 (deep navy), accent: #1A56DB → #007AFC (Mapbox blue),
//     bg: #F5F5F5 → #F0F4F8 (cool blue-gray), line: #E5E5E5 → #CDD8E0.
//   • primary restored: #003F5C (Cofely brand blue, corrige les références
//     existantes dans login_screen et onboarding).
//   • Nouvelle hiérarchie d'encre 4 niveaux: ink/inkSoft/muted/mutedSoft
//     pour profondeur texte architecture 3-panels.
//   • Nouvelle hiérarchie fonds 4 niveaux: bg/bgSoft/bgSurface/bgElevated
//     pour architecture dark-first. Mode sombre darkBg→darkBgSurface→darkBgElevated
//     crée profondeur sans bordures. Accent #007AFC pop sur tous les fonds sombres.
//   • Nouvelle hiérarchie bordures: line/lineSubtle.
//   • accentDim (#58B4D1 light / #1E3A5F dark) pour états passifs.
//   • Typographie: échelle 8 niveaux (displayLarge 64 → label 11), JetBrains Mono.
//   • Espacement: grille 4px, scale étendue (2→96).
//   • Rayons standardisés: none=0, sm=4, md=8, lg=24, xl=32, pill=100.
//     bubbleRadius=12, inputRadius=24, chipRadius=20 conservés.
//   • Ombres: 4 niveaux (subtle/medium/large/atmospheric) dont signature Mapbox
//     atmospheric glow (0 0 100px 50px rgba(14,16,18,0.40)).
//   • Animations: 4 durées (micro 150ms / fast 220ms / normal 400ms / slow 800ms)
//     + courbe signature cubic-bezier(0.19, 1, 0.22, 1).
//   • Composants: sidebar 280px, infoPanel 320px, chat max-width 400px.
//     bouton hauteur 40px / radius 8px, input hauteur 48px / radius 24px.
//   • Dégradé avatar rétabli: primary→accent (#003F5C→#007AFC).
//   • Mode sombre dark-first: toutes les couleurs et constantes dark* exposées.
//   • Tous les noms de constantes existants sont conservés (bg, surface, ink,
//     inkSoft, line, hover, accent, accentBg, accentHover, espacements,
//     radius, polices, durées, etc.).
//
// ┌─ ARCHITECTURE COULEURS ──────────────────────────────────────────────────┐
// │  INK HIERARCHY (profondeur texte 4 niveaux)                              │
// │    ink       → Texte principal, titres                                   │
// │    inkSoft   → Texte secondaire, métadonnées                             │
// │    muted     → Texte tertiaire, libellés désactivés, outlines            │
// │    mutedSoft → Bordures subtiles, séparateurs légers                     │
// │                                                                           │
// │  BG HIERARCHY (profondeur surfaces 4 niveaux)                            │
// │    bg          → Fond global (scaffold)                                  │
// │    bgSoft      → Fond sidebar                                            │
// │    bgSurface   → Fond panneau central (chat)                             │
// │    bgElevated  → Fond modaux, info panel, bulles bot (dark)              │
// │                                                                           │
// │  LINE HIERARCHY (bordures 2 niveaux)                                     │
// │    line        → Bordures standard, séparateurs principaux               │
// │    lineSubtle  → Bordures subtiles, hover states                         │
// │                                                                           │
// │  ACCENT HIERARCHY                                                        │
// │    primary     → #003F5C (light) / #58B4D1 (dark) — identité Cofely      │
// │    accent      → #007AFC — Mapbox blue, actions, CTA, liens, bulles user│
// │    accentDim   → #58B4D1 (light) / #1E3A5F (dark) — états passifs       │
// │                                                                           │
// │  BULLES DE CHAT                                                           │
// │    Light : bot blanc / #007AFC user — Dark : #22272E bot / #1E3A5F user  │
// └─────────────────────────────────────────────────────────────────────────┘

import 'package:flutter/material.dart';

/// Tokens de design Corely — source unique de vérité pour toute l'UI Corely.
/// Mapbox-inspired v2.1 : dark-first, hiérarchie d'encre 4 niveaux,
/// accent #007AFC, type scale 8 niveaux, ombres 4 niveaux.
abstract class CorelyTokens {
  // ═══════════════════════════════════════════════════════════════════════════
  // PALETTE — MODE CLAIR
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Identité de marque ────────────────────────────────────────────────────
  /// Bleu foncé Cofely — identité, headers, boutons CTA, dégradé avatar
  static const Color primary     = Color(0xFF003F5C);

  /// Bleu Mapbox — actions, CTA, liens, bulles utilisateur, accent principal
  static const Color accent      = Color(0xFF007AFC);

  /// Accent atténué — états passifs, badges inactifs (devient primary en dark)
  static const Color accentDim   = Color(0xFF58B4D1);

  // ── Hiérarchie des surfaces ──────────────────────────────────────────────
  /// Fond global interface (scaffold) — gris-bleu très clair
  static const Color bg          = Color(0xFFF0F4F8);

  /// Fond cartes, panneaux, bulles bot
  static const Color surface     = Color(0xFFFFFFFF);

  /// Fond sidebar
  static const Color bgSoft      = Color(0xFFFFFFFF);

  /// Fond panneaux, cartes (alias pour surface)
  static const Color bgSurface   = Color(0xFFFFFFFF);

  /// Fond modaux, popovers, dialogues
  static const Color bgElevated  = Color(0xFFFFFFFF);

  /// Fond zone chat (alias pour bg)
  static const Color chatBg      = bg;

  // ── Hiérarchie d'encre (texte) ───────────────────────────────────────────
  /// Texte principal, titres — bleu foncé profond
  static const Color ink         = Color(0xFF0D1E28);

  /// Texte secondaire, métadonnées, labels — gris-bleu
  static const Color inkSoft     = Color(0xFF4A6375);

  /// Texte tertiaire, libellés inactifs, outlines — gris-bleu moyen
  static const Color muted       = Color(0xFF8DAABB);

  /// Bordures subtiles, séparateurs discrets — gris-bleu clair
  static const Color mutedSoft   = Color(0xFFB0C8D6);

  // ── Hiérarchie de bordures ───────────────────────────────────────────────
  /// Bordures standard, séparateurs principaux
  static const Color line        = Color(0xFFCDD8E0);

  /// Bordures très subtiles, hover states
  static const Color lineSubtle  = Color(0xFFE1EBF2);

  /// Survol éléments (alias proche de lineSubtle)
  static const Color hover       = Color(0xFFE8EEF4);

  // ── Accent containers ────────────────────────────────────────────────────
  /// Fond accent léger (tint de #007AFC) — pour containers d'accent
  static const Color accentBg    = Color(0xFFD6EAFF);

  /// Accent survolé (darken de #007AFC) — pour états hover du bouton accent
  static const Color accentHover = Color(0xFF0060DB);

  // ── Bulles de chat (mode clair) ──────────────────────────────────────────
  /// Fond bulle bot (clair) — blanc
  static const Color botBubble   = surface;

  /// Fond bulle utilisateur (clair) — accent #007AFC
  static const Color userBubble  = accent;

  /// Texte bulle utilisateur (clair) — blanc sur accent
  static const Color userBubbleText = Color(0xFFFFFFFF);

  // ── Texte sur fonds de couleur ───────────────────────────────────────────
  /// Texte blanc sur primary
  static const Color onPrimary   = Color(0xFFFFFFFF);

  /// Texte blanc sur accent (WCAG AA 4.5:1)
  static const Color onAccent    = Color(0xFFFFFFFF);

  /// Texte principal sur surface (= ink)
  static const Color onSurface   = ink;

  // ═══════════════════════════════════════════════════════════════════════════
  // PALETTE — MODE SOMBRE
  // ═══════════════════════════════════════════════════════════════════════════
  // Architecture dark-first : bg → bgSoft → bgSurface → bgElevated crée de la
  // profondeur sans bordures. Accent #007AFC pop sur tous les fonds.

  // ── Identité de marque (dark) ─────────────────────────────────────────────
  /// Primary mode sombre — bleu ciel (= light accentDim)
  static const Color darkPrimary     = Color(0xFF58B4D1);

  /// Accent mode sombre — identique au mode clair
  static const Color darkAccent      = Color(0xFF007AFC);

  /// Accent atténué sombre — bulle user, containers primaires
  static const Color darkAccentDim   = Color(0xFF1E3A5F);

  // ── Hiérarchie des surfaces (dark) ────────────────────────────────────────
  /// Fond global sombre (scaffold) — presque noir
  static const Color darkBg          = Color(0xFF0E1012);

  /// Fond sidebar sombre
  static const Color darkBgSoft      = Color(0xFF15171B);

  /// Fond chat, panneaux sombres
  static const Color darkBgSurface   = Color(0xFF1A1E24);

  /// Fond modaux, info panel, bulles bot sombres
  static const Color darkBgElevated  = Color(0xFF22272E);

  /// Équivalent surface en mode sombre
  static const Color darkSurface     = Color(0xFF1A1E24);

  // ── Hiérarchie d'encre (dark) ────────────────────────────────────────────
  /// Texte principal sombre — blanc
  static const Color darkInk         = Color(0xFFFFFFFF);

  /// Texte secondaire sombre — gris-bleu clair
  static const Color darkInkSoft     = Color(0xFFA0AABA);

  /// Texte tertiaire sombre, bordures — gris foncé
  static const Color darkMuted       = Color(0xFF333943);

  /// Bordures subtiles sombres — gris moyen-foncé
  static const Color darkMutedSoft   = Color(0xFF566171);

  // ── Hiérarchie de bordures (dark) ─────────────────────────────────────────
  /// Bordures, séparateurs sombres
  static const Color darkLine        = Color(0xFF333943);

  /// Bordures très subtiles sombres
  static const Color darkLineSubtle  = Color(0xFF282D36);

  // ── Bulles de chat (mode sombre) ──────────────────────────────────────────
  /// Fond bulle bot sombre — bgElevated
  static const Color darkBotBubble   = Color(0xFF22272E);

  /// Fond bulle user sombre — accentDim
  static const Color darkUserBubble  = Color(0xFF1E3A5F);

  /// Texte bulle bot sombre — blanc
  static const Color darkBotText     = Color(0xFFFFFFFF);

  /// Texte bulle user sombre — inkSoft
  static const Color darkUserText    = Color(0xFFA0AABA);

  // ── Composants (dark) ─────────────────────────────────────────────────────
  /// Fond champ de saisie sombre
  static const Color darkInputBg     = Color(0xFF22272E);

  /// Séparateur sombre
  static const Color darkDivider     = Color(0xFF333943);

  /// Survol élément interactif sombre — rgba(0,122,252,0.10)
  static const Color darkHoverHighlight = Color(0x19007AFC);

  /// Survol actif sombre — rgba(0,122,252,0.18)
  static const Color darkActiveHighlight = Color(0x2E007AFC);

  /// Pouce scrollbar sombre
  static const Color darkScrollbarThumb = Color(0xFF333943);

  /// Piste scrollbar sombre
  static const Color darkScrollbarTrack = Color(0xFF15171B);

  /// Fond toast / snackbar sombre
  static const Color darkToastBg      = Color(0xFF22272E);

  /// Texte toast sombre
  static const Color darkToastText    = Color(0xFFFFFFFF);

  // ═══════════════════════════════════════════════════════════════════════════
  // COULEURS SÉMANTIQUES
  // ═══════════════════════════════════════════════════════════════════════════
  /// Vert succès — point "En ligne", confirmation
  static const Color onlineGreen   = Color(0xFF22C55E);

  /// Rouge erreur — danger, suppression
  static const Color errorRed      = Color(0xFFEF4444);

  /// Ambre avertissement — attention
  static const Color warningAmber  = Color(0xFFF59E0B);

  /// Vert succès (alias onlineGreen)
  static const Color successGreen  = Color(0xFF22C55E);

  /// Bleu information — info, notification
  static const Color infoBlue      = Color(0xFF007AFC);

  // ═══════════════════════════════════════════════════════════════════════════
  // DÉGRADÉS
  // ═══════════════════════════════════════════════════════════════════════════
  /// Dégradé avatar bot (clair) : primary → accent (#003F5C → #007AFC)
  static const LinearGradient avatarGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Dégradé avatar bot (sombre) : darkPrimary → darkAccent (#58B4D1 → #007AFC)
  static const LinearGradient darkAvatarGradient = LinearGradient(
    colors: [darkPrimary, darkAccent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // TYPOGRAPHIE
  // ═══════════════════════════════════════════════════════════════════════════
  /// Police d'affichage et UI (Inter)
  static const String displayFont = 'Inter';

  /// Police pour le corps du texte (JetBrains Mono)
  static const String bodyFont    = 'JetBrainsMono';

  /// Police UI (Inter)
  static const String uiFont      = 'Inter';

  /// Police principale (alias)
  static const String fontFamily  = 'Inter';

  /// Police monospace pour code, logs
  static const String fontFamilyMono = 'JetBrains Mono';

  // ── Poids de police ───────────────────────────────────────────────────────
  static const FontWeight weightLight    = FontWeight.w300;
  static const FontWeight weightRegular  = FontWeight.w400;
  static const FontWeight weightMedium   = FontWeight.w500;
  static const FontWeight weightSemiBold = FontWeight.w600;
  static const FontWeight weightBold     = FontWeight.w700;

  // ── Display (héros, splash, empty state) ─────────────────────────────────
  static const double displaySize   = 64.0;
  static const double displayHeight = 1.0;
  static const FontWeight displayWeight = weightMedium;
  static const double displayLetterSpacing = -1.5;

  // ── Headline (panneaux, sections) ─────────────────────────────────────────
  static const double headlineSize   = 32.0;
  static const double headlineHeight = 1.15;
  static const FontWeight headlineWeight = weightSemiBold;

  // ── Title (conversations, contextes) ──────────────────────────────────────
  static const double titleSize   = 20.0;
  static const double titleHeight = 1.3;
  static const FontWeight titleWeight = weightMedium;

  // ── Body (messages chat, paramètres) ──────────────────────────────────────
  static const double bodySize   = 16.0;
  static const double bodyHeight = 1.5;
  static const FontWeight bodyWeight = weightRegular;

  // ── Body small (métadonnées, timestamps) ──────────────────────────────────
  static const double bodySmallSize   = 14.0;
  static const double bodySmallHeight = 1.4;
  static const FontWeight bodySmallWeight = weightRegular;

  // ── Caption (aides, raccourcis) ───────────────────────────────────────────
  static const double captionSize   = 12.0;
  static const double captionHeight = 1.3;
  static const FontWeight captionWeight = weightRegular;

  // ── Button / Label (sidebar, tabs, badges) ────────────────────────────────
  static const double buttonSize         = 11.0;
  static const double buttonHeight       = 1.2;
  static const FontWeight buttonWeight   = weightSemiBold;
  static const double buttonLetterSpacing = 0.5;

  // ── Échelle complète (noms descriptifs pour usage générique) ─────────────
  static const double displayLargeSize   = 64.0;
  static const double displayLargeLineH  = 1.0;
  static const double displayLargeLS     = -1.5;
  static const FontWeight displayLargeW  = weightMedium;

  static const double displayMediumSize  = 48.0;
  static const double displayMediumLineH = 1.05;
  static const double displayMediumLS    = -1.0;
  static const FontWeight displayMediumW = weightMedium;

  static const double headingSize   = 32.0;
  static const double headingLineH  = 1.15;
  static const double headingLS     = 0.0;
  static const FontWeight headingW  = weightSemiBold;

  static const double subheadSize   = 20.0;
  static const double subheadLineH  = 1.3;
  static const double subheadLS     = 0.0;
  static const FontWeight subheadW  = weightMedium;

  // Alias vers les constantes existantes pour la rétrocompatibilité
  static const double labelSize   = 11.0;
  static const double labelLineH  = 1.2;
  static const double labelLS     = 0.5;
  static const FontWeight labelW  = weightSemiBold;

  // ═══════════════════════════════════════════════════════════════════════════
  // ESPACEMENT (grille 4px)
  // ═══════════════════════════════════════════════════════════════════════════
  // Noms RTTB conservés (space0–space8)
  static const double space0 = 0.0;
  static const double space1 = 4.0;
  static const double space2 = 8.0;
  static const double space3 = 16.0;
  static const double space4 = 24.0;
  static const double space5 = 32.0;
  static const double space6 = 48.0;
  static const double space7 = 64.0;
  static const double space8 = 96.0;

  // Noms par valeur (grille 4px étendue)
  static const double spacingBase = 4.0;
  static const double spacing2  = 2.0;
  static const double spacing4  = 4.0;
  static const double spacing8  = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing40 = 40.0;
  static const double spacing48 = 48.0;
  static const double spacing64 = 64.0;
  static const double spacing80 = 80.0;
  static const double spacing96 = 96.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // RAYONS DE BORDURE
  // ═══════════════════════════════════════════════════════════════════════════
  // Échelle standard
  static const double radiusNone  = 0.0;    // Coins droits
  static const double radiusSm    = 4.0;    // Sidebar, badges
  static const double radiusMd    = 8.0;    // Cartes, boutons
  static const double radiusLg    = 24.0;   // Panneaux (Mapbox signature)
  static const double radiusXl    = 32.0;   // Modaux, dialogues
  static const double radiusPill  = 100.0;  // Forme pilule / cercle parfait

  // Radius spécifiques aux composants
  static const double bubbleRadius = 12.0;  // Bulles de chat (entre md et lg)
  static const double tailRadius   = radiusSm;  // Queue intérieure bulle (= 4)
  static const double chipRadius   = 20.0;  // ActionChip toolbar
  static const double inputRadius  = radiusLg;  // Champ de saisie (= 24)

  // ═══════════════════════════════════════════════════════════════════════════
  // BORDURES (remplacent les ombres RTTB)
  // ═══════════════════════════════════════════════════════════════════════════
  /// Bordure standard 1px — couleur line
  static const BorderSide hairline = BorderSide(color: line, width: 1.0);

  /// Bordure accent 1px — couleur accent (#007AFC)
  static const BorderSide hairlineAccent = BorderSide(color: accent, width: 1.0);

  // ═══════════════════════════════════════════════════════════════════════════
  // OMBRES
  // ═══════════════════════════════════════════════════════════════════════════
  /// 0px 1px 3px rgba(0,0,0,0.08) — Chips, petites cartes, header
  static const List<BoxShadow> shadowSubtle = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 3,
      offset: Offset(0, 1),
    ),
  ];

  /// 0px 4px 12px rgba(0,0,0,0.10) — Bulles de chat, dropdowns, tooltips
  static const List<BoxShadow> shadowMedium = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// 0px 8px 24px rgba(0,0,0,0.12) — Modaux, panneaux, drawers
  static const List<BoxShadow> shadowLarge = [
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  /// 0px 0px 100px 50px rgba(14,16,18,0.40) — Signature Mapbox glow
  static const List<BoxShadow> shadowAtmospheric = [
    BoxShadow(
      color: Color(0x660E1012),
      blurRadius: 100,
      spreadRadius: 50,
      offset: Offset(0, 0),
    ),
  ];

  /// Pas d'ombre (RTTB compat)
  static const List<BoxShadow> noneShadow = [];

  /// Ombre d'en-tête — alias vers shadowSubtle
  static const List<BoxShadow> headerShadow = shadowSubtle;

  /// Ombre de bulle de chat — alias vers shadowMedium
  static const List<BoxShadow> bubbleShadow = shadowMedium;

  // ═══════════════════════════════════════════════════════════════════════════
  // DIMENSIONS DES COMPOSANTS
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Chat ──────────────────────────────────────────────────────────────────
  /// Diamètre avatar bot
  static const double avatarSize    = 36.0;

  /// Taille police lettre avatar "C"
  static const double avatarFontSz  = 16.0;

  /// Padding intérieur bouton d'envoi circulaire
  static const double sendBtnPad    = 14.0;

  /// Largeur max du chat sur desktop (centré)
  static const double maxChatWidth  = 400.0;

  // ── Sidebar ───────────────────────────────────────────────────────────────
  static const double sidebarWidth        = 280.0;
  static const double sidebarItemHeight   = 40.0;
  static const double sidebarItemRadius   = 6.0;
  static const double sidebarSectionGap   = 24.0;
  static const double sidebarIconSize     = 20.0;
  static const double sidebarLabelSize    = 13.0;
  static const double sidebarActiveIndW   = 3.0; // Largeur indicateur actif

  // ── Info panel ────────────────────────────────────────────────────────────
  static const double infoPanelWidth      = 320.0;
  static const double infoPanelPadding    = 20.0;
  static const double infoPanelSectionGap = 24.0;
  static const double infoPanelRadius     = 24.0;
  static const double infoPanelHeaderH    = 56.0;

  // ── Boutons ───────────────────────────────────────────────────────────────
  static const double buttonHeight   = 40.0;
  static const double buttonRadius   = radiusMd;  // = 8
  static const double buttonFontSize = 14.0;

  // ── Input ─────────────────────────────────────────────────────────────────
  static const double inputHeight = 48.0;
  static const double inputFontSz = 15.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // LAYOUT (conservés RTTB)
  // ═══════════════════════════════════════════════════════════════════════════
  static const double containerMaxWidth   = 680.0;
  static const double paragraphMaxWidth   = 680.0;
  static const double verticalRhythm      = 16.0;
  static const double desktopBreakpoint   = 900.0;
  static const double tabletBreakpoint    = 600.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // ANIMATIONS — DURÉES
  // ═══════════════════════════════════════════════════════════════════════════
  /// 150 ms — Hover, active feedback, scale au press
  static const Duration microDuration  = Duration(milliseconds: 150);

  /// 220 ms — Panel open/close, petits mouvements
  static const Duration smallDuration  = Duration(milliseconds: 220);

  /// 400 ms — Page transitions, apparitions normales
  static const Duration mediumDuration = Duration(milliseconds: 400);

  /// 800 ms — Atmospheric reveals, splash
  static const Duration slowDuration   = Duration(milliseconds: 800);

  // ── Noms descriptifs supplémentaires ──────────────────────────────────────
  static const Duration microAnim  = microDuration;   // 150 ms alias
  static const Duration fastAnim   = smallDuration;   // 220 ms alias
  static const Duration normalAnim = mediumDuration;  // 400 ms alias
  static const Duration slowAnim   = slowDuration;    // 800 ms alias

  // ── Chat loading dots ─────────────────────────────────────────────────────
  /// Animation individuelle des points de suspension
  static const Duration dotAnim    = Duration(milliseconds: 500);

  /// Décalage entre chaque point (stagger)
  static const Duration dotStagger = Duration(milliseconds: 150);

  /// AnimatedScale au press du bouton d'envoi
  static const Duration scaleAnim  = microDuration;   // 150 ms alias

  // ═══════════════════════════════════════════════════════════════════════════
  // ANIMATIONS — COURBES
  // ═══════════════════════════════════════════════════════════════════════════
  /// Mapbox signature ease : cubic-bezier(0.19, 1, 0.22, 1)
  /// Accélère rapidement puis décélère en douceur
  static const Curve standardEasing = Cubic(0.19, 1.0, 0.22, 1.0);

  /// Courbe de mouvement (alias standardEasing)
  static const Curve motionCurve    = Cubic(0.19, 1.0, 0.22, 1.0);

  /// RTTB easing conservé (fastOutSlowIn)
  static const Curve rttbEasing = Curves.fastOutSlowIn;

  // ═══════════════════════════════════════════════════════════════════════════
  // THÈME CLAIR — MAPBOX INSPIRED
  // ═══════════════════════════════════════════════════════════════════════════
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    brightness: Brightness.light,
    scaffoldBackgroundColor: bg,

    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: Color(0xFFCCE8F4),
      onPrimaryContainer: primary,
      secondary: accent,
      onSecondary: onAccent,
      secondaryContainer: accentBg,
      onSecondaryContainer: Color(0xFF003F5C),
      tertiary: Color(0xFF4A9EFF),
      onTertiary: onPrimary,
      tertiaryContainer: Color(0xFFD6EAFF),
      onTertiaryContainer: Color(0xFF003F5C),
      error: errorRed,
      onError: onPrimary,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: hover,
      onSurfaceVariant: inkSoft,
      outline: muted,
      outlineVariant: line,
      scrim: Color(0xFF000000),
      inverseSurface: ink,
      onInverseSurface: bg,
      inversePrimary: accent,
      surfaceTint: primary,
    ),

    // ── Typographie ─────────────────────────────────────────────────────────
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: displaySize,
        height: displayHeight,
        fontWeight: displayWeight,
        letterSpacing: displayLetterSpacing,
        color: ink,
      ),
      displayMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: displayMediumSize,
        height: displayMediumLineH,
        fontWeight: displayMediumW,
        letterSpacing: displayMediumLS,
        color: ink,
      ),
      headlineLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: headlineSize,
        height: headlineHeight,
        fontWeight: headlineWeight,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontFamily: uiFont,
        fontSize: titleSize,
        height: titleHeight,
        fontWeight: titleWeight,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontFamily: uiFont,
        fontSize: subheadSize,
        height: subheadLineH,
        fontWeight: subheadW,
        color: ink,
      ),
      bodyLarge: TextStyle(
        fontFamily: bodyFont,
        fontSize: bodySize,
        height: bodyHeight,
        fontWeight: bodyWeight,
        color: ink,
      ),
      bodyMedium: TextStyle(
        fontFamily: bodyFont,
        fontSize: bodySmallSize,
        height: bodySmallHeight,
        fontWeight: bodySmallWeight,
        color: inkSoft,
      ),
      bodySmall: TextStyle(
        fontFamily: uiFont,
        fontSize: captionSize,
        height: captionHeight,
        fontWeight: captionWeight,
        color: muted,
      ),
      labelLarge: TextStyle(
        fontFamily: uiFont,
        fontSize: buttonSize,
        height: buttonHeight,
        fontWeight: buttonWeight,
        letterSpacing: buttonLetterSpacing,
        color: ink,
      ),
    ),

    // ── AppBar ──────────────────────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: uiFont,
        fontSize: 18,
        fontWeight: weightSemiBold,
        color: ink,
      ),
      iconTheme: IconThemeData(color: ink),
    ),

    // ── Input ───────────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: hover,
      hintStyle: const TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputRadius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputRadius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputRadius),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputRadius),
        borderSide: const BorderSide(color: errorRed),
      ),
    ),

    // ── FilledButton ────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        textStyle: const TextStyle(
          fontFamily: uiFont,
          fontSize: buttonFontSize,
          fontWeight: weightSemiBold,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
        minimumSize: const Size(48, buttonHeight),
        elevation: 2,
        shadowColor: primary.withAlpha(80),
      ),
    ),

    // ── ElevatedButton ──────────────────────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
      ),
    ),

    // ── OutlinedButton ──────────────────────────────────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: primary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
        minimumSize: const Size(48, buttonHeight),
      ),
    ),

    // ── TextButton ──────────────────────────────────────────────────────────
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primary),
    ),

    // ── Chip / ActionChip ───────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: bg,
      selectedColor: accentBg,
      labelStyle: const TextStyle(
        fontFamily: uiFont,
        fontSize: 12,
        color: ink,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: uiFont,
        fontSize: 12,
        color: inkSoft,
      ),
      side: hairline,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(chipRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      selectedShadowColor: Colors.transparent,
      shadowColor: Colors.transparent,
    ),

    // ── Card ─────────────────────────────────────────────────────────────────
    cardTheme: const CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
        side: BorderSide(color: line),
      ),
      margin: EdgeInsets.symmetric(vertical: space1, horizontal: 0),
    ),

    // ── Dialog ───────────────────────────────────────────────────────────────
    dialogTheme: const DialogThemeData(
      backgroundColor: bgElevated,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusXl)),
      ),
    ),

    // ── BottomSheet ──────────────────────────────────────────────────────────
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
      ),
    ),

    // ── Divider ──────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: line,
      thickness: 1,
      space: 1,
    ),

    // ── Icon ─────────────────────────────────────────────────────────────────
    iconTheme: const IconThemeData(color: ink, size: 20),

    // ── ListTile ─────────────────────────────────────────────────────────────
    listTileTheme: const ListTileThemeData(
      iconColor: primary,
      leadingAndTrailingTextStyle: TextStyle(color: inkSoft),
    ),

    // ── Switch ───────────────────────────────────────────────────────────────
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? onPrimary : null),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? primary : null),
    ),

    // ── SnackBar ─────────────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      contentTextStyle:
          const TextStyle(color: Colors.white, fontFamily: fontFamily),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      behavior: SnackBarBehavior.floating,
    ),

    // ── ProgressIndicator ────────────────────────────────────────────────────
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: primary),

    // ── Scrollbar ────────────────────────────────────────────────────────────
    scrollbarTheme: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(muted),
    ),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // THÈME SOMBRE — MAPBOX DARK-FIRST
  // ═══════════════════════════════════════════════════════════════════════════
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: darkBg,

    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: darkPrimary,
      onPrimary: Color(0xFF003044),
      primaryContainer: darkAccentDim,
      onPrimaryContainer: Color(0xFFB8E2F2),
      secondary: darkAccent,
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFF004B8C),
      onSecondaryContainer: Color(0xFFB8E2F2),
      tertiary: Color(0xFF4A9EFF),
      onTertiary: Color(0xFF003366),
      tertiaryContainer: Color(0xFF001F4A),
      onTertiaryContainer: Color(0xFFBAD6FF),
      error: errorRed,
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: darkBgSurface,
      onSurface: darkInk,
      surfaceContainerHighest: darkBgElevated,
      onSurfaceVariant: darkInkSoft,
      outline: darkMuted,
      outlineVariant: darkLineSubtle,
      scrim: Color(0xFF000000),
      inverseSurface: bg,
      onInverseSurface: ink,
      inversePrimary: primary,
      surfaceTint: darkPrimary,
    ),

    // ── Typographie ─────────────────────────────────────────────────────────
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: displaySize,
        height: displayHeight,
        fontWeight: displayWeight,
        letterSpacing: displayLetterSpacing,
        color: darkInk,
      ),
      displayMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: displayMediumSize,
        height: displayMediumLineH,
        fontWeight: displayMediumW,
        letterSpacing: displayMediumLS,
        color: darkInk,
      ),
      headlineLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: headlineSize,
        height: headlineHeight,
        fontWeight: headlineWeight,
        color: darkInk,
      ),
      titleLarge: TextStyle(
        fontFamily: uiFont,
        fontSize: titleSize,
        height: titleHeight,
        fontWeight: titleWeight,
        color: darkInk,
      ),
      titleMedium: TextStyle(
        fontFamily: uiFont,
        fontSize: subheadSize,
        height: subheadLineH,
        fontWeight: subheadW,
        color: darkInk,
      ),
      bodyLarge: TextStyle(
        fontFamily: bodyFont,
        fontSize: bodySize,
        height: bodyHeight,
        fontWeight: bodyWeight,
        color: darkInk,
      ),
      bodyMedium: TextStyle(
        fontFamily: bodyFont,
        fontSize: bodySmallSize,
        height: bodySmallHeight,
        fontWeight: bodySmallWeight,
        color: darkInkSoft,
      ),
      bodySmall: TextStyle(
        fontFamily: uiFont,
        fontSize: captionSize,
        height: captionHeight,
        fontWeight: captionWeight,
        color: darkMuted,
      ),
      labelLarge: TextStyle(
        fontFamily: uiFont,
        fontSize: buttonSize,
        height: buttonHeight,
        fontWeight: buttonWeight,
        letterSpacing: buttonLetterSpacing,
        color: darkInk,
      ),
    ),

    // ── AppBar ──────────────────────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: darkBgSoft,
      foregroundColor: darkInk,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: uiFont,
        fontSize: 18,
        fontWeight: weightSemiBold,
        color: darkInk,
      ),
      iconTheme: IconThemeData(color: darkInk),
    ),

    // ── Input ───────────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkInputBg,
      hintStyle: const TextStyle(color: darkMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputRadius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputRadius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputRadius),
        borderSide: const BorderSide(color: darkAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputRadius),
        borderSide: const BorderSide(color: errorRed),
      ),
    ),

    // ── FilledButton ────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: darkAccent,
        foregroundColor: Color(0xFFFFFFFF),
        textStyle: const TextStyle(
          fontFamily: uiFont,
          fontSize: buttonFontSize,
          fontWeight: weightSemiBold,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
        minimumSize: const Size(48, buttonHeight),
        elevation: 2,
        shadowColor: darkAccent.withAlpha(60),
      ),
    ),

    // ── ElevatedButton ──────────────────────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: darkPrimary,
        foregroundColor: const Color(0xFF003044),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
      ),
    ),

    // ── OutlinedButton ──────────────────────────────────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: darkPrimary,
        side: const BorderSide(color: darkPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
        minimumSize: const Size(48, buttonHeight),
      ),
    ),

    // ── TextButton ──────────────────────────────────────────────────────────
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: darkPrimary),
    ),

    // ── Chip / ActionChip ───────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: darkBgElevated,
      selectedColor: darkAccentDim,
      labelStyle: const TextStyle(
        fontFamily: uiFont,
        fontSize: 12,
        color: darkInk,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: uiFont,
        fontSize: 12,
        color: darkInkSoft,
      ),
      side: BorderSide(color: darkLine),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(chipRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      selectedShadowColor: Colors.transparent,
      shadowColor: Colors.transparent,
    ),

    // ── Card ─────────────────────────────────────────────────────────────────
    cardTheme: const CardThemeData(
      color: darkBgSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
        side: BorderSide(color: darkLine),
      ),
      margin: EdgeInsets.symmetric(vertical: space1, horizontal: 0),
    ),

    // ── Dialog ───────────────────────────────────────────────────────────────
    dialogTheme: const DialogThemeData(
      backgroundColor: darkBgElevated,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusXl)),
      ),
    ),

    // ── BottomSheet ──────────────────────────────────────────────────────────
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: darkBgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
      ),
    ),

    // ── Divider ──────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: darkDivider,
      thickness: 1,
      space: 1,
    ),

    // ── Icon ─────────────────────────────────────────────────────────────────
    iconTheme: const IconThemeData(color: darkInk, size: 20),

    // ── ListTile ─────────────────────────────────────────────────────────────
    listTileTheme: const ListTileThemeData(
      iconColor: darkPrimary,
      leadingAndTrailingTextStyle: TextStyle(color: darkInkSoft),
    ),

    // ── Switch ───────────────────────────────────────────────────────────────
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? darkPrimary : null),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? darkPrimary : null),
    ),

    // ── SnackBar ─────────────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      backgroundColor: darkToastBg,
      contentTextStyle:
          const TextStyle(color: darkToastText, fontFamily: fontFamily),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      behavior: SnackBarBehavior.floating,
    ),

    // ── ProgressIndicator ────────────────────────────────────────────────────
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: darkAccent),

    // ── Scrollbar ────────────────────────────────────────────────────────────
    scrollbarTheme: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(darkScrollbarThumb),
    ),
  );
}
