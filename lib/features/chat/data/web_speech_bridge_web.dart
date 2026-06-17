import 'dart:async';
import 'dart:js' as js;
import 'package:flutter/foundation.dart';

/// Bridge vocal web — communique avec speech_bridge.js via CustomEvents.
/// Utilise dart:js pour l'accès dynamique aux propriétés JS
/// (l'extension Chrome ne cible pas WASM, dart:js est sûr).
class WebSpeechBridge {
  final _resultController = StreamController<String>.broadcast();
  final _isFinalController = StreamController<bool>.broadcast();
  final _endController = StreamController<void>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _speakEndController = StreamController<void>.broadcast();

  bool _available = false;
  bool _isListening = false;

  bool get isAvailable => _available;
  bool get isListening => _isListening;

  WebSpeechBridge() {
    _checkAvailability();
    _registerListeners();
  }

  void _checkAvailability() {
    _available = _hasSpeechRecognition();
    debugPrint('[WebSpeechBridge] STT disponible: $_available');
  }

  bool _hasSpeechRecognition() {
    try {
      final hasWebkit = js.context.hasProperty('webkitSpeechRecognition');
      final hasStandard = js.context.hasProperty('SpeechRecognition');
      return hasWebkit || hasStandard;
    } catch (_) {
      return false;
    }
  }

  void _registerListeners() {
    _addWindowListener('corely_speech_result', (js.JsObject event) {
      final detail = event['detail'] as js.JsObject?;
      if (detail == null) return;
      final transcript = _getString(detail, 'transcript');
      final isFinal = _getBool(detail, 'isFinal') ?? false;
      if (transcript.isNotEmpty) {
        _resultController.add(transcript);
        _isFinalController.add(isFinal);
      }
    });

    _addWindowListener('corely_speech_end', (js.JsObject event) {
      _isListening = false;
      _endController.add(null);
    });

    _addWindowListener('corely_speech_error', (js.JsObject event) {
      final detail = event['detail'] as js.JsObject?;
      final error = detail != null ? _getString(detail, 'error') : 'unknown';
      _errorController.add(error.isNotEmpty ? error : 'unknown');
      _isListening = false;
    });

    _addWindowListener('corely_tts_end', (js.JsObject event) {
      _speakEndController.add(null);
    });

    _addWindowListener('corely_tts_error', (js.JsObject event) {
      final detail = event['detail'] as js.JsObject?;
      final error = detail != null ? _getString(detail, 'error') : 'unknown';
      debugPrint('[WebSpeechBridge] TTS error: $error');
    });
  }

  // ── STT ──────────────────────────────────────────────────────────────────

  Future<void> startListening(String lang) async {
    if (!_available) return;
    _isListening = true;
    _dispatch('corely_speech_start', {'lang': lang});
  }

  Future<void> stopListening() async {
    _isListening = false;
    _dispatch('corely_speech_stop', null);
  }

  Stream<String> get onResult => _resultController.stream;
  Stream<bool> get onResultIsFinal => _isFinalController.stream;
  Stream<void> get onEnd => _endController.stream;
  Stream<String> get onError => _errorController.stream;

  // ── TTS ──────────────────────────────────────────────────────────────────

  Future<void> speak(String text, {String emotion = 'neutral'}) async {
    _dispatch('corely_tts_speak', {'text': text, 'emotion': emotion});
  }

  Future<void> stopSpeaking() async {
    _dispatch('corely_tts_stop', null);
  }

  Stream<void> get onSpeakEnd => _speakEndController.stream;

  // ── Dispatch CustomEvent via dart:js ────────────────────────────────────

  void _dispatch(String type, Map<String, String>? detail) {
    try {
      if (detail != null) {
        final jsDetail = js.JsObject.jsify(detail);
        js.context.callMethod('dispatchCustomEvent', [type, jsDetail]);
      } else {
        js.context.callMethod('dispatchCustomEvent', [type, null]);
      }
    } catch (e) {
      debugPrint('[WebSpeechBridge] Error dispatching $type: $e');
    }
  }

  /// Ajoute un event listener via dart:js en utilisant allowInterop
  /// pour éviter les erreurs de type en mode minifié.
  void _addWindowListener(String type, void Function(js.JsObject) callback) {
    try {
      js.context.callMethod('addEventListener', [
        type,
        js.allowInterop((dynamic event) {
          callback(event as js.JsObject);
        }),
      ]);
    } catch (e) {
      debugPrint('[WebSpeechBridge] Error adding listener for $type: $e');
    }
  }

  String _getString(js.JsObject obj, String key) {
    try {
      final value = obj[key];
      if (value is String) return value;
      return '';
    } catch (_) {
      return '';
    }
  }

  bool? _getBool(js.JsObject obj, String key) {
    try {
      final value = obj[key];
      if (value is bool) return value;
      return null;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _resultController.close();
    _isFinalController.close();
    _endController.close();
    _errorController.close();
    _speakEndController.close();
  }
}