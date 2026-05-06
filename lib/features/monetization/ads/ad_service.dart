// Conditional export: mobile (AdMob SDK) vs web stub
export 'ad_service_mobile.dart' if (dart.library.html) 'ad_service_web.dart';