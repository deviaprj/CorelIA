import 'package:corel_ia/core/config/app_config.dart';
import 'package:corel_ia/features/chat/data/model_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelRouter.classifyTask', () {
    test('une image est une tâche de vision', () {
      expect(ModelRouter.classifyTask('analyse ça', hasImage: true),
          TaskType.vision);
    });

    test('un message de raisonnement est détecté', () {
      expect(ModelRouter.classifyTask('compare ces deux approches'),
          TaskType.reasoning);
      expect(ModelRouter.classifyTask('prouve que ce théorème est vrai'),
          TaskType.reasoning);
    });

    test('un message simple reste général', () {
      expect(ModelRouter.classifyTask('bonjour, comment vas-tu ?'),
          TaskType.general);
    });
  });

  group('ModelRouter.resolveModel', () {
    test('résout le modèle général pour un utilisateur Free', () {
      final entry = ModelRouter.resolveModel(TaskType.general, isFull: false);
      expect(entry, isNotNull);
      expect(entry!.isFree, isTrue);
      expect(entry.provider, 'deepseek');
    });

    test('résout un modèle compatible vision', () {
      final entry = ModelRouter.resolveModel(TaskType.vision, isFull: false);
      expect(entry, isNotNull);
      expect(entry!.supportsVision, isTrue);
    });

    test('accepte un modèle explicite du registre', () {
      final entry = ModelRouter.resolveModel(
        TaskType.general,
        userOverride: AppConfig.deepSeekReasonerModel,
        isFull: true,
      );
      expect(entry?.modelId, AppConfig.deepSeekReasonerModel);
    });

    test('ignore un modèle inconnu et retombe sur la chaîne par défaut', () {
      final entry = ModelRouter.resolveModel(
        TaskType.general,
        userOverride: 'modele/inexistant',
        isFull: false,
      );
      expect(entry, isNotNull);
    });
  });

  group('ModelRouter.resolveParams', () {
    test('renvoie des paramètres cohérents pour chaque tâche', () {
      for (final task in TaskType.values) {
        final params = ModelRouter.resolveParams(task);
        expect(params.maxTokens, greaterThan(0));
        expect(params.temperature, inInclusiveRange(0, 2));
      }
    });
  });

  group('RateLimitTracker', () {
    test('gère les cooldowns', () {
      final tracker = RateLimitTracker();
      expect(tracker.isCoolingDown('modele'), isFalse);
      tracker.setCooldown('modele', duration: const Duration(minutes: 1));
      expect(tracker.isCoolingDown('modele'), isTrue);
    });
  });
}
