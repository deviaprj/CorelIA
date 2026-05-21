import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/core/platform/browser_action.dart';
import 'package:airon_bot/features/chat/presentation/slash_commands.dart';

void main() {
  group('Slash Commands End-to-End', () {
    group('All commands parse and map to BrowserAction', () {
      final commandMappings = {
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
        'export': BrowserActionType.getPageContent,
        'monitor': BrowserActionType.extractText,
        'translate': BrowserActionType.getPageContent,
        'searchpage': BrowserActionType.getPageContent,
        'docgen': BrowserActionType.getPageContent,
      };

      for (final entry in commandMappings.entries) {
        test('/${entry.key} parses and has a BrowserActionType', () {
          final parsed = SlashCommands.parse('/${entry.key} test_arg');
          expect(parsed, isNotNull, reason: '/${entry.key} should parse');
          expect(parsed!.command.name, entry.key);
          // Every slash command must have a corresponding action type
          expect(BrowserActionType.values, contains(entry.value));
        });
      }
    });

    group('Combo workflows', () {
      test('links + download combo', () {
        final links = SlashCommands.parse('/links video');
        final download = SlashCommands.parse('/download');
        expect(links, isNotNull);
        expect(download, isNotNull);
        expect(links!.command.name, 'links');
        expect(download!.command.name, 'download');
      });

      test('scroll + screenshot combo', () {
        final scroll = SlashCommands.parse('/scroll down 800');
        final screenshot = SlashCommands.parse('/screenshot');
        expect(scroll, isNotNull);
        expect(screenshot, isNotNull);
        expect(scroll!.args, equals(['down', '800']));
      });

      test('open + waitfor + extract combo', () {
        final open = SlashCommands.parse('/open https://example.com');
        final waitfor = SlashCommands.parse('/waitfor .content 5000');
        final extract = SlashCommands.parse('/extract .content');
        expect(open, isNotNull);
        expect(waitfor, isNotNull);
        expect(extract, isNotNull);
        expect(open!.args.first, equals('https://example.com'));
        expect(waitfor!.args.first, equals('.content'));
      });

      test('forms + autofill + fill + click combo', () {
        final forms = SlashCommands.parse('/forms');
        final autofill = SlashCommands.parse('/autofill');
        final fill = SlashCommands.parse('/fill #email test@test.com');
        final click = SlashCommands.parse('/click button.submit');
        expect(forms, isNotNull);
        expect(autofill, isNotNull);
        expect(fill, isNotNull);
        expect(click, isNotNull);
      });

      test('metadata + export json combo', () {
        final metadata = SlashCommands.parse('/metadata');
        final export = SlashCommands.parse('/export json');
        expect(metadata, isNotNull);
        expect(export, isNotNull);
        expect(export!.args.first, equals('json'));
      });

      test('searchpage + extract combo', () {
        final searchpage = SlashCommands.parse('/searchpage prix');
        final extract = SlashCommands.parse('/extract .price');
        expect(searchpage, isNotNull);
        expect(extract, isNotNull);
        expect(searchpage!.args.first, equals('prix'));
      });

      test('click + waitfor + inspect + highlight combo', () {
        final click = SlashCommands.parse('/click #show-more');
        final waitfor = SlashCommands.parse('/waitfor .new-content 5000');
        final inspect = SlashCommands.parse('/inspect .new-content');
        final highlight = SlashCommands.parse('/highlight .new-content');
        expect(click!.command.name, 'click');
        expect(waitfor!.command.name, 'waitfor');
        expect(inspect!.command.name, 'inspect');
        expect(highlight!.command.name, 'highlight');
      });

      test('monitor + extract combo', () {
        final monitor = SlashCommands.parse('/monitor .price 60');
        final extract = SlashCommands.parse('/extract .price');
        expect(monitor, isNotNull);
        expect(extract, isNotNull);
        expect(monitor!.args, equals(['.price', '60']));
      });
    });

    group('Error handling', () {
      test('unknown command returns null', () {
        expect(SlashCommands.parse('/unknown'), isNull);
      });

      test('text without slash returns null', () {
        expect(SlashCommands.parse('hello world'), isNull);
      });

      test('empty args are allowed', () {
        final parsed = SlashCommands.parse('/summarize');
        expect(parsed, isNotNull);
        expect(parsed!.args, isEmpty);
      });
    });
  });
}
