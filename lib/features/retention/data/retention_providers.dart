import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'streak_service.dart';
import 'user_profile_service.dart';
import 'usage_stats_service.dart';
import 'daily_question_service.dart';

/// Provider pour le service de streak.
final streakServiceProvider = Provider<StreakService>((ref) => StreakService());

/// Provider pour le service de profil utilisateur.
final userProfileServiceProvider = Provider<UserProfileService>(
    (ref) => UserProfileService());

/// Provider pour le service de statistiques d'usage.
final usageStatsServiceProvider = Provider<UsageStatsService>(
    (ref) => UsageStatsService());

/// Provider pour le service de question quotidienne.
final dailyQuestionServiceProvider = Provider<DailyQuestionService>(
    (ref) => DailyQuestionService());

/// Provider async pour les donnees de streak.
final streakDataProvider = FutureProvider<StreakData>((ref) async {
  return ref.read(streakServiceProvider).getStreakData();
});

/// Provider async pour les statistiques d'usage.
final usageStatsProvider = FutureProvider<UsageStats>((ref) async {
  return ref.read(usageStatsServiceProvider).getStats();
});

/// Provider async pour le profil utilisateur.
final userNameProvider = FutureProvider<String?>((ref) async {
  return ref.read(userProfileServiceProvider).getName();
});

/// Provider async pour les sujets favoris.
final userInterestsProvider = FutureProvider<List<String>>((ref) async {
  return ref.read(userProfileServiceProvider).getInterests();
});
