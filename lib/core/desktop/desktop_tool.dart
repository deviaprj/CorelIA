/// Resultat d'une execution d'outil desktop.
class DesktopToolResult {
  final bool success;
  final String? data; // Sortie principale (texte, JSON, etc.)
  final String? error;
  final Map<String, dynamic>? metadata;

  const DesktopToolResult({
    required this.success,
    this.data,
    this.error,
    this.metadata,
  });

  factory DesktopToolResult.ok(String data, {Map<String, dynamic>? metadata}) =>
      DesktopToolResult(success: true, data: data, metadata: metadata);

  factory DesktopToolResult.fail(String error) =>
      DesktopToolResult(success: false, error: error);

  Map<String, dynamic> toJson() => {
        'success': success,
        if (data != null) 'data': data,
        if (error != null) 'error': error,
        if (metadata != null) 'metadata': metadata,
      };
}

/// Interface abstraite pour un outil desktop (email, fichiers, navigateur, etc.).
///
/// Chaque outil implemente cette interface. Les outils sont enregistres dans
/// le [DesktopToolRegistry] et appeles via le slash command `/tool <id> <params>`
/// ou par l'AgentRunner.
abstract class DesktopTool {
  /// Identifiant unique (ex: "email", "filesystem", "browser").
  String get id;

  /// Nom lisible (ex: "Email", "Fichiers", "Navigateur").
  String get name;

  /// Description pour le LLM (utilisee dans le function calling).
  String get description;

  /// Schema JSON des parametres acceptes (format OpenAI function calling).
  Map<String, dynamic> get parametersSchema;

  /// Verifie si l'outil est disponible sur cette machine.
  Future<bool> get isAvailable;

  /// Execute l'outil avec les parametres donnes.
  Future<DesktopToolResult> execute(Map<String, dynamic> params);

  /// Categorie de l'outil (pour regroupement UI).
  String get category;
}
