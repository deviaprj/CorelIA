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

/// Paramètres recommandés pour un modèle selon le type de tâche.
class ModelParams {
  final double temperature;
  final int maxTokens;
  final bool enableThinking;

  const ModelParams({
    this.temperature = 0.7,
    this.maxTokens = 4096,
    this.enableThinking = false,
  });
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
      'deepseek-reasoner',
      'deepseek/deepseek-r1:free',
      'deepseek-v4-pro',
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
    List<String>? attachmentTypes,
  }) {
    // Routage prioritaire par type de pièce jointe
    if (attachmentTypes != null && attachmentTypes.isNotEmpty) {
      if (attachmentTypes.any((t) => t == 'image')) return TaskType.vision;
      if (attachmentTypes.any((t) => t == 'pdf' || t == 'document' || t == 'spreadsheet' || t == 'presentation')) {
        return TaskType.document;
      }
      if (attachmentTypes.any((t) => t == 'text')) return TaskType.longFile;
    }

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
      return entry;
    }

    // Dernier recours : deepseek-v4-pro
    return _registry['deepseek-v4-pro'];
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

  // ── Complex task detection (cost optimization) ───────────────────────────

  /// Version enrichie de [classifyTask] qui détecte les tâches complexes
  /// nécessitant deepseek-v4-pro ou le mode thinking.
  static TaskType classifyTaskEnhanced(
    String message, {
    bool hasImage = false,
    bool hasFile = false,
    bool isDocGen = false,
    List<String>? attachmentTypes,
  }) {
    // Routage prioritaire inchangé (pièces jointes)
    if (attachmentTypes != null && attachmentTypes.isNotEmpty) {
      if (attachmentTypes.any((t) => t == 'image')) return TaskType.vision;
      if (attachmentTypes.any((t) => t == 'pdf' || t == 'document' || t == 'spreadsheet' || t == 'presentation')) {
        return TaskType.document;
      }
      if (attachmentTypes.any((t) => t == 'text')) return TaskType.longFile;
    }

    if (hasImage) return TaskType.vision;
    if (isDocGen) return TaskType.document;
    if (hasFile) return TaskType.longFile;

    final lower = message.toLowerCase();

    // Deep reasoning → thinking ON (deepseek-reasoner)
    if (_isDeepReasoningPrompt(lower)) return TaskType.reasoning;

    // Complex tasks → deepseek-v4-pro (document routing)
    if (_isDocumentGenerationPrompt(lower) ||
        _isExtractionPrompt(lower) ||
        _isMultiStepAction(lower)) {
      return TaskType.document;
    }

    // Fallback sur la classification existante
    if (_containsCodeKeywords(lower)) return TaskType.code;
    if (_containsReasoningKeywords(lower)) return TaskType.reasoning;
    return TaskType.general;
  }

  /// Résout les paramètres (température, tokens, thinking) pour un type de tâche.
  static ModelParams resolveParams(TaskType taskType) {
    switch (taskType) {
      case TaskType.reasoning:
        return const ModelParams(
          temperature: 0.7,
          maxTokens: 4096,
          enableThinking: true,
        );
      case TaskType.document:
      case TaskType.longFile:
      case TaskType.code:
        return const ModelParams(
          temperature: 0.7,
          maxTokens: 4096,
          enableThinking: false,
        );
      case TaskType.vocal:
      case TaskType.vocalFast:
        return const ModelParams(
          temperature: 0.95,
          maxTokens: 2048,
          enableThinking: false,
        );
      case TaskType.vision:
        return const ModelParams(
          temperature: 0.7,
          maxTokens: 4096,
          enableThinking: false,
        );
      case TaskType.general:
        return const ModelParams(
          temperature: 0.7,
          maxTokens: 4096,
          enableThinking: false,
        );
    }
  }

  static bool _isDocumentGenerationPrompt(String text) {
    const markers = [
      'genere un document', 'génère un document', 'generate a document',
      'redige un document', 'rédige un document', 'write a document',
      'docgen', 'document complet', 'complete document',
      'rapport detaille', 'rapport détaillé', 'detailed report',
      'mémoire', 'memoire', 'these', 'thèse', 'dissertation',
    ];
    return markers.any((m) => text.contains(m));
  }

  static bool _isExtractionPrompt(String text) {
    const markers = [
      'nettoie et structure le texte extrait', 'clean and structure the extracted text',
      'extrait suivant', 'extracted text', '/extract',
      'analyse ce contenu', 'analyze this content',
      'resume et structure', 'résume et structure',
      'synthese de', 'synthèse de', 'summary of',
    ];
    return markers.any((m) => text.contains(m));
  }

  static bool _isMultiStepAction(String text) {
    const stepMarkers = [
      'etape 1', 'étape 1', 'step 1', 'phase 1',
      'd\'abord', 'ensuite', 'puis', 'finalement',
      'first', 'then', 'next', 'after that', 'finally',
      'planifie', 'organise', 'coordonne',
      'multi-step', 'plusieurs etapes', 'plusieurs étapes',
    ];
    final hasSteps = stepMarkers.any((m) => text.contains(m));

    const actionVerbs = [
      'trouve', 'cherche', 'recherche', 'reserve', 'réserve', 'achete', 'achète',
      'planifie', 'organise', 'coordonne', 'genere', 'génère', 'redige', 'rédige',
      'find', 'search', 'book', 'buy', 'plan', 'organize', 'generate', 'write',
    ];
    var verbCount = 0;
    for (final verb in actionVerbs) {
      if (text.contains(verb)) verbCount++;
    }

    return hasSteps || verbCount >= 3;
  }

  static bool _isDeepReasoningPrompt(String text) {
    const markers = [
      'prouve', 'prove', 'démonstration', 'demonstration',
      'theorem', 'théorème', 'axiome', 'proof',
      'raisonnement pas a pas', 'raisonnement pas à pas', 'step by step reasoning',
      'chaine de pensee', 'chaîne de pensée', 'chain of thought',
      'explique ton raisonnement', 'explain your reasoning',
      'démontre', 'demontre', 'démontrer', 'demontrer',
    ];
    return markers.any((m) => text.contains(m));
  }

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