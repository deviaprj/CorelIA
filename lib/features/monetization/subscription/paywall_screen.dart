/// Barrel — sélectionne l'implémentation du paywall selon la plateforme.
///
/// - mobile (dart:io)       → paywall_screen_mobile.dart (RevenueCat + fallback Stripe)
/// - web/extension (dart:html) → paywall_screen_web.dart (Stripe checkout / info)
///
/// Contexte : auparavant le router importait la version web sur TOUTES les
/// plateformes, ce qui affichait "Les abonnements Pro sont disponibles sur
/// l'application mobile" SUR mobile — message absurde et monétisation Pro
/// mobile inopérante (paywall_screen_mobile.dart était dead code).
export 'paywall_screen_mobile.dart' if (dart.library.html) 'paywall_screen_web.dart';