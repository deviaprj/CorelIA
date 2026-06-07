import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/constants.dart';

/// Résultat d'exécution d'un script généré par IA.
class ScriptExecutionResult {
  final bool success;
  final dynamic data;
  final String? error;
  final String? script;

  const ScriptExecutionResult({
    required this.success,
    this.data,
    this.error,
    this.script,
  });

  factory ScriptExecutionResult.fromJson(Map<String, dynamic> json) {
    return ScriptExecutionResult(
      success: json['success'] as bool? ?? false,
      data: json['data'],
      error: json['error'] as String?,
      script: json['script'] as String?,
    );
  }

  String _formatDataBlock() {
    if (data == null) {
      return '✅ Script exécuté avec succès, mais aucune donnée retournée.';
    }
    return '✅ **Résultat**:\n\n```json\n${const JsonEncoder.withIndent('  ').convert(data)}\n```';
  }

  String _formatScriptBlock() {
    if (script == null || script!.trim().isEmpty) return '';
    return '\n**Script généré**:\n\n```python\n${script!.trim()}\n```\n';
  }

  /// Formatte le résultat en markdown pour affichage dans le chat.
  String formatMarkdown({
    required String title,
    String? subtitle,
  }) {
    final buf = StringBuffer();
    buf.writeln('🔬 **$title**');
    buf.writeln();
    if (subtitle != null && subtitle.isNotEmpty) {
      buf.writeln(subtitle);
      buf.writeln();
    }

    if (!success) {
      buf.writeln('❌ **Erreur**: ${error ?? "Échec inconnu"}');
      final scriptBlock = _formatScriptBlock();
      if (scriptBlock.isNotEmpty) buf.write(scriptBlock);
      return buf.toString();
    }

    buf.writeln(_formatDataBlock());
    buf.write(_formatScriptBlock());
    return buf.toString();
  }

  String formatScrapeMarkdown(String url, String instruction) {
    return formatMarkdown(
      title: 'Script scraping',
      subtitle: '**URL**: $url\n**Instruction**: $instruction',
    );
  }

  String formatExecMarkdown(String instruction) {
    return formatMarkdown(
      title: 'Script exécuté',
      subtitle: '**Instruction**: $instruction',
    );
  }

  String formatApiFetchMarkdown(String url, String instruction) {
    return formatMarkdown(
      title: 'API fetch',
      subtitle: '**URL**: $url\n**Instruction**: $instruction',
    );
  }
}

/// Client pour le service de scripts à la volée.
class ScriptExecutionService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 45),
  ));

  static Future<ScriptExecutionResult> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    final backendUrl = AppConstants.backendBaseUrl;
    if (backendUrl.isEmpty) {
      return const ScriptExecutionResult(
        success: false,
        error: 'Backend indisponible (URL non configurée)',
      );
    }

    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '$backendUrl$path',
        data: data,
      );

      if (resp.data == null) {
        return const ScriptExecutionResult(
          success: false,
          error: 'Réponse vide du backend',
        );
      }

      return ScriptExecutionResult.fromJson(resp.data!);
    } on DioException catch (e) {
      debugPrint('[ScriptExecution] Dio error: $e');
      return ScriptExecutionResult(
        success: false,
        error: 'Erreur réseau: ${e.message}',
      );
    } catch (e) {
      debugPrint('[ScriptExecution] Error: $e');
      return ScriptExecutionResult(
        success: false,
        error: 'Erreur: $e',
      );
    }
  }

  static Future<ScriptExecutionResult> scrapeWithScript(
    String url,
    String instruction,
  ) {
    return _post('/script/scrape', {
      'url': url,
      'instruction': instruction,
    });
  }

  static Future<ScriptExecutionResult> execWithInstruction(
    String instruction,
  ) {
    return _post('/script/exec', {'instruction': instruction});
  }

  static Future<ScriptExecutionResult> apiFetchWithScript(
    String url,
    String instruction,
  ) {
    return _post('/script/api-fetch', {
      'url': url,
      'instruction': instruction,
    });
  }
}
