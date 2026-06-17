import 'package:shared_preferences/shared_preferences.dart';

/// Service de statistiques d'usage pour motiver l'utilisateur.
///
/// Tracks :
/// - Total de messages envoyes
/// - Temps estime economise (hypothese : 2 min par requete IA vs recherche manuelle)
/// - Jours d'utilisation
/// - Series en cours
class UsageStatsService {
  static const String _prefsKeyTotalMessages = 'stats_total_messages';
  static const String _prefsKeyDaysUsed = 'stats_days_used';
  static const String _prefsKeyLastUsed = 'stats_last_used';
  static const String _prefsKeyTimeSaved = 'stats_time_saved_minutes';
  static const String _prefsKeyConversationsStarted = 'stats_conversations_started';

  /// Temps moyen economise par requete (en minutes).
  static const double _timeSavedPerMessage = 2.0;

  /// Enregistre qu'un message a ete envoye.
  Future<void> recordMessageSent() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_prefsKeyTotalMessages) ?? 0;
    await prefs.setInt(_prefsKeyTotalMessages, current + 1);

    final timeSaved = (prefs.getDouble(_prefsKeyTimeSaved) ?? 0) + _timeSavedPerMessage;
    await prefs.setDouble(_prefsKeyTimeSaved, timeSaved);

    await _updateDaysUsed(prefs);
  }

  /// Enregistre le demarrage d'une nouvelle conversation.
  Future<void> recordConversationStarted() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_prefsKeyConversationsStarted) ?? 0;
    await prefs.setInt(_prefsKeyConversationsStarted, current + 1);
  }

  /// Retourne les statistiques actuelles.
  Future<UsageStats> getStats() async {
    final prefs = await SharedPreferences.getInstance();
    return UsageStats(
      totalMessages: prefs.getInt(_prefsKeyTotalMessages) ?? 0,
      daysUsed: prefs.getInt(_prefsKeyDaysUsed) ?? 0,
      timeSavedMinutes: prefs.getDouble(_prefsKeyTimeSaved) ?? 0,
      conversationsStarted: prefs.getInt(_prefsKeyConversationsStarted) ?? 0,
    );
  }

  Future<void> _updateDaysUsed(SharedPreferences prefs) async {
    final lastUsed = prefs.getString(_prefsKeyLastUsed);
    final now = DateTime.now();

    if (lastUsed != null) {
      final lastDate = DateTime.parse(lastUsed);
      if (lastDate.year == now.year &&
          lastDate.month == now.month &&
          lastDate.day == now.day) {
        return; // Deja compte aujourd'hui
      }
    }

    final currentDays = prefs.getInt(_prefsKeyDaysUsed) ?? 0;
    await prefs.setInt(_prefsKeyDaysUsed, currentDays + 1);
    await prefs.setString(_prefsKeyLastUsed, now.toIso8601String());
  }

  /// Reset complet (debug).
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyTotalMessages);
    await prefs.remove(_prefsKeyDaysUsed);
    await prefs.remove(_prefsKeyLastUsed);
    await prefs.remove(_prefsKeyTimeSaved);
    await prefs.remove(_prefsKeyConversationsStarted);
  }
}

class UsageStats {
  final int totalMessages;
  final int daysUsed;
  final double timeSavedMinutes;
  final int conversationsStarted;

  const UsageStats({
    required this.totalMessages,
    required this.daysUsed,
    required this.timeSavedMinutes,
    required this.conversationsStarted,
  });

  /// Temps economise formate en heures et minutes.
  String get timeSavedFormatted {
    final hours = timeSavedMinutes ~/ 60;
    final minutes = (timeSavedMinutes % 60).toInt();
    if (hours > 0) {
      return '$hours h $minutes min';
    }
    return '$minutes min';
  }

  /// Texte de motivation pour l'UI.
  String get motivationMessage {
    if (totalMessages >= 100) {
      return 'Tu as economise $timeSavedFormatted de recherche ! 🎉';
    }
    if (totalMessages >= 50) {
      return 'Plus de 50 conversations avec Corely. Continue comme ca ! 🔥';
    }
    if (totalMessages >= 20) {
      return 'Tu commences a maitriser Corely. $timeSavedFormatted economises !';
    }
    if (totalMessages >= 5) {
      return 'Deja $totalMessages messages. Pas mal !';
    }
    return 'Pose-moi ta premiere question !';
  }
}
