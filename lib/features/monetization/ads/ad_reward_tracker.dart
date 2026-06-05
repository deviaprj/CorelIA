import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Algorithme optimal de frequence publicitaire recompensee.
///
/// Objectif : maximiser le revenu publicitaire sans irriter l'utilisateur.
/// Principe : courbe progressive — les premieres videos sont "bon marche",
/// puis le cout augmente pour encourager le passage Pro.
///
/// Niveaux (algorithme optimal) :
/// - Tier 0 (0-4 videos vues) : 1 video = +5 messages  (5 bonus possibles)
/// - Tier 1 (5-9 videos vues)  : 2 videos = +5 messages (5 bonus possibles)
/// - Tier 2 (10+ videos vues)   : 3 videos = +5 messages (hard cap)
///
/// Reset quotidien a minuit + timer anti-spam 30s entre videos.
class AdRewardTracker {
  static const String _prefsKeyVideosWatched = 'ad_videos_watched_today';
  static const String _prefsKeyDate = 'ad_videos_date';
  static const String _prefsKeyLastWatchTime = 'ad_last_watch_time_ms';

  static const int _antiSpamSeconds = 30;
  static const int _bonusMessages = 5;

  static const List<int> _tierThresholds = [0, 5, 10];
  static const List<int> _videosRequiredPerTier = [1, 2, 3];

  /// Nombre de videos visionnees aujourd'hui.
  Future<int> getVideosWatchedToday() async {
    await _resetIfNewDay();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsKeyVideosWatched) ?? 0;
  }

  /// Combien de videos sont necessaires pour obtenir le prochain bonus.
  Future<int> getRequiredVideosForNextBonus() async {
    final watched = await getVideosWatchedToday();
    final tier = _tierFromVideos(watched);
    return _videosRequiredPerTier[tier];
  }

  /// Tier actuel (0, 1 ou 2) en fonction du nombre de videos vues.
  int _tierFromVideos(int watched) {
    for (var i = _tierThresholds.length - 1; i >= 0; i--) {
      if (watched >= _tierThresholds[i]) return i;
    }
    return 0;
  }

  /// Enregistre qu'une video a ete completement visionnee.
  Future<void> recordVideoWatched() async {
    await _resetIfNewDay();
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_prefsKeyVideosWatched) ?? 0;
    final updated = current + 1;
    await prefs.setInt(_prefsKeyVideosWatched, updated);
    await prefs.setInt(
      _prefsKeyLastWatchTime,
      DateTime.now().millisecondsSinceEpoch,
    );
    debugPrint('[AdRewardTracker] Videos vues aujourdhui : $updated');
  }

  /// Verifie si l'utilisateur peut regarder une video (anti-spam).
  Future<bool> canWatchVideo() async {
    final remaining = await getSecondsUntilNextVideo();
    return remaining <= 0;
  }

  /// Secondes restantes avant de pouvoir regarder la prochaine video.
  Future<int> getSecondsUntilNextVideo() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_prefsKeyLastWatchTime);
    if (lastMs == null) return 0;

    final elapsed = DateTime.now().millisecondsSinceEpoch - lastMs;
    final remaining = _antiSpamSeconds * 1000 - elapsed;
    return remaining > 0 ? (remaining / 1000).ceil() : 0;
  }

  /// Texte decrivant le cout actuel pour l'UI.
  Future<String> getCostLabel() async {
    final required = await getRequiredVideosForNextBonus();
    if (required == 1) return '1 video';
    return '$required videos';
  }

  /// Texte decrivant le bonus pour l'UI.
  String getBonusLabel() => '+$_bonusMessages messages';

  /// Reset complet (achat Pro ou debug).
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyVideosWatched, 0);
    await prefs.remove(_prefsKeyLastWatchTime);
  }

  Future<void> _resetIfNewDay() async {
    final prefs = await SharedPreferences.getInstance();
    final storedDate = prefs.getString(_prefsKeyDate);
    final today = _todayString();

    if (storedDate != today) {
      await prefs.setInt(_prefsKeyVideosWatched, 0);
      await prefs.setString(_prefsKeyDate, today);
      await prefs.remove(_prefsKeyLastWatchTime);
      debugPrint('[AdRewardTracker] Reset quotidien effectue.');
    }
  }

  static String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
