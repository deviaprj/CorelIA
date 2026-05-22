import 'dart:collection';
import 'dart:math' as math;

/// Decision du VAD prosodique.
enum SpeechFinalDecision {
  /// En attente — pas encore assez de silence ou de signal.
  waiting,

  /// Pause respiratoire — l'utilisateur reprendra probablement.
  breathingPause,

  /// Fin de phrase detectee — l'utilisateur a termine.
  endOfPhrase,
}

/// Echantillon de niveau sonore avec timestamp.
class _MicSample {
  final DateTime timestamp;
  final double level;
  _MicSample(this.timestamp, this.level);
}

/// Analyseur VAD prosodique qui distingue une pause respiratoire
/// d'une fin de phrase reelle en combinant :
/// - Niveau sonore (micLevel) et sa decroissance
/// - Presence/absence de ponctuation finale
/// - Cadence des mises a jour de transcript
/// - Duree totale de l'utterance
///
/// Contrainte : speech_to_text ne donne pas acces au buffer audio brut.
/// On utilise onSoundLevelChange comme proxy d'energie vocale.
class ProsodyVadAnalyzer {
  /// Silence minimum si ponctuation finale detectee.
  final Duration minSilenceWithPunctuation;

  /// Silence minimum sans ponctuation finale.
  final Duration minSilenceWithoutPunctuation;

  /// Seuil de chute d'energie relative au pic recent (0.0 - 1.0).
  final double energyDropThreshold;

  /// Taille du ring buffer d'historique mic.
  final int micHistorySize;

  /// Duree maximale d'une utterance (safety cap).
  final Duration maxUtteranceDuration;

  /// Duree de silence pour considerer une pause respiratoire.
  final Duration breathingPauseThreshold;

  /// Duree pendant laquelle l'energie doit rester basse apres une chute.
  final Duration sustainedLowEnergyDuration;

  ProsodyVadAnalyzer({
    this.minSilenceWithPunctuation = const Duration(milliseconds: 400),
    this.minSilenceWithoutPunctuation = const Duration(milliseconds: 900),
    this.energyDropThreshold = 0.15,
    this.micHistorySize = 20,
    this.maxUtteranceDuration = const Duration(seconds: 12),
    this.breathingPauseThreshold = const Duration(milliseconds: 200),
    this.sustainedLowEnergyDuration = const Duration(milliseconds: 300),
  });

  final Queue<_MicSample> _micHistory = Queue<_MicSample>();
  DateTime? _utteranceStart;
  DateTime? _lastTranscriptUpdate;
  String _lastTranscript = '';
  bool _hasFinalPunctuation = false;

  /// Notifie l'analyseur d'un nouveau niveau sonore (0.0 - 1.0).
  void onSoundLevelChange(double level) {
    final now = DateTime.now();
    _micHistory.addLast(_MicSample(now, level));
    while (_micHistory.length > micHistorySize) {
      _micHistory.removeFirst();
    }
  }

  /// Notifie l'analyseur d'une mise a jour du transcript.
  void onTranscriptUpdate(String transcript, {bool isFinal = false}) {
    final now = DateTime.now();
    _utteranceStart ??= now;
    _lastTranscriptUpdate = now;
    _lastTranscript = transcript;
    _hasFinalPunctuation = RegExp(r'[.!?;。！？；]\s*$').hasMatch(transcript.trim());
  }

  /// Evalue l'etat actuel et retourne une decision VAD.
  SpeechFinalDecision evaluate() {
    final now = DateTime.now();

    // Pas encore commence a parler
    if (_utteranceStart == null || _lastTranscriptUpdate == null) {
      return SpeechFinalDecision.waiting;
    }

    // Safety cap : utterance trop longue
    final utteranceDuration = now.difference(_utteranceStart!);
    if (utteranceDuration > maxUtteranceDuration) {
      return SpeechFinalDecision.endOfPhrase;
    }

    final silence = now.difference(_lastTranscriptUpdate!);

    // 1. Ponctuation finale + silence suffisant
    if (_hasFinalPunctuation && silence >= minSilenceWithPunctuation) {
      return SpeechFinalDecision.endOfPhrase;
    }

    // 2. Pas de ponctuation + silence prolonge
    if (!_hasFinalPunctuation && silence >= minSilenceWithoutPunctuation) {
      return SpeechFinalDecision.endOfPhrase;
    }

    // 3. Decroissance d'energie prolongee
    if (_micHistory.length >= 3) {
      final recentPeak = _recentPeakLevel();
      if (recentPeak > 0.05) {
        final lowEnergySamples = _micHistory
            .where((s) => s.level < recentPeak * energyDropThreshold)
            .toList();
        if (lowEnergySamples.length >= 2) {
          final lowDuration = now.difference(lowEnergySamples.first.timestamp);
          if (lowDuration >= sustainedLowEnergyDuration) {
            return SpeechFinalDecision.endOfPhrase;
          }
        }
      }
    }

    // 4. Pause respiratoire : silence court avec energie transitoire
    if (silence >= breathingPauseThreshold && silence < minSilenceWithPunctuation) {
      if (_hasFinalPunctuation) {
        return SpeechFinalDecision.breathingPause;
      }
      // Sans ponctuation : breathing seulement si energie monte a nouveau
      final levels = _micHistory.map((s) => s.level).toList();
      if (levels.length >= 3) {
        final last = levels.last;
        final prev = levels[levels.length - 2];
        if (last > prev && last > 0.05) {
          return SpeechFinalDecision.breathingPause;
        }
      }
    }

    return SpeechFinalDecision.waiting;
  }

  /// Retourne le pic d'energie sur les 500 dernieres millisecondes.
  double _recentPeakLevel() {
    if (_micHistory.isEmpty) return 0.0;
    final now = DateTime.now();
    final recentSamples = _micHistory
        .where((s) => now.difference(s.timestamp).inMilliseconds <= 500)
        .toList();
    if (recentSamples.isEmpty) return 0.0;
    return recentSamples.map((s) => s.level).reduce(math.max);
  }

  /// Reset complet pour la prochaine utterance.
  void reset() {
    _micHistory.clear();
    _utteranceStart = null;
    _lastTranscriptUpdate = null;
    _lastTranscript = '';
    _hasFinalPunctuation = false;
  }
}
