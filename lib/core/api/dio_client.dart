// Conditional export: mobile (dart:io) vs web stub
export 'dio_client_io.dart' if (dart.library.html) 'dio_client_web.dart';