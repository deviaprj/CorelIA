import 'package:flutter/foundation.dart';

/// Plateforme detectee (version web : extension Chrome + navigateur).
enum AppPlatform {
  mobileAndroid, // jamais sur web, conserve pour uniformite
  mobileIos, // jamais sur web, conserve pour uniformite
  chromeExtension,
  web,
  desktopLinux, // jamais sur web, conserve pour uniformite
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
  static bool get _isChromeExtension =>
      Uri.base.scheme == 'chrome-extension';

  static AppPlatform get current {
    if (_isChromeExtension) return AppPlatform.chromeExtension;
    return AppPlatform.web;
  }

  static bool get isMobile => false;

  static bool get isExtension => _isChromeExtension;

  static bool get isDesktop => false;

  static bool get isWeb => true;
}
