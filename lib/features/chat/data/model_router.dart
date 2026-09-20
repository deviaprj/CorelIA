import '../../../core/config/app_config.dart';

/// Types de tâches qui influencent le choix du modèle.
enum TaskType { general, reasoning, vision }

/// Métadonnées d'un modèle dans la table de routage.
class ModelEntry {
  const ModelEntry({
    required this.modelId,
    required this.provider,
    this.isFree = false,
    this.supportsVision = false,
  });

  final String modelId;
  final String provider; // 'deepseek' | 'openrouter'
  final bool isFree;
  final bool supportsVision;
}

/// Paramètres de génération recommandés pour un type de tâche.
class ModelParams {
  const ModelParams({this.temperature = 0.7, this.maxTokens = AppConfig.maxTokens});

  final double temperature;
  final int maxTokens;
}

/// Suivi des cooldowns après un rate-limit (HTTP 429).
class RateLimitTracker {
  final Map<String, DateTime> _cooldownUntil = {};

  bool isCoolingDown(String modelId) {
    final until = _cooldownUntil[modelId];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _cooldownUntil.remove(modelId);
      return false;
    }
    return true;
  }

  void setCooldown(String modelId, {Duration duration = const Duration(minutes: 5)}) {
    _cooldownUntil[modelId] = DateTime.now().add(duration);
  }
}

/// Routage du modèle selon la tâche et le rôle de l'utilisateur.
abstract class ModelRouter {
  static final rateLimiter = RateLimitTracker();

  static const _registry = <String, ModelEntry>{
    AppConfig.deepSeekModel: ModelEntry(
      modelId: AppConfig.deepSeekModel,
      provider: 'deepseek',
      isFree: true,
    ),
    AppConfig.deepSeekProModel: ModelEntry(
      modelId: AppConfig.deepSeekProModel,
      provider: 'deepseek',
      isFree: true,
    ),
    AppConfig.deepSeekReasonerModel: ModelEntry(
      modelId: AppConfig.deepSeekReasonerModel,
      provider: 'deepseek',
      isFree: true,
    ),
    AppConfig.deepSeekVisionModel: ModelEntry(
      modelId: AppConfig.deepSeekVisionModel,
      provider: 'deepseek',
      isFree: true,
      supportsVision: true,
    ),
    AppConfig.openRouterVisionModel: ModelEntry(
      modelId: AppConfig.openRouterVisionModel,
      provider: 'openrouter',
      supportsVision: true,
    ),
    AppConfig.openRouterGpt4oMini: ModelEntry(
      modelId: AppConfig.openRouterGpt4oMini,
      provider: 'openrouter',
      supportsVision: true,
    ),
  };

  static const _routingTable = <TaskType, List<String>>{
    TaskType.general: [AppConfig.deepSeekModel, AppConfig.deepSeekProModel],
    TaskType.reasoning: [
      AppConfig.deepSeekReasonerModel,
      AppConfig.deepSeekProModel,
    ],
    TaskType.vision: [
      AppConfig.deepSeekVisionModel,
      AppConfig.openRouterVisionModel,
      AppConfig.openRouterGpt4oMini,
    ],
  };

  /// Classe le message utilisateur en type de tâche.
  static TaskType classifyTask(String message, {bool hasImage = false}) {
    if (hasImage) return TaskType.vision;
    final lower = message.toLowerCase();
    if (_reasoningMarkers.any(lower.contains)) return TaskType.reasoning;
    return TaskType.general;
  }

  /// Meilleur modèle disponible pour une tâche.
  ///
  /// [isFull] : si faux, les modèles payants sont exclus de la chaîne.
  static ModelEntry? resolveModel(
    TaskType taskType, {
    String? userOverride,
    bool isFull = true,
  }) {
    if (userOverride != null && _registry.containsKey(userOverride)) {
      final entry = _registry[userOverride]!;
      if (!rateLimiter.isCoolingDown(userOverride) && (isFull || entry.isFree)) {
        return entry;
      }
    }

    final chain = _routingTable[taskType] ?? _routingTable[TaskType.general]!;
    for (final modelId in chain) {
      final entry = _registry[modelId];
      if (entry == null || rateLimiter.isCoolingDown(modelId)) continue;
      if (!isFull && !entry.isFree) continue;
      return entry;
    }
    return null;
  }

  static ModelParams resolveParams(TaskType taskType) => switch (taskType) {
        TaskType.reasoning =>
          const ModelParams(temperature: 0.7, maxTokens: AppConfig.maxTokens),
        TaskType.vision =>
          const ModelParams(temperature: 0.5, maxTokens: AppConfig.maxTokens),
        TaskType.general =>
          const ModelParams(temperature: 0.7, maxTokens: AppConfig.maxTokens),
      };

  static void markRateLimited(String modelId) {
    final entry = _registry[modelId];
    rateLimiter.setCooldown(
      modelId,
      duration: (entry?.isFree ?? false)
          ? const Duration(minutes: 5)
          : const Duration(minutes: 1),
    );
  }

  static const _reasoningMarkers = [
    'analyse', 'analyser', 'raisonne', 'raisonnement', 'démontre', 'demontre',
    'prouve', 'preuve', 'logique', 'étape par étape', 'etape par etape',
    'compare', 'compare ces', 'pourquoi', 'explique pourquoi',
    'analyze', 'reason', 'prove', 'step by step', 'compare', 'why',
  ];
}
