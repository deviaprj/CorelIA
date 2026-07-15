import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'agent_state.dart';
import '../../core/desktop/desktop_tool_registry.dart';
import '../../core/desktop/desktop_tool.dart';
import '../../core/desktop/permissions/desktop_permission_service.dart';
import '../../core/constants.dart';
import '../chat/data/ai_client.dart';

/// Notifier principal pour le mode agent autonome.
///
/// Orchestre la boucle Plan→Execute→Verify→Report.
/// Separe de ChatNotifier — gere son propre etat et son propre cycle.
class AgentNotifier extends FamilyNotifier<AgentState, String> {
  final _uuid = const Uuid();
  late final DeepSeekClient _aiClient;

  @override
  AgentState build(String sessionId) {
    _aiClient = DeepSeekClient(
      apiKey: AppConstants.deepSeekApiKey,
    );
    return AgentState(sessionId: sessionId);
  }

  /// Lance une tache autonome.
  Future<void> run(String goal) async {
    state = state.copyWith(
      goal: goal,
      phase: AgentPhase.planning,
      plan: [],
      currentStepIndex: 0,
      retryCount: 0,
      error: null,
    );

    try {
      await _plan();
      if (state.plan.isEmpty) {
        state = state.copyWith(
          phase: AgentPhase.error,
          error: 'Aucun plan genere',
        );
        return;
      }

      await _executeAll();
      await _verify();
      await _report();
    } catch (e) {
      if (state.canRetry) {
        state = state.copyWith(
          retryCount: state.retryCount + 1,
          phase: AgentPhase.planning,
        );
        await run(goal); // Reessayer
        return;
      }
      state = state.copyWith(
        phase: AgentPhase.error,
        error: e.toString(),
      );
    }
  }

  /// Phase PLAN : demande au LLM de decomposer le goal en etapes.
  Future<void> _plan() async {
    final tools = desktopToolRegistry.functionDefinitions;

    final planPrompt = '''
Tu es un planificateur de taches. Decompose le goal suivant en etapes concretes
utilisant les outils disponibles. Reponds UNIQUEMENT avec un JSON de ce format :
{
  "plan": [
    {
      "step": 1,
      "description": "Description de l'etape",
      "tool": "outil_id",
      "params": {"cle": "valeur"}
    }
  ]
}

Outils disponibles :
${const JsonEncoder.withIndent('  ').convert(tools)}

GOAL : $state.goal
''';

    try {
      final response = await _callLlm(planPrompt);
      final json = _extractJson(response);
      if (json != null && json['plan'] != null) {
        final steps = (json['plan'] as List).map((s) => AgentStep(
              id: 'step_${s['step']}',
              description: s['description'] as String? ?? 'Etape ${s['step']}',
              toolId: s['tool'] as String? ?? 'unknown',
              params: (s['params'] as Map<String, dynamic>?) ?? {},
            )).toList();

        state = state.copyWith(plan: steps);
      }
    } catch (e) {
      state = state.copyWith(
        phase: AgentPhase.error,
        error: 'Erreur planification : $e',
      );
    }
  }

  /// Phase EXECUTE : itere chaque etape du plan.
  Future<void> _executeAll() async {
    state = state.copyWith(phase: AgentPhase.executing);

    for (var i = 0; i < state.plan.length; i++) {
      if (state.phase == AgentPhase.error) break;

      state = state.copyWith(currentStepIndex: i);
      final step = state.plan[i];

      // Marquer en cours
      final updatedSteps = state.plan.toList();
      updatedSteps[i] = step.copyWith(status: AgentStepStatus.running);
      state = state.copyWith(plan: updatedSteps);

      // Verifier permission
      if (!desktopPermissionService.isGranted(step.toolId)) {
        final tool = desktopToolRegistry.get(step.toolId);
        if (tool != null) {
          final granted =
              await desktopPermissionService.requestPermission(tool);
          if (!granted.isGranted) {
            updatedSteps[i] = step.copyWith(
              status: AgentStepStatus.skipped,
              error: 'Permission refusee',
            );
            state = state.copyWith(plan: updatedSteps);
            continue;
          }
        }
      }

      // Executer l'outil
      final result = await desktopToolRegistry.execute(
        step.toolId,
        step.params,
      );

      updatedSteps[i] = step.copyWith(
        status: result.success ? AgentStepStatus.completed : AgentStepStatus.failed,
        resultSummary: result.data?.substring(0, min(result.data?.length ?? 0, 200)),
        error: result.error,
      );
      state = state.copyWith(plan: updatedSteps);

      if (!result.success) break;
    }
  }

  /// Phase VERIFY : le LLM evalue la qualite des resultats.
  Future<void> _verify() async {
    state = state.copyWith(phase: AgentPhase.verifying);

    final resultsText = state.plan.map((s) =>
        '[${s.status.name}] ${s.description}: ${s.resultSummary ?? s.error ?? "N/A"}')
        .join('\n');

    final verifyPrompt = '''
Evalue si ce plan a ete execute avec succes. Reponds UNIQUEMENT avec :
{"success": true/false, "reason": "..."}

GOAL : $state.goal

RESULTATS :
$resultsText
''';

    try {
      final response = await _callLlm(verifyPrompt);
      final json = _extractJson(response);
      final success = json?['success'] as bool? ?? true;

      if (!success && state.canRetry) {
        state = state.copyWith(
          retryCount: state.retryCount + 1,
          phase: AgentPhase.planning,
        );
        await run(state.goal); // Reessayer
        return;
      }
    } catch (e) {
      // Si la verification echoue, on continue quand meme vers le rapport
    }

    state = state.copyWith(phase: AgentPhase.reporting);
  }

  /// Phase REPORT : genere le rapport final.
  Future<void> _report() async {
    final completed = state.plan
        .where((s) => s.status == AgentStepStatus.completed)
        .toList();
    final failed = state.plan
        .where((s) => s.status == AgentStepStatus.failed)
        .toList();

    final reportPrompt = '''
Genere un rapport de synthese pour la tache suivante. Format : markdown.
Inclus : resume, resultats detailles, erreurs eventuelles, recommandations.

GOAL : $state.goal

Etapes reussies (${completed.length}) :
${completed.map((s) => '- ${s.description}: ${s.resultSummary}').join('\n')}

Etapes echouees (${failed.length}) :
${failed.map((s) => '- ${s.description}: ${s.error}').join('\n')}
''';

    try {
      final response = await _callLlm(reportPrompt);
      state = state.copyWith(
        reportContent: response,
        reportFormat: 'markdown',
        phase: AgentPhase.reporting,
      );
    } catch (e) {
      state = state.copyWith(
        phase: AgentPhase.error,
        error: 'Erreur generation rapport : $e',
      );
    }
  }

  /// Annule la tache en cours.
  void cancel() {
    state = state.copyWith(
      phase: AgentPhase.idle,
      plan: [],
      error: 'Annule par l\'utilisateur',
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<String> _callLlm(String prompt) async {
    final messages = [
      {'role': 'system', 'content': 'Tu es un assistant planificateur. Reponds UNIQUEMENT au format JSON demande.'},
      {'role': 'user', 'content': prompt},
    ];

    final buffer = StringBuffer();
    final stream = _aiClient.streamChat(messages);
    await for (final chunk in stream) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }

  Map<String, dynamic>? _extractJson(String text) {
    try {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start >= 0 && end > start) {
        return jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}

/// Provider pour l'agent notifier.
final agentNotifierProvider =
    NotifierProvider.family<AgentNotifier, AgentState, String>(
  AgentNotifier.new,
);
