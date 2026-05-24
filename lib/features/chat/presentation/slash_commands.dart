import 'package:flutter/material.dart';
import '../../../core/language/language_service.dart' as lang;

/// Définition d'une commande slash.
class SlashCommand {
  final String name;
  final String description;
  final String usage;
  final List<String> params;
  final IconData icon;

  const SlashCommand({
    required this.name,
    required this.description,
    required this.usage,
    this.params = const [],
    required this.icon,
  });

  /// Exemple d'utilisation formaté.
  String get example {
    if (params.isEmpty) return '/$name';
    return '/$name ${params.map((p) => '<$p>').join(' ')}';
  }
}

/// Liste des commandes slash disponibles.
class SlashCommands {
  static final RegExp _argTokenizer = RegExp(
    '"([^"\\\\]*(?:\\\\.[^"\\\\]*)*)"|\'([^\'\\\\]*(?:\\\\.[^\'\\\\]*)*)\'|(\\S+)',
  );

  static const List<SlashCommand> all = [
    SlashCommand(
      name: 'download',
      description: 'Télécharger un fichier depuis une URL, ou sans argument tous les liens du dernier /links',
      usage: '/download [url] [filename]',
      params: ['url', 'filename'],
      icon: Icons.download,
    ),
    SlashCommand(
      name: 'links',
      description: 'Extraire les liens d\'une page (courante ou URL, filtrables)',
      usage: '/links [url] [all|video|videos|image|audio|document]',
      params: ['url', 'filter'],
      icon: Icons.link,
    ),
    SlashCommand(
      name: 'pdf',
      description: 'Convertir la page courante ou une URL en PDF',
      usage: '/pdf [url] [filename]',
      params: ['url', 'filename'],
      icon: Icons.picture_as_pdf,
    ),
    SlashCommand(
      name: 'summarize',
      description: 'Résumer le contenu d\'une page (courante ou URL)',
      usage: '/summarize [url]',
      params: ['url'],
      icon: Icons.summarize,
    ),
    SlashCommand(
      name: 'extract',
      description: 'Extraire le texte d\'une page ou élément (URL + sélecteur CSS)',
      usage: '/extract [url] [selector]',
      params: ['url', 'selector'],
      icon: Icons.content_paste,
    ),
    SlashCommand(
      name: 'scroll',
      description: 'Défiler la page (haut/bas, nombre de pixels)',
      usage: '/scroll [up|down] [amount]',
      params: ['direction', 'amount'],
      icon: Icons.arrow_downward,
    ),
    SlashCommand(
      name: 'open',
      description: 'Ouvrir un URL dans un nouvel onglet',
      usage: '/open <url>',
      params: ['url'],
      icon: Icons.open_in_new,
    ),
    SlashCommand(
      name: 'click',
      description: 'Cliquer sur un élément de la page (sélecteur CSS)',
      usage: '/click <selector>',
      params: ['selector'],
      icon: Icons.touch_app,
    ),
    SlashCommand(
      name: 'fill',
      description: 'Remplir un champ de formulaire (sélecteur CSS + valeur)',
      usage: '/fill <selector> <value>',
      params: ['selector', 'value'],
      icon: Icons.edit,
    ),
    SlashCommand(
      name: 'screenshot',
      description: 'Capturer la page visible en image',
      usage: '/screenshot',
      params: [],
      icon: Icons.screenshot,
    ),
    SlashCommand(
      name: 'back',
      description: 'Revenir à la page précédente',
      usage: '/back',
      params: [],
      icon: Icons.arrow_back,
    ),
    SlashCommand(
      name: 'forward',
      description: 'Aller à la page suivante',
      usage: '/forward',
      params: [],
      icon: Icons.arrow_forward,
    ),
    SlashCommand(
      name: 'forms',
      description: 'Extraire et lister les formulaires de la page courante',
      usage: '/forms [index]',
      params: ['index'],
      icon: Icons.dynamic_form,
    ),
    SlashCommand(
      name: 'tables',
      description: 'Extraire les tableaux de la page courante',
      usage: '/tables [index]',
      params: ['index'],
      icon: Icons.table_chart,
    ),
    SlashCommand(
      name: 'media',
      description: 'Extraire les médias (images, vidéos, audio) de la page',
      usage: '/media [images|videos|audio|all]',
      params: ['type'],
      icon: Icons.perm_media,
    ),
    SlashCommand(
      name: 'metadata',
      description: 'Afficher les métadonnées d\'une page (courante ou URL)',
      usage: '/metadata [url]',
      params: ['url'],
      icon: Icons.info_outline,
    ),
    SlashCommand(
      name: 'autofill',
      description: 'Remplir automatiquement un formulaire avec des données de test',
      usage: '/autofill [form_selector]',
      params: ['form_selector'],
      icon: Icons.auto_fix_high,
    ),
    SlashCommand(
      name: 'inspect',
      description: 'Inspecter un élément (sélecteur CSS) et afficher ses propriétés',
      usage: '/inspect <selector>',
      params: ['selector'],
      icon: Icons.search,
    ),
    SlashCommand(
      name: 'highlight',
      description: 'Surligner un élément sur la page (sélecteur CSS)',
      usage: '/highlight <selector>',
      params: ['selector'],
      icon: Icons.highlight,
    ),
    SlashCommand(
      name: 'waitfor',
      description: 'Attendre qu\'un élément apparaisse sur la page',
      usage: '/waitfor <selector> [timeout_ms]',
      params: ['selector', 'timeout_ms'],
      icon: Icons.hourglass_bottom,
    ),
    SlashCommand(
      name: 'export',
      description: 'Exporter les données de la page (JSON, CSV, Markdown)',
      usage: '/export [json|csv|md]',
      params: ['format'],
      icon: Icons.file_download,
    ),
    SlashCommand(
      name: 'monitor',
      description: 'Surveiller la page pour détecter des changements (prix, stock, contenu)',
      usage: '/monitor <selector> [interval_sec]',
      params: ['selector', 'interval_sec'],
      icon: Icons.monitor_heart,
    ),
    SlashCommand(
      name: 'translate',
      description: 'Traduire le contenu de la page ou un texte sélectionné',
      usage: '/translate [fr|en|es|de|it|pt|ja|zh|ar|ru|ko|nl]',
      params: ['langue_cible'],
      icon: Icons.translate,
    ),
    SlashCommand(
      name: 'searchpage',
      description: 'Rechercher un terme dans le contenu de la page courante',
      usage: '/searchpage <terme>',
      params: ['terme'],
      icon: Icons.pageview,
    ),
    SlashCommand(
      name: 'docgen',
      description: 'Générer un document riche (word, powerpoint, excel, pdf, markdown, texte) ou une image (jpg, png) à partir d\'un sujet',
      usage: '/docgen <format> <sujet> [nom_fichier]',
      params: ['format', 'sujet', 'nom_fichier'],
      icon: Icons.description,
    ),
    SlashCommand(
      name: 'scrape',
      description: 'Scraper une URL via le backend et extraire prix, liens, contenu',
      usage: '/scrape <url> [selectors_json]',
      params: ['url', 'selectors'],
      icon: Icons.web,
    ),
  ];

  /// Recherche les commandes correspondant à un préfixe.
  static List<SlashCommand> search(String prefix) {
    if (prefix.isEmpty) {
      final sorted = List<SlashCommand>.from(all)
        ..sort((a, b) => a.name.compareTo(b.name));
      return sorted;
    }
    final lower = prefix.toLowerCase().trim();
    final commandToken = lower.split(RegExp(r'\s+')).first;

    final matches = all
        .where((cmd) =>
            cmd.name.toLowerCase().startsWith(commandToken) ||
            cmd.description.toLowerCase().contains(lower))
        .toList();

    matches.sort((a, b) {
      final aStarts = a.name.toLowerCase().startsWith(commandToken);
      final bStarts = b.name.toLowerCase().startsWith(commandToken);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return a.name.compareTo(b.name);
    });

    return matches;
  }

  /// Commandes universelles (fonctionnent sur toutes les plateformes).
  static const Set<String> universalCommandNames = {'docgen', 'scrape', 'summarize', 'extract', 'links', 'metadata'};

  /// Parse une commande slash depuis le texte de l'utilisateur.
  /// Retourne null si ce n'est pas une commande slash valide.
  static ParsedSlashCommand? parse(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('/')) return null;

    final raw = trimmed.substring(1).trim();
    if (raw.isEmpty) return null;

    final parts = <String>[];
    for (final match in _argTokenizer.allMatches(raw)) {
      final quotedDouble = match.group(1);
      final quotedSingle = match.group(2);
      final unquoted = match.group(3);
      final token = quotedDouble ?? quotedSingle ?? unquoted;
      if (token == null) continue;
      // Conserver explicitement les tokens vides quotés (ex: /pdf "" mon_fichier)
      if (token.isEmpty && quotedDouble == null && quotedSingle == null) continue;
      parts.add(
        token
            .replaceAll(r'\"', '"')
            .replaceAll(r"\'", "'")
            .replaceAll(r'\\', r'\'),
      );
    }

    if (parts.isEmpty) return null;

    final cmdName = parts[0].toLowerCase();
    final command = all.where((c) => c.name == cmdName).firstOrNull;
    if (command == null) return null;

    final args = parts.sublist(1);
    return ParsedSlashCommand(command: command, args: args);
  }
}

/// Résultat du parsing d'une commande slash.
class ParsedSlashCommand {
  final SlashCommand command;
  final List<String> args;

  const ParsedSlashCommand({required this.command, required this.args});

  /// Reconstruit le texte de la commande.
  String get fullText => '/${command.name} ${args.join(' ')}'.trim();

  /// Traduit la commande en langage naturel pour affichage dans la conversation.
  String toNaturalLanguage([lang.AppLanguage language = lang.AppLanguage.fr]) {
    return lang.toNaturalLanguage(command.name, args, language);
  }
}

/// Widget de palette de commandes slash.
class SlashCommandPalette extends StatelessWidget {
  final String filter;
  final void Function(SlashCommand) onSelected;

  const SlashCommandPalette({
    super.key,
    required this.filter,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final commands = SlashCommands.search(filter);
    if (commands.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
          top: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Commandes',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: commands.length,
              itemBuilder: (context, index) {
                final cmd = commands[index];
                return InkWell(
                  onTap: () => onSelected(cmd),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(cmd.icon, size: 18, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '/${cmd.name}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                cmd.description,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          cmd.params.isEmpty ? '' : '<${cmd.params.join('> <')}>',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}