import '../../../core/constants.dart';

/// Types de tâches influençant le choix du modèle.
enum TaskType {
  general,
  reasoning,
  vision,
  document,
  code,
  longFile,
  vocal,      // conversation vocale (jovial, rapide)
  vocalFast,   // conversation vocale rapide
}

/// Métadonnées d'un modèle dans la table de routage.
class ModelEntry {
  final String modelId;
  final String provider; // 'deepseek' ou 'openrouter'
  final bool isFree;
  final bool supportsVision;
  final bool supportsSearch;

  const ModelEntry({
    required this.modelId,
    required this.provider,
    this.isFree = false,
    this.supportsVision = false,
    this.supportsSearch = false,
  });
}

/// Suivi des cooldowns de rate-limit par modèle.
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

  /// Retourne le temps restant en secondes, ou 0 si pas en cooldown.
  int remainingSeconds(String modelId) {
    final until = _cooldownUntil[modelId];
    if (until == null) return 0;
    final diff = until.difference(DateTime.now());
    return diff.isNegative ? 0 : diff.inSeconds;
  }
}

/// Routage intelligent des modèles IA.
class ModelRouter {
  static final rateLimiter = RateLimitTracker();

  /// Registre de tous les modèles disponibles.
  static const _registry = <String, ModelEntry>{
    // DeepSeek direct API
    'deepseek-v4-flash': ModelEntry(
      modelId: 'deepseek-v4-flash',
      provider: 'deepseek',
      supportsSearch: true,
    ),
    'deepseek-v4-pro': ModelEntry(
      modelId: 'deepseek-v4-pro',
      provider: 'deepseek',
      supportsSearch: true,
    ),
    'deepseek-reasoner': ModelEntry(
      modelId: 'deepseek-reasoner',
      provider: 'deepseek',
    ),
    'deepseek-chat': ModelEntry(
      modelId: 'deepseek-chat',
      provider: 'deepseek',
      supportsVision: true,
    ),
    // OpenRouter free
    'deepseek/deepseek-r1:free': ModelEntry(
      modelId: 'deepseek/deepseek-r1:free',
      provider: 'openrouter',
      isFree: true,
    ),
    'qwen/qwen3-coder:free': ModelEntry(
      modelId: 'qwen/qwen3-coder:free',
      provider: 'openrouter',
      isFree: true,
    ),
    'mistral/mistral-7b-instruct:free': ModelEntry(
      modelId: 'mistral/mistral-7b-instruct:free',
      provider: 'openrouter',
      isFree: true,
    ),
    // OpenRouter vocal (free)
    'arcee/trinity': ModelEntry(
      modelId: 'arcee/trinity',
      provider: 'openrouter',
      isFree: true,
    ),
    'neversleep/ring-2.6-1t': ModelEntry(
      modelId: 'neversleep/ring-2.6-1t',
      provider: 'openrouter',
      isFree: true,
    ),
    // OpenRouter paid / cheap
    'google/gemini-flash-1.5': ModelEntry(
      modelId: 'google/gemini-flash-1.5',
      provider: 'openrouter',
      supportsVision: true,
    ),
    'openai/gpt-4o-mini': ModelEntry(
      modelId: 'openai/gpt-4o-mini',
      provider: 'openrouter',
      supportsVision: true,
    ),
    'mistralai/mistral-large-2407': ModelEntry(
      modelId: 'mistralai/mistral-large-2407',
      provider: 'openrouter',
    ),
  };

  /// Table de routage : tâche → chaîne de fallback ordonnée.
  static const _routingTable = <TaskType, List<String>>{
    TaskType.general: [
      'deepseek-v4-flash',
      'mistral/mistral-7b-instruct:free',
    ],
    TaskType.reasoning: [
      'deepseek-v4-pro',
      'deepseek/deepseek-r1:free',
      'deepseek-reasoner',
    ],
    TaskType.vision: [
      'google/gemini-flash-1.5',
      'deepseek-chat',
      'openai/gpt-4o-mini',
    ],
    TaskType.document: [
      'deepseek-v4-pro',
      'deepseek-v4-flash',
    ],
    TaskType.code: [
      'deepseek-v4-pro',
      'qwen/qwen3-coder:free',
      'deepseek-v4-flash',
    ],
    TaskType.longFile: [
      'deepseek-v4-pro',
      'mistral/mistral-7b-instruct:free',
    ],
    TaskType.vocal: [
      'arcee/trinity',
      'neversleep/ring-2.6-1t',
      'deepseek/deepseek-r1:free',
      'openai/gpt-4o-mini',
    ],
    TaskType.vocalFast: [
      'neversleep/ring-2.6-1t',
      'arcee/trinity',
      'deepseek/deepseek-r1:free',
      'openai/gpt-4o-mini',
    ],
  };

  /// Classifie le message utilisateur en type de tâche.
  static TaskType classifyTask(
    String message, {
    bool hasImage = false,
    bool hasFile = false,
    bool isDocGen = false,
  }) {
    if (hasImage) return TaskType.vision;
    if (isDocGen) return TaskType.document;
    if (hasFile) return TaskType.longFile;

    final lower = message.toLowerCase();
    if (_containsCodeKeywords(lower)) return TaskType.code;
    if (_containsReasoningKeywords(lower)) return TaskType.reasoning;
    return TaskType.general;
  }

  /// Résout le meilleur modèle disponible pour une tâche.
  static ModelEntry? resolveModel(
    TaskType taskType, {
    String? userOverride,
  }) {
    // Si l'utilisateur a sélectionné un modèle explicite (pas 'auto'/'task:*')
    if (userOverride != null &&
        !userOverride.startsWith('auto') &&
        !userOverride.startsWith('task:')) {
      final entry = _registry[userOverride];
      if (entry != null && !rateLimiter.isCoolingDown(userOverride)) {
        return entry;
      }
    }

    // Si l'utilisateur a forcé un type de tâche
    TaskType effectiveTask = taskType;
    if (userOverride == 'task:code') effectiveTask = TaskType.code;
    if (userOverride == 'task:vision') effectiveTask = TaskType.vision;
    if (userOverride == 'task:reasoning') effectiveTask = TaskType.reasoning;
    if (userOverride == 'task:document') effectiveTask = TaskType.document;

    final chain = _routingTable[effectiveTask] ?? _routingTable[TaskType.general]!;
    for (final modelId in chain) {
      final entry = _registry[modelId];
      if (entry == null) continue;
      if (rateLimiter.isCoolingDown(modelId)) continue;
      if (entry.provider == 'deepseek' && AppConstants.deepSeekApiKey.isEmpty) continue;
      if (entry.provider == 'openrouter' && AppConstants.openRouterApiKey.isEmpty) continue;
      return entry;
    }

    // Dernier recours : deepseek-v4-flash si la clé existe
    if (AppConstants.deepSeekApiKey.isNotEmpty) {
      return _registry['deepseek-v4-flash'];
    }
    return null;
  }

  /// Marque un modèle comme rate-limited après un 429.
  static void markRateLimited(String modelId) {
    final entry = _registry[modelId];
    final duration = (entry?.isFree ?? false)
        ? const Duration(minutes: 5)
        : const Duration(minutes: 1);
    rateLimiter.setCooldown(modelId, duration: duration);
  }

  /// Retourne l'entrée du registre pour un modelId.
  static ModelEntry? getEntry(String modelId) => _registry[modelId];

  static bool _containsCodeKeywords(String text) {
    const keywords = [
      'code', 'fonction', 'function', 'bug', 'debug', 'programmer',
      'compile', 'refactor', 'script', 'python', 'dart', 'javascript',
      'html', 'css', 'sql', 'api', 'endpoint', 'écrire un programme',
      'write a function', 'algorithme', 'algorithm', 'coder', 'codez',
      'class ', 'void ', 'async ', 'import ', 'def ', 'fn ',
    ];
    return keywords.any((k) => text.contains(k));
  }

  static bool _containsReasoningKeywords(String text) {
    const keywords = [
      'analyser', 'analyze', 'raisonner', 'reason', 'logique', 'logic',
      'prouver', 'prove', 'démontrer', 'démonstration', 'mathématique',
      'equation', 'résoudre', 'solve', 'calculer', 'pourquoi',
      'expliquer pourquoi', 'hypothèse', 'hypothesis', 'comparer',
      'compare', 'contraste', 'déduire', 'infer', 'raisonnement',
    ];
    return keywords.any((k) => text.contains(k));
  }
}