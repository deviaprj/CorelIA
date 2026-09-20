import 'package:corel_ia/core/models/user_role.dart';
import 'package:corel_ia/core/providers/firebase_providers.dart';
import 'package:corel_ia/features/chat/data/chat_repository.dart';
import 'package:corel_ia/features/chat/presentation/chat_notifier.dart';
import 'package:corel_ia/features/subscription/data/quota_service.dart';
import 'package:corel_ia/features/subscription/data/role_providers.dart';
import 'package:corel_ia/features/subscription/domain/quota_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer buildContainer(String uid) => ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(
            AppUserLike(uid: uid, email: '$uid@corelia.app'),
          ),
          userRoleProvider.overrideWithValue(UserRole.free),
          chatRepositoryProvider.overrideWithValue(const ChatRepository(null)),
          quotaServiceProvider.overrideWithValue(QuotaService()),
        ],
      );

  test('le message utilisateur reste affiché même si l\'IA échoue', () async {
    final container = buildContainer('u1');
    addTearDown(container.dispose);

    await container.read(chatNotifierProvider.notifier).sendMessage('Bonjour');

    final state = container.read(chatNotifierProvider);
    expect(
      state.messages.map((m) => m.content),
      contains('Bonjour'),
      reason: 'le message de l\'utilisateur doit rester dans la conversation',
    );
    expect(state.error, isNotNull, reason: 'sans clé IA, une erreur est attendue');
    expect(state.isStreaming, isFalse);
    expect(
      state.remainingRequests,
      QuotaPolicies.free.dailyRequests! - 1,
      reason: 'la requête Free doit être décomptée',
    );
    expect(
      state.messages.where((m) => m.isStreaming),
      isEmpty,
      reason: 'le placeholder de streaming doit être retiré',
    );
  });

  test('le quota épuisé bloque le message et le garde en attente', () async {
    final container = buildContainer('u2');
    addTearDown(container.dispose);

    final quota = container.read(quotaServiceProvider);
    for (var i = 0; i < QuotaPolicies.free.dailyRequests!; i++) {
      await quota.consume(UserRole.free);
    }

    final notifier = container.read(chatNotifierProvider.notifier);
    await notifier.sendMessage('Dernier message');

    final state = container.read(chatNotifierProvider);
    expect(state.error, kQuotaExceededError);
    expect(state.quotaBlocked, isTrue);
    expect(state.messages, isEmpty);
    expect(state.remainingRequests, 0);

    // Le message est conservé pour être renvoyé après passage en Full.
    await quota.reset();
    await notifier.retryPendingMessage();
    expect(container.read(chatNotifierProvider).messages, isNotEmpty);
  });
}
