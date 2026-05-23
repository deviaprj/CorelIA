import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service de profil utilisateur pour la personnalisation progressive.
///
/// Principe : on collecte des donnees de maniere progressive pour
/// personnaliser l'experience sans etre intrusif.
///
/// Jour 1 : anonyme
/// Jour 3 : prenom demande (apres avoir gagne la confiance)
/// Jour 7 : sujets favoris extraits de l'historique de conversation
/// Jour 14 : affichage personnalise "Corely sait que tu aimes..."
class UserProfileService {
  static const String _prefsKeyName = 'user_profile_name';
  static const String _prefsKeyInterests = 'user_profile_interests';
  static const String _prefsKeyFirstSeen = 'user_profile_first_seen';
  static const String _prefsKeyNameAsked = 'user_profile_name_asked';
  static const int _nameAskThresholdDays = 3;
  static const int _interestsThresholdDays = 7;

  /// Retourne le prenom s'il a ete fourni.
  Future<String?> getName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyName);
  }

  /// Enregistre le prenom de l'utilisateur.
  Future<void> setName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyName, name.trim());
    debugPrint('[UserProfile] Prenom enregistre : $name');
  }

  /// Retourne la liste des sujets favoris.
  Future<List<String>> getInterests() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKeyInterests);
    return raw ?? const [];
  }

  /// Ajoute un sujet favori.
  Future<void> addInterest(String interest) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_prefsKeyInterests) ?? [];
    if (!current.contains(interest)) {
      current.add(interest);
      await prefs.setStringList(_prefsKeyInterests, current);
    }
  }

  /// Extrait des sujets potentiels a partir du texte d'une conversation.
  /// Appeler apres chaque message assistant pour enrichir le profil.
  Future<void> extractInterestsFromText(String text) async {
    final lower = text.toLowerCase();
    final keywords = <String, String>{
      'football': 'football',
      'foot': 'football',
      'basket': 'basketball',
      'tennis': 'tennis',
      'sport': 'sport',
      'tech': 'technologie',
      'technologie': 'technologie',
      'programmation': 'programmation',
      'code': 'programmation',
      'flutter': 'programmation',
      'dart': 'programmation',
      'politique': 'politique',
      'actualite': 'actualites',
      'news': 'actualites',
      'voyage': 'voyages',
      'cuisine': 'cuisine',
      'recette': 'cuisine',
      'musique': 'musique',
      'film': 'cinema',
      'cinema': 'cinema',
      'serie': 'cinema',
      'jeu video': 'gaming',
      'gaming': 'gaming',
      'sante': 'sante',
      'medecine': 'sante',
      'finance': 'finance',
      'crypto': 'finance',
      'bitcoin': 'finance',
      'investissement': 'finance',
    };

    for (final entry in keywords.entries) {
      if (lower.contains(entry.key)) {
        await addInterest(entry.value);
      }
    }
  }

  /// Indique si on doit demander le prenom (apres 3 jours).
  Future<bool> shouldAskForName() async {
    final prefs = await SharedPreferences.getInstance();
    final nameAsked = prefs.getBool(_prefsKeyNameAsked) ?? false;
    if (nameAsked) return false;

    final firstSeen = prefs.getString(_prefsKeyFirstSeen);
    if (firstSeen == null) {
      await prefs.setString(_prefsKeyFirstSeen, DateTime.now().toIso8601String());
      return false;
    }

    final daysSinceFirst = DateTime.now().difference(DateTime.parse(firstSeen)).inDays;
    return daysSinceFirst >= _nameAskThresholdDays;
  }

  /// Marque le prenom comme demande.
  Future<void> markNameAsAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyNameAsked, true);
  }

  /// Indique si les sujets favoris sont prets a etre exploites (apres 7 jours).
  Future<bool> hasEnoughDataForPersonalization() async {
    final prefs = await SharedPreferences.getInstance();
    final firstSeen = prefs.getString(_prefsKeyFirstSeen);
    if (firstSeen == null) return false;

    final days = DateTime.now().difference(DateTime.parse(firstSeen)).inDays;
    return days >= _interestsThresholdDays;
  }

  /// Message de bienvenue personnalise.
  Future<String> getPersonalizedGreeting() async {
    final name = await getName();
    final interests = await getInterests();

    if (name != null && interests.isNotEmpty) {
      final interestList = interests.take(2).join(' et ');
      return 'Corely sait que tu aimes $interestList, $name. Pose-moi ce que tu veux !';
    }

    if (name != null) {
      return 'Bonjour $name ! Pret a discuter ?';
    }

    return 'Bonjour ! Pose-moi ce que tu veux.';
  }

  /// Reset complet (debug).
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyName);
    await prefs.remove(_prefsKeyInterests);
    await prefs.remove(_prefsKeyFirstSeen);
    await prefs.remove(_prefsKeyNameAsked);
  }
}
