// Conditional export: mobile (File, camera, compress) vs web stub
export 'image_upload_service_io.dart' if (dart.library.html) 'image_upload_service_web.dart';