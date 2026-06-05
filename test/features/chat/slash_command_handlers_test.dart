import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/core/platform/browser_action.dart';
import 'package:corel_ia/features/chat/presentation/slash_commands.dart';

void main() {
  // ── BrowserAction construction ─────────────────────────────────────────────

  group('BrowserAction', () {
    test('actionId is auto-generated and unique', () {
      final a1 = BrowserAction(action: BrowserActionType.extractText, params: {});
      final a2 = BrowserAction(action: BrowserActionType.extractText, params: {});
      expect(a1.actionId, isNotEmpty);
      expect(a1.actionId, isNot(equals(a2.actionId)));
    });

    test('toJson contains all required fields', () {
      final action = BrowserAction(
        action: BrowserActionType.download,
        params: {'url': 'https://example.com/file.pdf', 'filename': 'doc.pdf'},
      );
      final json = action.toJson();
      expect(json['actionId'], equals(action.actionId));
      expect(json['action'], equals('DOWNLOAD'));
      expect(json['params'], equals({'url': 'https://example.com/file.pdf', 'filename': 'doc.pdf'}));
    });
  });

  // ── BrowserActionResult ───────────────────────────────────────────────────

  group('BrowserActionResult', () {
    test('fromJson parses success result', () {
      final result = BrowserActionResult.fromJson({
        'actionId': '123',
        'action': 'EXTRACT_LINKS',
        'success': true,
        'data': {'links': [], 'count': 0, 'filter': 'all'},
      });
      expect(result.actionId, equals('123'));
      expect(result.action, equals(BrowserActionType.extractLinks));
      expect(result.success, isTrue);
      expect(result.data!['count'], equals(0));
      expect(result.error, isNull);
    });

    test('fromJson parses error result', () {
      final result = BrowserActionResult.fromJson({
        'actionId': '456',
        'action': 'CLICK_ELEMENT',
        'success': false,
        'error': 'Element not found',
      });
      expect(result.success, isFalse);
      expect(result.error, equals('Element not found'));
      expect(result.data, isNull);
    });

    test('fromJson handles missing data gracefully', () {
      final result = BrowserActionResult.fromJson({
        'actionId': '789',
        'action': 'UNKNOWN_ACTION',
        'success': false,
      });
      expect(result.action, equals(BrowserActionType.getPageContent)); // fallback
      expect(result.success, isFalse);
    });
  });

  // ── BrowserActionType enum ────────────────────────────────────────────────

  group('BrowserActionType', () {
    test('all values have non-empty string values', () {
      for (final type in BrowserActionType.values) {
        expect(type.value, isNotEmpty);
      }
    });

    test('fromString returns correct type', () {
      expect(BrowserActionType.fromString('DOWNLOAD'), equals(BrowserActionType.download));
      expect(BrowserActionType.fromString('EXTRACT_TABLES'), equals(BrowserActionType.extractTables));
      expect(BrowserActionType.fromString('AUTOFILL_PAGE'), equals(BrowserActionType.autoFillPage));
      expect(BrowserActionType.fromString('WAIT_FOR_SELECTOR'), equals(BrowserActionType.waitForSelector));
    });

    test('fromString returns fallback for unknown value', () {
      expect(BrowserActionType.fromString('NONEXISTENT'), equals(BrowserActionType.getPageContent));
    });

    test('all new V7 action types exist', () {
      final values = BrowserActionType.values.map((e) => e.value).toSet();
      expect(values, containsAll([
        'EXTRACT_TABLES',
        'EXTRACT_FORMS',
        'EXTRACT_MEDIA',
        'PAGE_METADATA',
        'AUTOFILL_PAGE',
        'HIGHLIGHT_ELEMENT',
        'WAIT_FOR_SELECTOR',
        'GET_ELEMENT_INFO',
      ]));
    });
  });

  // ── SlashCommands intégration avec BrowserAction ─────────────────────────

  group('SlashCommand → BrowserAction mapping', () {
    test('each slash command has a corresponding BrowserActionType', () {
      // Toutes les commandes avec handlers doivent avoir un BrowserActionType
      final commandActions = {
        'download': BrowserActionType.download,
        'links': BrowserActionType.extractLinks,
        'pdf': BrowserActionType.saveAsPdf,
        'summarize': BrowserActionType.summarizePage,
        'extract': BrowserActionType.extractText,
        'scroll': BrowserActionType.scroll,
        'open': BrowserActionType.openUrl,
        'click': BrowserActionType.clickElement,
        'fill': BrowserActionType.fillForm,
        'screenshot': BrowserActionType.screenshot,
        'back': BrowserActionType.navigateBack,
        'forward': BrowserActionType.navigateForward,
        'forms': BrowserActionType.extractForms,
        'tables': BrowserActionType.extractTables,
        'media': BrowserActionType.extractMedia,
        'metadata': BrowserActionType.pageMetadata,
        'autofill': BrowserActionType.autoFillPage,
        'inspect': BrowserActionType.getElementInfo,
        'highlight': BrowserActionType.highlightElement,
        'waitfor': BrowserActionType.waitForSelector,
        'export': BrowserActionType.getPageContent,  // /export uses getPageContent + extractTables
        'monitor': BrowserActionType.extractText,
        'translate': BrowserActionType.getPageContent,
        'searchpage': BrowserActionType.getPageContent,
        'docgen': BrowserActionType.getPageContent,
        'scrape': BrowserActionType.getPageContent,
      };

      final missingCommands = <String>[];
      for (final cmd in SlashCommands.all) {
        if (!commandActions.containsKey(cmd.name)) {
          missingCommands.add(cmd.name);
        }
      }
      expect(missingCommands, isEmpty,
          reason: 'Commandes sans mapping BrowserActionType: ${missingCommands.join(', ')}');
    });
  });

  // ── Sélecteurs CSS dans les commandes slash ─────────────────────────────

  group('CSS Selector patterns in slash commands', () {
    test('sélecteurs CSS valides sont acceptés', () {
      final selectors = [
        '/click button',
        '/click #id',
        '/click .class',
        '/click div > p',
        '/click a[href="/next"]',
        '/fill input[name="email"] value',
        '/extract article',
        '/inspect .price-tag',
        '/highlight #main',
        '/waitfor .loaded 5000',
        '/monitor span.price 60',
      ];

      for (final cmd in selectors) {
        final parsed = SlashCommands.parse(cmd);
        expect(parsed, isNotNull, reason: 'Échec parsing: $cmd');
      }
    });

    test('sélecteurs CSS complexes sont acceptés', () {
      final complexSelectors = [
        '/click button.submit.primary',
        '/click form#login input[type="email"]',
        '/extract div.content > p:first-child',
        '/inspect table.data tr:nth-child(2)',
        '/highlight ul li:last-child a',
        '/fill textarea[name="bio"] Une description.',
      ];

      for (final cmd in complexSelectors) {
        final parsed = SlashCommands.parse(cmd);
        expect(parsed, isNotNull, reason: 'Échec parsing complexe: $cmd');
      }
    });
  });

  // ── Validation des paramètres ────────────────────────────────────────────

  group('Slash command parameter validation', () {
    test('/open requires URL', () {
      // La commande elle-même parse, mais le handler vérifie les args
      final parsed = SlashCommands.parse('/open');
      expect(parsed, isNotNull);
      expect(parsed!.args, isEmpty);
    });

    test('/download requires URL', () {
      final parsed = SlashCommands.parse('/download');
      expect(parsed, isNotNull);
      expect(parsed!.args, isEmpty);
    });

    test('/click requires selector', () {
      final parsed = SlashCommands.parse('/click');
      expect(parsed, isNotNull);
      expect(parsed!.args, isEmpty);
    });

    test('/fill requires selector and value', () {
      final parsed = SlashCommands.parse('/fill');
      expect(parsed, isNotNull);
      expect(parsed!.args, isEmpty);
    });

    test('/monitor requires selector', () {
      final parsed = SlashCommands.parse('/monitor');
      expect(parsed, isNotNull);
      expect(parsed!.args, isEmpty);
    });

    test('/waitfor requires selector', () {
      final parsed = SlashCommands.parse('/waitfor');
      expect(parsed, isNotNull);
      expect(parsed!.args, isEmpty);
    });

    test('/translate validates language code', () {
      // /translate sans args → le handler affichera l'erreur
      final parsed = SlashCommands.parse('/translate');
      expect(parsed, isNotNull);
      expect(parsed!.args, isEmpty);

      // /translate avec langue valide
      final valid = SlashCommands.parse('/translate fr');
      expect(valid!.args, equals(['fr']));

      // /translate avec langue inconnue (le handler gère la validation)
      final unknown = SlashCommands.parse('/translate xx');
      expect(unknown!.args, equals(['xx']));
    });
  });

  // ── Tests de régression : commandes existantes toujours fonctionnelles ──

  group('Regression: existing commands', () {
    test('/download with url only still works', () {
      final result = SlashCommands.parse('/download https://example.com/file.zip');
      expect(result!.command.name, equals('download'));
      expect(result.args, equals(['https://example.com/file.zip']));
    });

    test('/links with filter still works', () {
      final result = SlashCommands.parse('/links video');
      expect(result!.command.name, equals('links'));
      expect(result.args, equals(['video']));
    });

    test('/summarize still works (no args)', () {
      final result = SlashCommands.parse('/summarize');
      expect(result!.command.name, equals('summarize'));
      expect(result.args, isEmpty);
    });

    test('/extract with selector still works', () {
      final result = SlashCommands.parse('/extract .main-content');
      expect(result!.command.name, equals('extract'));
      expect(result.args, equals(['.main-content']));
    });

    test('/scroll with direction and amount still works', () {
      final result = SlashCommands.parse('/scroll down 300');
      expect(result!.command.name, equals('scroll'));
      expect(result.args, equals(['down', '300']));
    });

    test('/screenshot still works (no args)', () {
      final result = SlashCommands.parse('/screenshot');
      expect(result!.command.name, equals('screenshot'));
      expect(result.args, isEmpty);
    });
  });
}
