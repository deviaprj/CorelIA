import 'package:flutter/foundation.dart';

/// Détecte la plateforme courante (mobile Android/iOS ou extension Chrome)
enum AppPlatform {
  mobileAndroid,
  mobileIos,
  chromeExtension,
  web;

  /// Nom lisible de la plateforme (pour headers API, logs, etc.)
  String get name => switch (this) {
    AppPlatform.mobileAndroid => 'android',
    AppPlatform.mobileIos => 'ios',
    AppPlatform.chromeExtension => 'extension',
    AppPlatform.web => 'web',
  };
}

class PlatformService {
  static AppPlatform get current {
    if (kIsWeb) {
      return _isChromeExtension
          ? AppPlatform.chromeExtension
          : AppPlatform.web;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AppPlatform.mobileAndroid;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppPlatform.mobileIos;
    }
    // Linux / macOS / Windows → web fallback (pas de SDK mobile)
    return AppPlatform.web;
  }

  static bool get _isChromeExtension =>
      Uri.base.scheme == 'chrome-extension';

  static bool get isMobile =>
      current == AppPlatform.mobileAndroid ||
      current == AppPlatform.mobileIos;

  static bool get isExtension =>
      current == AppPlatform.chromeExtension;
}