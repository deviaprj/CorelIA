// Conditional export: mobile (RevenueCat SDK) vs web stub
export 'subscription_service_mobile.dart' if (dart.library.html) 'subscription_service_web.dart';