// Conditional export: mobile (Ollama local, dart:io) vs web stub
export 'ollama_vision_service_io.dart' if (dart.library.html) 'ollama_vision_service_web.dart';