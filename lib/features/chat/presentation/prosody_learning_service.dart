import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_emotion.dart';

/// Service d'apprentissage de la prosodie TTS.
///
/// Apprend les préférences de l'utilisateur au fil du temps :
/// - Vitesse de parole par émotion
/// - Hauteur (pitch) par émotion
/// - Fréquence d'hésitations
/// - Satisfaction implicite (barge-in = mauvaise prosodie)
///
/// Les données sont stockées localement (SharedPreferences) et
/// synchronisées vers Firestore si l'utilisateur a consenti
/// (via ConsentDataService, niveau 2).
class ProsodyLearningService {
  static const String _prefsPrefix = 'prosody_';
  static const double _minRate = 0.35;
  static const double _maxRate = 1.30;
  static const double _minPitch = 0.5;
  static const double _maxPitch = 2.0;
  static const double _adjustmentStep = 0.03; // 3% per event
  static const double _maxDeviation = 0.15; // max ±15% from base

  // ── Public API ────────────────────────────────────────────────────────────

  /// Retourne la config TTS pour une émotion, ajustée par l'apprentissage.
  Future<EmotionTtsConfig> getConfigForEmotion(TtsEmotion emotion) async {
    final base = emotionTtsConfigs[emotion] ?? emotionTtsConfigs[TtsEmotion.neutral]!;
    final adjustedRate = await _getAdjustedRate(emotion, base.rate);
    final adjustedPitch = await _getAdjustedPitch(emotion, base.pitch);
    return EmotionTtsConfig(rate: adjustedRate, pitch: adjustedPitch);
  }

  /// Retourne l'intensité d'hésitation préférée (0.0 - 1.0).
  Future<double> getHesitationIntensity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('${_prefsPrefix}hesitation_intensity') ?? 0.25;
  }

  /// Enregistre un barge-in (interruption pendant TTS) pour une émotion.
  /// Interprété comme "la prosodie était mauvaise" → ralentir légèrement.
  Future<void> recordBargeIn(TtsEmotion emotion) async {
    final prefs = await SharedPreferences.getInstance();
    final keyBarge = '${_prefsPrefix}bargein_${emotion.name}';
    final keyComplete = '${_prefsPrefix}complete_${emotion.name}';

    final bargeCount = (prefs.getInt(keyBarge) ?? 0) + 1;
    final completeCount = prefs.getInt(keyComplete) ?? 0;
    await prefs.setInt(keyBarge, bargeCount);

    // Ajustement basé sur le ratio barge/complete
    final total = bargeCount + completeCount;
    if (total >= 3) {
      final ratio = bargeCount / total;
      final currentRate = await _getAdjustedRate(emotion, _baseRate(emotion));
      if (ratio > 0.5) {
        // Trop de barge-in → ralentir
        await _setAdjustedRate(emotion, currentRate - _adjustmentStep);
        debugPrint('[ProsodyLearning] Barge-in detected for ${emotion.name} — slowing down');
      }
    }
  }

  /// Enregistre une completion TTS réussie (pas d'interruption).
  /// Interprété comme "la prosodie était bonne" → confirmer/rester stable.
  Future<void> recordCompletion(TtsEmotion emotion) async {
    final prefs = await SharedPreferences.getInstance();
    final keyComplete = '${_prefsPrefix}complete_${emotion.name}';
    final completeCount = (prefs.getInt(keyComplete) ?? 0) + 1;
    await prefs.setInt(keyComplete, completeCount);

    // Si beaucoup de completions consécutives sans barge-in,
    // on peut légèrement augmenter la confiance (mais pas la vitesse)
    final keyBarge = '${_prefsPrefix}bargein_${emotion.name}';
    final bargeCount = prefs.getInt(keyBarge) ?? 0;
    final total = completeCount + bargeCount;
    if (total >= 5 && bargeCount == 0) {
      // Utilisateur très satisfait → on peut augmenter légèrement la vitesse
      // mais très prudemment (+1%)
      final currentRate = await _getAdjustedRate(emotion, _baseRate(emotion));
      await _setAdjustedRate(emotion, currentRate + 0.01);
      debugPrint('[ProsodyLearning] High completion rate for ${emotion.name} — slight speed up');
    }
  }

  /// Enregistre un changement manuel de vitesse par l'utilisateur.
  Future<void> recordManualSpeedChange(double speed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${_prefsPrefix}manual_speed', speed.clamp(_minRate, _maxRate));
    debugPrint('[ProsodyLearning] Manual speed preference: $speed');
  }

  /// Enregistre un changement manuel de pitch par l'utilisateur.
  Future<void> recordManualPitchChange(double pitch) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${_prefsPrefix}manual_pitch', pitch.clamp(_minPitch, _maxPitch));
  }

  /// Met à jour l'intensité d'hésitation préférée.
  Future<void> setHesitationIntensity(double intensity) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${_prefsPrefix}hesitation_intensity', intensity.clamp(0.0, 1.0));
  }

  /// Reset tout l'apprentissage (debug).
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefsPrefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<double> _getAdjustedRate(TtsEmotion emotion, double baseRate) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_prefsPrefix}rate_${emotion.name}';
    final stored = prefs.getDouble(key);
    if (stored != null) return stored.clamp(_minRate, _maxRate);
    return baseRate.clamp(_minRate, _maxRate);
  }

  Future<void> _setAdjustedRate(TtsEmotion emotion, double rate) async {
    final prefs = await SharedPreferences.getInstance();
    final base = _baseRate(emotion);
    final deviation = rate - base;
    final clampedDeviation = deviation.clamp(-_maxDeviation, _maxDeviation);
    final clampedRate = (base + clampedDeviation).clamp(_minRate, _maxRate);
    await prefs.setDouble('${_prefsPrefix}rate_${emotion.name}', clampedRate);
  }

  Future<double> _getAdjustedPitch(TtsEmotion emotion, double basePitch) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_prefsPrefix}pitch_${emotion.name}';
    final stored = prefs.getDouble(key);
    if (stored != null) return stored.clamp(_minPitch, _maxPitch);
    return basePitch.clamp(_minPitch, _maxPitch);
  }

  Future<void> _setAdjustedPitch(TtsEmotion emotion, double pitch) async {
    final prefs = await SharedPreferences.getInstance();
    final base = _basePitch(emotion);
    final deviation = pitch - base;
    final clampedDeviation = deviation.clamp(-_maxDeviation, _maxDeviation);
    final clampedPitch = (base + clampedDeviation).clamp(_minPitch, _maxPitch);
    await prefs.setDouble('${_prefsPrefix}pitch_${emotion.name}', clampedPitch);
  }

  double _baseRate(TtsEmotion emotion) {
    return emotionTtsConfigs[emotion]?.rate ?? emotionTtsConfigs[TtsEmotion.neutral]!.rate;
  }

  double _basePitch(TtsEmotion emotion) {
    return emotionTtsConfigs[emotion]?.pitch ?? emotionTtsConfigs[TtsEmotion.neutral]!.pitch;
  }
}
