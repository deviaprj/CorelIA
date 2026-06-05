// Conditional export: mobile (app_links) vs web stub
export 'deep_link_service_io.dart' if (dart.library.html) 'deep_link_service_web.dart';