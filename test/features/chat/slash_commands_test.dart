import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airon_bot/features/chat/presentation/slash_commands.dart';

void main() {
  // ── SlashCommand model ─────────────────────────────────────────────────────

  group('SlashCommand', () {
    test('example returns /name for commands with no params', () {
      const cmd = SlashCommand(
        name: 'screenshot',
        description: 'Test',
        usage: '/screenshot',
        icon: Icons.screenshot,
      );
      expect(cmd.example, equals('/screenshot'));
    });

    test('example returns /name <param1> <param2> for commands with params', () {
      const cmd = SlashCommand(
        name: 'download',
        description: 'Test',
        usage: '/download <url> [filename]',
        params: ['url', 'filename'],
        icon: Icons.download,
      );
      expect(cmd.example, equals('/download <url> <filename>'));
    });

    test('example with single param', () {
      const cmd = SlashCommand(
        name: 'open',
        description: 'Test',
        usage: '/open <url>',
        params: ['url'],
        icon: Icons.open_in_new,
      );
      expect(cmd.example, equals('/open <url>'));
    });
  });

  // ── SlashCommands.search ───────────────────────────────────────────────────

  group('SlashCommands.search', () {
    test('returns all commands when prefix is empty', () {
      final results = SlashCommands.search('');
      expect(results.length, equals(SlashCommands.all.length));
    });

    test('filters by name prefix (case-insensitive)', () {
      final results = SlashCommands.search('downlo');
      expect(results.length, equals(1));
      expect(results.first.name, equals('download'));
    });

    test('filters by name prefix (uppercase)', () {
      final results = SlashCommands.search('SC');
      expect(results.any((c) => c.name == 'screenshot'), isTrue);
    });

    test('filters by description content', () {
      final results = SlashCommands.search('télécharger');
      expect(results.any((c) => c.name == 'download'), isTrue);
    });

    test('filters by description: "page" matches multiple', () {
      final results = SlashCommands.search('page');
      expect(results.length, greaterThanOrEqualTo(2));
      expect(results.any((c) => c.name == 'summarize'), isTrue);
      expect(results.any((c) => c.name == 'pdf'), isTrue);
    });

    test('returns empty list for unknown prefix', () {
      final results = SlashCommands.search('xyz123');
      expect(results, isEmpty);
    });

    test('partial name "li" matches links', () {
      final results = SlashCommands.search('li');
      expect(results.any((c) => c.name == 'links'), isTrue);
    });

    test('partial name "sc" matches scroll and screenshot', () {
      final results = SlashCommands.search('sc');
      expect(results.any((c) => c.name == 'scroll'), isTrue);
      expect(results.any((c) => c.name == 'screenshot'), isTrue);
    });

    test('description "formulaire" matches fill', () {
      final results = SlashCommands.search('formulaire');
      expect(results.any((c) => c.name == 'fill'), isTrue);
    });

    test('description "sélecteur CSS" matches extract and click and fill', () {
      final results = SlashCommands.search('sélecteur');
      expect(results.length, greaterThanOrEqualTo(2));
      expect(results.any((c) => c.name == 'extract'), isTrue);
      expect(results.any((c) => c.name == 'click'), isTrue);
    });
  });

  // ── SlashCommands.parse ────────────────────────────────────────────────────

  group('SlashCommands.parse', () {
    test('returns null for text not starting with /', () {
      expect(SlashCommands.parse('hello'), isNull);
      expect(SlashCommands.parse('download url'), isNull);
    });

    test('returns null for unknown command', () {
      expect(SlashCommands.parse('/unknown'), isNull);
      expect(SlashCommands.parse('/foo bar'), isNull);
    });

    test('parses /download with url and filename', () {
      final result = SlashCommands.parse('/download https://example.com/video.mp4 myvideo.mp4');
      expect(result, isNotNull);
      expect(result!.command.name, equals('download'));
      expect(result.args, equals(['https://example.com/video.mp4', 'myvideo.mp4']));
    });

    test('parses /download with url only', () {
      final result = SlashCommands.parse('/download https://example.com/file.zip');
      expect(result, isNotNull);
      expect(result!.command.name, equals('download'));
      expect(result.args, equals(['https://example.com/file.zip']));
    });

    test('parses /links with filter', () {
      final result = SlashCommands.parse('/links video');
      expect(result, isNotNull);
      expect(result!.command.name, equals('links'));
      expect(result.args, equals(['video']));
    });

    test('parses /links without filter', () {
      final result = SlashCommands.parse('/links');
      expect(result, isNotNull);
      expect(result!.command.name, equals('links'));
      expect(result.args, isEmpty);
    });

    test('parses /pdf with url and filename', () {
      final result = SlashCommands.parse('/pdf https://example.com report');
      expect(result, isNotNull);
      expect(result!.command.name, equals('pdf'));
    });

    test('parses /pdf without args', () {
      final result = SlashCommands.parse('/pdf');
      expect(result, isNotNull);
      expect(result!.command.name, equals('pdf'));
      expect(result.args, isEmpty);
    });

    test('parses /summarize (no args)', () {
      final result = SlashCommands.parse('/summarize');
      expect(result, isNotNull);
      expect(result!.command.name, equals('summarize'));
      expect(result.args, isEmpty);
    });

    test('parses /extract with selector', () {
      final result = SlashCommands.parse('/extract .main-content');
      expect(result, isNotNull);
      expect(result!.command.name, equals('extract'));
      expect(result.args, equals(['.main-content']));
    });

    test('parses /scroll with direction and amount', () {
      final result = SlashCommands.parse('/scroll down 300');
      expect(result, isNotNull);
      expect(result!.command.name, equals('scroll'));
      expect(result.args, equals(['down', '300']));
    });

    test('parses /open with url', () {
      final result = SlashCommands.parse('/open https://example.com');
      expect(result, isNotNull);
      expect(result!.command.name, equals('open'));
      expect(result.args, equals(['https://example.com']));
    });

    test('parses /click with selector', () {
      final result = SlashCommands.parse('/click #submit-btn');
      expect(result, isNotNull);
      expect(result!.command.name, equals('click'));
      expect(result.args, equals(['#submit-btn']));
    });

    test('parses /fill with selector and value', () {
      final result = SlashCommands.parse('/fill #email user@example.com');
      expect(result, isNotNull);
      expect(result!.command.name, equals('fill'));
      expect(result.args, equals(['#email', 'user@example.com']));
    });

    test('parses /screenshot (no args)', () {
      final result = SlashCommands.parse('/screenshot');
      expect(result, isNotNull);
      expect(result!.command.name, equals('screenshot'));
      expect(result.args, isEmpty);
    });

    test('parses /back (no args)', () {
      final result = SlashCommands.parse('/back');
      expect(result, isNotNull);
      expect(result!.command.name, equals('back'));
      expect(result.args, isEmpty);
    });

    test('parses /forward (no args)', () {
      final result = SlashCommands.parse('/forward');
      expect(result, isNotNull);
      expect(result!.command.name, equals('forward'));
      expect(result.args, isEmpty);
    });

    test('is case-insensitive for command name', () {
      final result = SlashCommands.parse('/DOWNLOAD url');
      expect(result, isNotNull);
      expect(result!.command.name, equals('download'));
    });

    test('trims whitespace before parsing', () {
      final result = SlashCommands.parse('  /screenshot  ');
      expect(result, isNotNull);
      expect(result!.command.name, equals('screenshot'));
    });

    test('handles extra whitespace between args', () {
      final result = SlashCommands.parse('/scroll   down   500');
      expect(result, isNotNull);
      expect(result!.command.name, equals('scroll'));
      expect(result.args, equals(['down', '500']));
    });

    // ── Nouvelles commandes V7 ───────────────────────────────────────────

    test('parses /forms with index', () {
      final result = SlashCommands.parse('/forms 0');
      expect(result, isNotNull);
      expect(result!.command.name, equals('forms'));
      expect(result.args, equals(['0']));
    });

    test('parses /forms without args', () {
      final result = SlashCommands.parse('/forms');
      expect(result, isNotNull);
      expect(result!.command.name, equals('forms'));
      expect(result.args, isEmpty);
    });

    test('parses /tables with index', () {
      final result = SlashCommands.parse('/tables 2');
      expect(result, isNotNull);
      expect(result!.command.name, equals('tables'));
      expect(result.args, equals(['2']));
    });

    test('parses /media with type', () {
      final result = SlashCommands.parse('/media images');
      expect(result, isNotNull);
      expect(result!.command.name, equals('media'));
      expect(result.args, equals(['images']));
    });

    test('parses /media with all', () {
      final result = SlashCommands.parse('/media all');
      expect(result, isNotNull);
      expect(result!.command.name, equals('media'));
      expect(result.args, equals(['all']));
    });

    test('parses /metadata', () {
      final result = SlashCommands.parse('/metadata');
      expect(result, isNotNull);
      expect(result!.command.name, equals('metadata'));
      expect(result.args, isEmpty);
    });

    test('parses /autofill', () {
      final result = SlashCommands.parse('/autofill');
      expect(result, isNotNull);
      expect(result!.command.name, equals('autofill'));
      expect(result.args, isEmpty);
    });

    test('parses /inspect with selector', () {
      final result = SlashCommands.parse('/inspect .product-card');
      expect(result, isNotNull);
      expect(result!.command.name, equals('inspect'));
      expect(result.args, equals(['.product-card']));
    });

    test('parses /highlight with selector', () {
      final result = SlashCommands.parse('/highlight #main-title');
      expect(result, isNotNull);
      expect(result!.command.name, equals('highlight'));
      expect(result.args, equals(['#main-title']));
    });

    test('parses /waitfor with selector and timeout', () {
      final result = SlashCommands.parse('/waitfor .results 5000');
      expect(result, isNotNull);
      expect(result!.command.name, equals('waitfor'));
      expect(result.args, equals(['.results', '5000']));
    });

    test('parses /export with format', () {
      final result = SlashCommands.parse('/export csv');
      expect(result, isNotNull);
      expect(result!.command.name, equals('export'));
      expect(result.args, equals(['csv']));
    });

    test('parses /export json default', () {
      final result = SlashCommands.parse('/export');
      expect(result, isNotNull);
      expect(result!.command.name, equals('export'));
      expect(result.args, isEmpty);
    });

    test('parses /monitor with selector and interval', () {
      final result = SlashCommands.parse('/monitor .price 60');
      expect(result, isNotNull);
      expect(result!.command.name, equals('monitor'));
      expect(result.args, equals(['.price', '60']));
    });

    test('parses /translate with language', () {
      final result = SlashCommands.parse('/translate en');
      expect(result, isNotNull);
      expect(result!.command.name, equals('translate'));
      expect(result.args, equals(['en']));
    });

    test('parses /searchpage with term', () {
      final result = SlashCommands.parse('/searchpage GDPR compliance');
      expect(result, isNotNull);
      expect(result!.command.name, equals('searchpage'));
      expect(result.args, equals(['GDPR', 'compliance']));
    });
  });

  // ── ParsedSlashCommand ─────────────────────────────────────────────────────

  group('ParsedSlashCommand', () {
    test('fullText reconstructs command with args', () {
      const cmd = SlashCommand(
        name: 'download',
        description: 'Test',
        usage: '/download <url>',
        params: ['url'],
        icon: Icons.download,
      );
      const parsed = ParsedSlashCommand(
        command: cmd,
        args: ['https://example.com/file.zip'],
      );
      expect(parsed.fullText, equals('/download https://example.com/file.zip'));
    });

    test('fullText reconstructs command without args', () {
      const cmd = SlashCommand(
        name: 'screenshot',
        description: 'Test',
        usage: '/screenshot',
        icon: Icons.screenshot,
      );
      const parsed = ParsedSlashCommand(command: cmd, args: []);
      expect(parsed.fullText, equals('/screenshot'));
    });
  });

  // ── ParsedSlashCommand.toNaturalLanguage ────────────────────────────────────

  group('ParsedSlashCommand.toNaturalLanguage', () {
    test('/links → natural language', () {
      final result = SlashCommands.parse('/links')!;
      expect(
        result.toNaturalLanguage(),
        equals('Extrais tous les liens de la page courante'),
      );
    });

    test('/links video → natural language', () {
      final result = SlashCommands.parse('/links video')!;
      expect(
        result.toNaturalLanguage(),
        equals('Extrais tous les liens vidéos de la page courante'),
      );
    });

    test('/download → natural language', () {
      final result =
          SlashCommands.parse('/download https://example.com/doc.pdf')!;
      expect(
        result.toNaturalLanguage(),
        equals('Télécharge https://example.com/doc.pdf'),
      );
    });

    test('/summarize → natural language', () {
      final result = SlashCommands.parse('/summarize')!;
      expect(result.toNaturalLanguage(), equals('Résume la page courante'));
    });

    test('/screenshot → natural language', () {
      final result = SlashCommands.parse('/screenshot')!;
      expect(
        result.toNaturalLanguage(),
        equals("Capture d'écran de la page courante"),
      );
    });

    test('/translate → natural language', () {
      final result = SlashCommands.parse('/translate en')!;
      expect(
        result.toNaturalLanguage(),
        equals('Traduis la page en anglais'),
      );
    });

    test('/forms → natural language', () {
      final result = SlashCommands.parse('/forms')!;
      expect(
        result.toNaturalLanguage(),
        equals('Extrais les formulaires de la page'),
      );
    });

    test('/media → natural language', () {
      final result = SlashCommands.parse('/media images')!;
      expect(
        result.toNaturalLanguage(),
        equals('Extrais les médias (images) de la page'),
      );
    });

    test('/searchpage → natural language', () {
      final result = SlashCommands.parse('/searchpage prix')!;
      expect(
        result.toNaturalLanguage(),
        equals('Cherche "prix" dans la page'),
      );
    });

    test('/fill → natural language', () {
      final result =
          SlashCommands.parse('/fill input[name="email"] test@test.com')!;
      expect(
        result.toNaturalLanguage(),
        equals('Remplis input[name="email"] avec "test@test.com"'),
      );
    });

    test('/export → natural language', () {
      final result = SlashCommands.parse('/export csv')!;
      expect(result.toNaturalLanguage(), equals('Exporte la page en CSV'));
    });

    test('/monitor → natural language', () {
      final result = SlashCommands.parse('/monitor .price 1800')!;
      expect(
        result.toNaturalLanguage(),
        equals('Surveille .price'),
      );
    });
  });

  // ── SlashCommands.all completeness ─────────────────────────────────────────

  group('SlashCommands.all', () {
    test('contains exactly 25 commands', () {
      expect(SlashCommands.all.length, equals(25));
    });

    test('all commands have non-empty names', () {
      for (final cmd in SlashCommands.all) {
        expect(cmd.name, isNotEmpty);
      }
    });

    test('all commands have non-empty descriptions', () {
      for (final cmd in SlashCommands.all) {
        expect(cmd.description, isNotEmpty);
      }
    });

    test('all commands have non-empty usage strings', () {
      for (final cmd in SlashCommands.all) {
        expect(cmd.usage, isNotEmpty);
      }
    });

    test('all command names are unique', () {
      final names = SlashCommands.all.map((c) => c.name).toList();
      expect(names.toSet().length, equals(names.length));
    });

    test('all commands start with / in usage', () {
      for (final cmd in SlashCommands.all) {
        expect(cmd.usage, startsWith('/'));
      }
    });

    test('required commands exist', () {
      final names = SlashCommands.all.map((c) => c.name).toSet();
      expect(names, containsAll([
        'download', 'links', 'pdf', 'summarize', 'extract',
        'scroll', 'open', 'click', 'fill', 'screenshot',
        'back', 'forward',
        // Nouvelles commandes V7
        'forms', 'tables', 'media', 'metadata', 'autofill',
        'inspect', 'highlight', 'waitfor', 'export', 'monitor',
        'translate', 'searchpage',
      ]));
    });
  });

  // ── SlashCommandPalette widget ───────────────────────────────────────────────

  group('SlashCommandPalette', () {
    testWidgets('renders commands matching filter', (tester) async {
      String? selectedCmd;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SlashCommandPalette(
            filter: 'dow',
            onSelected: (cmd) => selectedCmd = cmd.name,
          ),
        ),
      ));

      expect(find.text('/download'), findsOneWidget);
      await tester.tap(find.text('/download'));
      expect(selectedCmd, equals('download'));
    });

    testWidgets('shows all commands when filter is empty', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: SlashCommandPalette(
              filter: '',
              onSelected: (_) {},
            ),
          ),
        ),
      ));

      // Should render the palette with "Commandes" header
      expect(find.text('Commandes'), findsOneWidget);
      // At least the first command should be visible
      expect(find.text('/download'), findsOneWidget);
      // A ListView exists for scrollable content
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('renders nothing when no commands match', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SlashCommandPalette(
            filter: 'xyznonexistent',
            onSelected: (_) {},
          ),
        ),
      ));

      expect(find.byType(SlashCommandPalette), findsOneWidget);
      // SizedBox.shrink() — no command text visible
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('displays command parameters hint', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SlashCommandPalette(
            filter: 'fill',
            onSelected: (_) {},
          ),
        ),
      ));

      expect(find.text('<selector> <value>'), findsOneWidget);
    });

    testWidgets('commands with no params show no parameter hint', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SlashCommandPalette(
            filter: 'back',
            onSelected: (_) {},
          ),
        ),
      ));

      // /back has no params, so the params column text should be empty
      expect(find.text('/back'), findsOneWidget);
    });

    testWidgets('displays header with "Commandes" label', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SlashCommandPalette(
            filter: '',
            onSelected: (_) {},
          ),
        ),
      ));

      expect(find.text('Commandes'), findsOneWidget);
    });

    testWidgets('each command row is tappable and calls onSelected',
        (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: SlashCommandPalette(
              filter: '',
              onSelected: (cmd) => selected.add(cmd.name),
            ),
          ),
        ),
      ));

      // Tap /download
      await tester.tap(find.text('/download'));
      expect(selected, contains('download'));
    });
  });

  // ── Combos — Enchaînements de commandes slash ──────────────────────────

  group('Combos Slash — Enchaînements', () {
    test('Combo "links + download" parse correctement', () {
      final cmd1 = SlashCommands.parse('/links document');
      expect(cmd1, isNotNull);
      expect(cmd1!.command.name, equals('links'));
      expect(cmd1.args, equals(['document']));

      final cmd2 = SlashCommands.parse('/download https://example.com/doc.pdf rapport.pdf');
      expect(cmd2, isNotNull);
      expect(cmd2!.command.name, equals('download'));
      expect(cmd2.args, equals(['https://example.com/doc.pdf', 'rapport.pdf']));
    });

    test('Combo "extract + translate" parse correctement', () {
      final cmd1 = SlashCommands.parse('/extract .recipe-ingredients');
      expect(cmd1, isNotNull);
      expect(cmd1!.command.name, equals('extract'));

      final cmd2 = SlashCommands.parse('/translate en');
      expect(cmd2, isNotNull);
      expect(cmd2!.command.name, equals('translate'));
      expect(cmd2!.args, equals(['en']));
    });

    test('Combo "forms + autofill + fill + click" parse correctement', () {
      final cmds = [
        SlashCommands.parse('/forms')!,
        SlashCommands.parse('/autofill')!,
        SlashCommands.parse('/fill input[name="email"] moi@email.com')!,
        SlashCommands.parse('/click button[type="submit"]')!,
      ];

      expect(cmds[0].command.name, equals('forms'));
      expect(cmds[1].command.name, equals('autofill'));
      expect(cmds[2].command.name, equals('fill'));
      expect(cmds[3].command.name, equals('click'));
      expect(cmds[2].args, equals(['input[name="email"]', 'moi@email.com']));
    });

    test('Combo "summarize + pdf" parse correctement', () {
      final cmd1 = SlashCommands.parse('/summarize');
      expect(cmd1, isNotNull);
      expect(cmd1!.command.name, equals('summarize'));

      final cmd2 = SlashCommands.parse('/pdf "" mon_resume');
      expect(cmd2, isNotNull);
      expect(cmd2!.command.name, equals('pdf'));
    });

    test('Combo "tables + export csv" parse correctement', () {
      final cmd1 = SlashCommands.parse('/tables');
      expect(cmd1, isNotNull);
      expect(cmd1!.command.name, equals('tables'));

      final cmd2 = SlashCommands.parse('/export csv');
      expect(cmd2, isNotNull);
      expect(cmd2!.command.name, equals('export'));
      expect(cmd2!.args, equals(['csv']));
    });

    test('Combo "media + download" parse correctement', () {
      final cmd1 = SlashCommands.parse('/media images');
      expect(cmd1, isNotNull);
      expect(cmd1!.command.name, equals('media'));

      final cmd2 = SlashCommands.parse('/download https://cdn.example.com/photo-hd.jpg');
      expect(cmd2, isNotNull);
      expect(cmd2!.command.name, equals('download'));
    });

    test('Combo "metadata + export json" parse correctement', () {
      final cmd1 = SlashCommands.parse('/metadata');
      expect(cmd1, isNotNull);
      expect(cmd1!.command.name, equals('metadata'));

      final cmd2 = SlashCommands.parse('/export json');
      expect(cmd2, isNotNull);
      expect(cmd2!.command.name, equals('export'));
      expect(cmd2!.args, equals(['json']));
    });

    test('Combo "searchpage + extract" parse correctement', () {
      final cmd1 = SlashCommands.parse('/searchpage "API key"');
      expect(cmd1, isNotNull);
      expect(cmd1!.command.name, equals('searchpage'));
      expect(cmd1.args, equals(['API key']));

      final cmd2 = SlashCommands.parse('/extract .api-reference');
      expect(cmd2, isNotNull);
      expect(cmd2!.command.name, equals('extract'));
    });

    test('Combo "open + waitfor + extract" parse correctement', () {
      final cmds = [
        SlashCommands.parse('/open https://example.com/spa')!,
        SlashCommands.parse('/waitfor .content-loaded 10000')!,
        SlashCommands.parse('/extract .content-loaded')!,
      ];

      expect(cmds[0].command.name, equals('open'));
      expect(cmds[1].command.name, equals('waitfor'));
      expect(cmds[1].args, equals(['.content-loaded', '10000']));
      expect(cmds[2].command.name, equals('extract'));
    });

    test('Workflow e-commerce complet parse correctement', () {
      final workflow = [
        SlashCommands.parse('/open https://ecommerce.fr/produit'),
        SlashCommands.parse('/metadata'),
        SlashCommands.parse('/searchpage €'),
        SlashCommands.parse('/extract .product-description'),
        SlashCommands.parse('/media images'),
        SlashCommands.parse('/screenshot'),
      ];

      for (final cmd in workflow) {
        expect(cmd, isNotNull);
      }
      expect(workflow[0]!.command.name, equals('open'));
      expect(workflow[1]!.command.name, equals('metadata'));
      expect(workflow[2]!.command.name, equals('searchpage'));
      expect(workflow[3]!.command.name, equals('extract'));
      expect(workflow[4]!.command.name, equals('media'));
      expect(workflow[5]!.command.name, equals('screenshot'));
    });

    test('Combo "scroll + screenshot" parse correctement', () {
      final cmd1 = SlashCommands.parse('/scroll down 800');
      expect(cmd1, isNotNull);
      expect(cmd1!.command.name, equals('scroll'));

      final cmd2 = SlashCommands.parse('/screenshot');
      expect(cmd2, isNotNull);
      expect(cmd2!.command.name, equals('screenshot'));
    });

    test('Combo "click + waitfor + inspect + highlight" parse correctement', () {
      final cmds = [
        SlashCommands.parse('/click #show-more')!,
        SlashCommands.parse('/waitfor .new-content 5000')!,
        SlashCommands.parse('/inspect .new-content')!,
        SlashCommands.parse('/highlight .new-content')!,
      ];

      expect(cmds[0].command.name, equals('click'));
      expect(cmds[1].command.name, equals('waitfor'));
      expect(cmds[2].command.name, equals('inspect'));
      expect(cmds[3].command.name, equals('highlight'));
    });
  });

  // ── Nouvelles commandes : validation sémantique ────────────────────────

  group('SlashCommands.all — validation des nouvelles commandes', () {
    test('toutes les commandes de navigation existent', () {
      final names = SlashCommands.all.map((c) => c.name).toSet();
      expect(names, containsAll(['open', 'back', 'forward', 'scroll']));
    });

    test('toutes les commandes d\'extraction existent', () {
      final names = SlashCommands.all.map((c) => c.name).toSet();
      expect(names, containsAll([
        'extract', 'links', 'forms', 'tables', 'media',
      ]));
    });

    test('toutes les commandes d\'analyse existent', () {
      final names = SlashCommands.all.map((c) => c.name).toSet();
      expect(names, containsAll([
        'summarize', 'metadata', 'searchpage', 'inspect',
      ]));
    });

    test('toutes les commandes d\'interaction existent', () {
      final names = SlashCommands.all.map((c) => c.name).toSet();
      expect(names, containsAll([
        'click', 'fill', 'highlight', 'waitfor',
      ]));
    });

    test('toutes les commandes d\'automatisation existent', () {
      final names = SlashCommands.all.map((c) => c.name).toSet();
      expect(names, containsAll([
        'autofill', 'monitor',
      ]));
    });

    test('toutes les commandes de sortie existent', () {
      final names = SlashCommands.all.map((c) => c.name).toSet();
      expect(names, containsAll([
        'download', 'screenshot', 'pdf', 'export', 'translate',
      ]));
    });

    test('les commandes de combo naturelles sont toutes disponibles', () {
      // Vérifier que toutes les commandes nécessaires aux combos du guide existent
      final names = SlashCommands.all.map((c) => c.name).toSet();
      // Combo "links + download"
      expect(names, containsAll(['links', 'download']));
      // Combo "extract + translate"
      expect(names, containsAll(['extract', 'translate']));
      // Combo "forms + autofill + fill + click"
      expect(names, containsAll(['forms', 'autofill', 'fill', 'click']));
      // Combo "summarize + pdf"
      expect(names, containsAll(['summarize', 'pdf']));
      // Combo "tables + export csv"
      expect(names, containsAll(['tables', 'export']));
      // Combo "media + download"
      expect(names, containsAll(['media', 'download']));
      // Combo "metadata + export json"
      expect(names, containsAll(['metadata', 'export']));
      // Combo "searchpage + extract"
      expect(names, containsAll(['searchpage', 'extract']));
      // Combo "scroll + screenshot"
      expect(names, containsAll(['scroll', 'screenshot']));
      // Combo "click + waitfor + inspect + highlight"
      expect(names, containsAll(['click', 'waitfor', 'inspect', 'highlight']));
      // Combo "monitor"
      expect(names, contains('monitor'));
      // Combo "open"
      expect(names, contains('open'));
    });
  });
}