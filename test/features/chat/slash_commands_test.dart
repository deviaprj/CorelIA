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
      final results = SlashCommands.search('dow');
      expect(results.length, equals(1));
      expect(results.first.name, equals('download'));
    });

    test('filters by name prefix (uppercase)', () {
      final results = SlashCommands.search('SC');
      expect(results.any((c) => c.name == 'screenshot'), isTrue);
    });

    test('filters by description content', () {
      final results = SlashCommands.search('vidéo');
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

  // ── SlashCommands.all completeness ─────────────────────────────────────────

  group('SlashCommands.all', () {
    test('contains exactly 12 commands', () {
      expect(SlashCommands.all.length, equals(12));
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
      // The first few commands should be visible
      expect(find.text('/download'), findsOneWidget);
      expect(find.text('/links'), findsOneWidget);
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
}