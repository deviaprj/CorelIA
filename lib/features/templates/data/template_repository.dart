import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/template.dart';

/// Repository local pour les templates (SharedPreferences).
///
/// En production, sera migre vers SQLite pour de meilleures performances.
class TemplateRepository {
  static const String _prefsKey = 'corely_templates';
  static const int _maxTemplates = 100;

  List<Template> _cache = [];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _cache = list
            .map((e) => Template.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('[TemplateRepo] Load error: $e');
        _cache = [];
      }
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _cache.map((t) => t.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(jsonList));
  }

  /// Tous les templates, tries par usage decroissant.
  Future<List<Template>> getAll() async {
    await _ensureLoaded();
    final list = _cache.toList();
    list.sort((a, b) {
      final scoreA = a.useCount + a.confidenceBoost;
      final scoreB = b.useCount + b.confidenceBoost;
      return scoreB.compareTo(scoreA);
    });
    return list;
  }

  /// Templates par categorie.
  Future<List<Template>> getByCategory(String category) async {
    final all = await getAll();
    return all.where((t) => t.category == category).toList();
  }

  /// Recherche par nom ou tag.
  Future<List<Template>> search(String query) async {
    final all = await getAll();
    final lower = query.toLowerCase();
    return all
        .where((t) =>
            t.name.toLowerCase().contains(lower) ||
            t.description.toLowerCase().contains(lower) ||
            t.tags.any((tag) => tag.toLowerCase().contains(lower)))
        .toList();
  }

  /// Sauvegarde un template (creation ou mise a jour).
  Future<void> save(Template template) async {
    await _ensureLoaded();
    final index = _cache.indexWhere((t) => t.id == template.id);
    if (index >= 0) {
      _cache[index] = template.copyWith(updatedAt: DateTime.now());
    } else {
      _cache.add(template);
      if (_cache.length > _maxTemplates) {
        _cache.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        _cache = _cache.take(_maxTemplates).toList();
      }
    }
    await _persist();
  }

  /// Supprime un template.
  Future<void> delete(String templateId) async {
    await _ensureLoaded();
    _cache.removeWhere((t) => t.id == templateId);
    await _persist();
  }

  /// Incremente le compteur d'utilisation.
  Future<void> recordUsage(String templateId) async {
    await _ensureLoaded();
    final index = _cache.indexWhere((t) => t.id == templateId);
    if (index >= 0) {
      _cache[index] = _cache[index].copyWith(
        useCount: _cache[index].useCount + 1,
        confidenceBoost: _cache[index].confidenceBoost + 0.1,
        lastUsedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _persist();
    }
  }
}

/// Singleton du repository templates.
final templateRepository = TemplateRepository();
