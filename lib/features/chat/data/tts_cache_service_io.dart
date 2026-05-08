import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Service de cache TTS — stocke les fichiers audio Edge TTS localement.
///
/// Clé = SHA-256(texte + voix + rate + pitch + format)
/// Valeur = fichier MP3 dans getTemporaryDirectory()/tts_cache/
///
/// LRU avec max 50 entrées, TTL 24h, purge automatique.
class TtsCacheService {
  static const _maxEntries = 50;
  static const _ttlHours = 24;
  static const _cacheDirName = 'tts_cache';

  static final TtsCacheService _instance = TtsCacheService._();
  factory TtsCacheService() => _instance;
  TtsCacheService._();

  bool _initialized = false;
  Directory? _cacheDir;

  /// Initialise le répertoire de cache (idempotent).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final tempDir = await getTemporaryDirectory();
      _cacheDir = Directory('${tempDir.path}/$_cacheDirName');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      await _purgeExpired();
      debugPrint('[TtsCache] Initialisé dans ${_cacheDir!.path}');
    } catch (e) {
      debugPrint('[TtsCache] Erreur initialisation : $e');
      _cacheDir = null;
    }
  }

  /// Calcule la clé de cache pour un texte + config vocale.
  String _cacheKey(String text, String voice, double rate, double pitch, String format) {
    final raw = '$text|$voice|$rate|$pitch|$format';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// Cherche un fichier audio en cache. Retourne le chemin si trouvé et valide.
  Future<String?> get(String text, {required String voice, required double rate, required double pitch, String format = 'audio-24khz-48kbitrate-mono-mp3'}) async {
    if (_cacheDir == null) await init();
    if (_cacheDir == null) return null;

    final key = _cacheKey(text, voice, rate, pitch, format);
    final file = File('${_cacheDir!.path}/$key.mp3');

    if (!await file.exists()) return null;

    // Vérifier TTL
    final stat = await file.stat();
    final age = DateTime.now().difference(stat.modified);
    if (age.inHours >= _ttlHours) {
      await file.delete();
      return null;
    }

    // Vérifier que le fichier n'est pas vide/corrompu
    final size = await file.length();
    if (size < 100) {
      await file.delete();
      return null;
    }

    debugPrint('[TtsCache] Cache HIT: "${text.length > 30 ? '${text.substring(0, 30)}...' : text}"');
    return file.path;
  }

  /// Stocke un fichier audio en cache. Retourne le chemin du fichier cache.
  Future<String?> put(String text, String sourcePath, {required String voice, required double rate, required double pitch, String format = 'audio-24khz-48kbitrate-mono-mp3'}) async {
    if (_cacheDir == null) await init();
    if (_cacheDir == null) return null;

    try {
      final key = _cacheKey(text, voice, rate, pitch, format);
      final destFile = File('${_cacheDir!.path}/$key.mp3');

      // Copier le fichier source vers le cache
      final source = File(sourcePath);
      if (!await source.exists()) return null;

      await source.copy(destFile.path);

      // LRU : purger si trop d'entrées
      await _enforceMaxEntries();

      debugPrint('[TtsCache] Cached: "${text.length > 30 ? '${text.substring(0, 30)}...' : text}"');
      return destFile.path;
    } catch (e) {
      debugPrint('[TtsCache] Erreur mise en cache : $e');
      return null;
    }
  }

  /// Supprime les entrées expirées du cache.
  Future<void> _purgeExpired() async {
    if (_cacheDir == null) return;
    try {
      final now = DateTime.now();
      await for (final entity in _cacheDir!.list()) {
        if (entity is File && entity.path.endsWith('.mp3')) {
          final stat = await entity.stat();
          final age = now.difference(stat.modified);
          if (age.inHours >= _ttlHours) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('[TtsCache] Purge error: $e');
    }
  }

  /// Maintient le cache en dessous de _maxEntries en supprimant les plus anciens.
  Future<void> _enforceMaxEntries() async {
    if (_cacheDir == null) return;
    try {
      final files = <_CacheFileEntry>[];
      await for (final entity in _cacheDir!.list()) {
        if (entity is File && entity.path.endsWith('.mp3')) {
          final stat = await entity.stat();
          files.add(_CacheFileEntry(path: entity.path, modified: stat.modified));
        }
      }

      if (files.length < _maxEntries) return;

      // Trier par date de modification (plus ancien d'abord)
      files.sort((a, b) => a.modified.compareTo(b.modified));

      // Supprimer les plus anciens
      final toDelete = files.length - _maxEntries + 1;
      for (var i = 0; i < toDelete && i < files.length; i++) {
        await File(files[i].path).delete();
      }
    } catch (e) {
      debugPrint('[TtsCache] Enforce max entries error: $e');
    }
  }

  /// Vide tout le cache.
  Future<void> clear() async {
    if (_cacheDir == null) return;
    try {
      await for (final entity in _cacheDir!.list()) {
        if (entity is File) {
          await entity.delete();
        }
      }
      debugPrint('[TtsCache] Cache vidé');
    } catch (e) {
      debugPrint('[TtsCache] Clear error: $e');
    }
  }

  /// Taille du cache en nombre de fichiers.
  Future<int> get size async {
    if (_cacheDir == null) return 0;
    var count = 0;
    await for (final entity in _cacheDir!.list()) {
      if (entity is File && entity.path.endsWith('.mp3')) count++;
    }
    return count;
  }
}

class _CacheFileEntry {
  final String path;
  final DateTime modified;
  const _CacheFileEntry({required this.path, required this.modified});
}