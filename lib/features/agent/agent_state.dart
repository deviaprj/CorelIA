/// Etat du mode agent autonome.
///
/// La machine a etats : idle → planning → executing → verifying → reporting → idle
enum AgentPhase {
  idle,
  planning,
  executing,
  verifying,
  reporting,
  error,
}

/// Une etape du plan d'execution.
class AgentStep {
  final String id;
  final String description;
  final String toolId;
  final Map<String, dynamic> params;
  final AgentStepStatus status;
  final String? resultSummary;
  final String? error;

  const AgentStep({
    required this.id,
    required this.description,
    required this.toolId,
    this.params = const {},
    this.status = AgentStepStatus.pending,
    this.resultSummary,
    this.error,
  });

  AgentStep copyWith({
    String? id,
    String? description,
    String? toolId,
    Map<String, dynamic>? params,
    AgentStepStatus? status,
    String? resultSummary,
    String? error,
  }) =>
      AgentStep(
        id: id ?? this.id,
        description: description ?? this.description,
        toolId: toolId ?? this.toolId,
        params: params ?? this.params,
        status: status ?? this.status,
        resultSummary: resultSummary ?? this.resultSummary,
        error: error,
      );
}

enum AgentStepStatus {
  pending,
  running,
  completed,
  failed,
  skipped,
}

/// Etat complet d'une session agent.
class AgentState {
  final String sessionId;
  final AgentPhase phase;
  final String goal;
  final List<AgentStep> plan;
  final int currentStepIndex;
  final int retryCount;
  final String? reportContent;
  final String? reportFormat;
  final String? error;

  static const int maxRetries = 3;

  const AgentState({
    required this.sessionId,
    this.phase = AgentPhase.idle,
    this.goal = '',
    this.plan = const [],
    this.currentStepIndex = 0,
    this.retryCount = 0,
    this.reportContent,
    this.reportFormat,
    this.error,
  });

  AgentState copyWith({
    String? sessionId,
    AgentPhase? phase,
    String? goal,
    List<AgentStep>? plan,
    int? currentStepIndex,
    int? retryCount,
    String? reportContent,
    String? reportFormat,
    String? error,
  }) =>
      AgentState(
        sessionId: sessionId ?? this.sessionId,
        phase: phase ?? this.phase,
        goal: goal ?? this.goal,
        plan: plan ?? this.plan,
        currentStepIndex: currentStepIndex ?? this.currentStepIndex,
        retryCount: retryCount ?? this.retryCount,
        reportContent: reportContent ?? this.reportContent,
        reportFormat: reportFormat ?? this.reportFormat,
        error: error,
      );

  AgentStep? get currentStep =>
      plan.isNotEmpty && currentStepIndex < plan.length
          ? plan[currentStepIndex]
          : null;

  int get totalSteps => plan.length;
  int get completedSteps =>
      plan.where((s) => s.status == AgentStepStatus.completed).length;
  int get failedSteps =>
      plan.where((s) => s.status == AgentStepStatus.failed).length;
  double get progress =>
      totalSteps > 0 ? completedSteps / totalSteps : 0.0;
  bool get isComplete => phase == AgentPhase.reporting;
  bool get canRetry => retryCount < maxRetries;

  // Nom lisible de la phase
  String get phaseLabel => switch (phase) {
        AgentPhase.idle => 'En attente',
        AgentPhase.planning => 'Planification...',
        AgentPhase.executing => 'Execution (${completedSteps}/${totalSteps})',
        AgentPhase.verifying => 'Verification...',
        AgentPhase.reporting => 'Rapport final',
        AgentPhase.error => 'Erreur',
      };
}
