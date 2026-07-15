/// Modele de template reutilisable.
///
/// Les templates permettent de sauvegarder et reutiliser des patterns
/// de prompts, workflows, et formats de documents.
class Template {
  final String id;
  final String name;
  final String description;
  final String category; // email, report, presentation, search, agent_plan
  final String content; // Corps du template avec ${variables}
  final List<String> variables; // Variables extraites du contenu
  final List<String> tags;
  final int useCount;
  final double confidenceBoost; // Boost appris des utilisations reussies
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;

  const Template({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.content,
    this.variables = const [],
    this.tags = const [],
    this.useCount = 0,
    this.confidenceBoost = 0.0,
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
  });

  /// Extrait les variables ${...} du contenu.
  static List<String> extractVariables(String content) {
    final regex = RegExp(r'\$\{(\w+)\}');
    return regex.allMatches(content).map((m) => m.group(1)!).toSet().toList();
  }

  /// Resout les variables avec les valeurs fournies.
  String resolve(Map<String, String> values) {
    var result = content;
    for (final entry in values.entries) {
      result = result.replaceAll('\${${entry.key}}', entry.value);
    }
    return result;
  }

  /// Cree un nouveau template avec les champs obligatoires.
  factory Template.create({
    required String name,
    required String description,
    required String category,
    required String content,
    List<String> tags = const [],
  }) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now();
    return Template(
      id: id,
      name: name,
      description: description,
      category: category,
      content: content,
      variables: extractVariables(content),
      tags: tags,
      createdAt: now,
      updatedAt: now,
    );
  }

  Template copyWith({
    String? name,
    String? description,
    String? category,
    String? content,
    List<String>? variables,
    List<String>? tags,
    int? useCount,
    double? confidenceBoost,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
  }) =>
      Template(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        category: category ?? this.category,
        content: content ?? this.content,
        variables: variables ?? this.variables,
        tags: tags ?? this.tags,
        useCount: useCount ?? this.useCount,
        confidenceBoost: confidenceBoost ?? this.confidenceBoost,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category,
        'content': content,
        'variables': variables,
        'tags': tags,
        'useCount': useCount,
        'confidenceBoost': confidenceBoost,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastUsedAt': lastUsedAt?.toIso8601String(),
      };

  factory Template.fromJson(Map<String, dynamic> json) => Template(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        category: json['category'] as String? ?? 'general',
        content: json['content'] as String,
        variables: (json['variables'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        tags:
            (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
                [],
        useCount: json['useCount'] as int? ?? 0,
        confidenceBoost: (json['confidenceBoost'] as num?)?.toDouble() ?? 0.0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        lastUsedAt: json['lastUsedAt'] != null
            ? DateTime.tryParse(json['lastUsedAt'] as String)
            : null,
      );

  /// Categories disponibles.
  static const List<String> categories = [
    'email',
    'report',
    'presentation',
    'search',
    'agent_plan',
    'general',
  ];

  /// Label lisible pour une categorie.
  static String categoryLabel(String category) => switch (category) {
        'email' => 'Email',
        'report' => 'Rapport',
        'presentation' => 'Presentation',
        'search' => 'Recherche',
        'agent_plan' => 'Plan agent',
        _ => 'General',
      };
}
