import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

/// Plateforme detectee (version native : mobile + desktop).
enum AppPlatform {
  mobileAndroid,
  mobileIos,
  chromeExtension, // jamais sur native, conserve pour uniformite
  web, // jamais sur native, conserve pour uniformite
  desktopLinux,
  desktopWindows,
  desktopMacos;

  /// Nom lisible de la plateforme (pour headers API, logs, etc.)
  String get name => switch (this) {
        AppPlatform.mobileAndroid => 'android',
        AppPlatform.mobileIos => 'ios',
        AppPlatform.chromeExtension => 'extension',
        AppPlatform.web => 'web',
        AppPlatform.desktopLinux => 'linux',
        AppPlatform.desktopWindows => 'windows',
        AppPlatform.desktopMacos => 'macos',
      };
}

class PlatformService {
  static AppPlatform get current {
    if (Platform.isAndroid) return AppPlatform.mobileAndroid;
    if (Platform.isIOS) return AppPlatform.mobileIos;
    if (Platform.isLinux) return AppPlatform.desktopLinux;
    if (Platform.isWindows) return AppPlatform.desktopWindows;
    if (Platform.isMacOS) return AppPlatform.desktopMacos;
    // Fallback (ne devrait jamais arriver)
    return AppPlatform.desktopLinux;
  }

  static bool get isMobile =>
      current == AppPlatform.mobileAndroid ||
      current == AppPlatform.mobileIos;

  static bool get isExtension => false; // jamais sur native

  static bool get isDesktop =>
      current == AppPlatform.desktopLinux ||
      current == AppPlatform.desktopWindows ||
      current == AppPlatform.desktopMacos;

  static bool get isWeb => false; // jamais sur native
}
