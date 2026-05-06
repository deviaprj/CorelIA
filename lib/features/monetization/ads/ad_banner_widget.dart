// Conditional export: mobile (AdWidget) vs web stub (from ad_service_web)
// On web, AdBannerWidget is defined in ad_service_web.dart
export 'ad_banner_widget_mobile.dart' if (dart.library.html) 'ad_service_web.dart';