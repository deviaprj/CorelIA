import 'dart:async';
import 'package:flutter/foundation.dart';
import '../domain/app_user.dart';
import '../../../core/constants.dart';
import '../../../core/secure_storage.dart';

/// Mock repository pour tests locaux sans Firebase
/// Permet de tester l'application en mode DEMO sur Linux desktop
class MockAuthRepository {
  final SecureStorageService _storage = SecureStorageService();
  final _authStateController = StreamController<AppUser?>.broadcast();

  // Utilisateur courant simulé
  AppUser? _currentUser;

  // Base de données simulée en mémoire
  final Map<String, AppUser> _users = {};

  // Stream pour écouter les changements d'auth
  Stream<AppUser?> get authStateChanges => _authStateController.stream;

  // Utilisateur courant
  AppUser? get currentUser => _currentUser;

  /// Initialisation du mock
  Future<void> initialize() async {
    debugPrint('[MockAuth] Initialisé - mode DEMO');
    // Tenter de restaurer une session précédente
    final savedEmail = await _storage.read('demo_user_email');
    if (savedEmail != null && _users.containsKey(savedEmail)) {
      _currentUser = _users[savedEmail];
      _authStateController.add(_currentUser);
      debugPrint('[MockAuth] Session restaurée: $savedEmail');
    }
  }

  /// Inscription avec email/password
  Future<AppUser> registerWithEmail(
    String email,
    String password,
    String name,
  ) async {
    await Future.delayed(const Duration(milliseconds: 500)); // Simulation réseau

    if (_users.containsKey(email)) {
      throw Exception('Cet email est déjà utilisé');
    }

    final user = AppUser(
      uid: 'demo_${DateTime.now().millisecondsSinceEpoch}',
      email: email,
      displayName: name,
      plan: 'free',
      createdAt: DateTime.now(),
    );

    _users[email] = user;
    _currentUser = user;
    await _storage.write('demo_user_email', email);
    _authStateController.add(user);

    debugPrint('[MockAuth] Inscription réussie: ${user.email}');
    return user;
  }

  /// Connexion avec email/password
  Future<AppUser> signInWithEmail(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 300)); // Simulation réseau

    // En mode demo, on accepte n'importe quel mot de passe (≥ 6 caractères)
    if (password.length < 6) {
      throw Exception('Le mot de passe doit faire au moins 6 caractères');
    }

    // Si l'utilisateur existe, on le retourne
    if (_users.containsKey(email)) {
      _currentUser = _users[email];
    } else {
      // Création automatique pour la démo
      _currentUser = AppUser(
        uid: 'demo_${DateTime.now().millisecondsSinceEpoch}',
        email: email,
        displayName: email.split('@').first,
        plan: 'free',
        createdAt: DateTime.now(),
      );
      _users[email] = _currentUser!;
    }

    await _storage.write('demo_user_email', email);
    _authStateController.add(_currentUser);

    debugPrint('[MockAuth] Connexion réussie: ${_currentUser!.email}');
    return _currentUser!;
  }

  /// Connexion avec Google (simulée)
  Future<AppUser> signInWithGoogle() async {
    await Future.delayed(const Duration(milliseconds: 500));

    _currentUser = AppUser(
      uid: 'google_demo_${DateTime.now().millisecondsSinceEpoch}',
      email: 'demo.google@gmail.com',
      displayName: 'Demo Google User',
      plan: 'free',
      createdAt: DateTime.now(),
    );

    await _storage.write('demo_user_email', _currentUser!.email!);
    _authStateController.add(_currentUser);

    debugPrint('[MockAuth] Google Sign-In réussi');
    return _currentUser!;
  }

  /// Connexion anonyme (simulée)
  Future<AppUser> signInAnonymously() async {
    await Future.delayed(const Duration(milliseconds: 200));

    _currentUser = AppUser(
      uid: 'anon_${DateTime.now().millisecondsSinceEpoch}',
      email: null,
      displayName: 'Utilisateur Anonyme',
      plan: 'free',
      createdAt: DateTime.now(),
    );

    _authStateController.add(_currentUser);

    debugPrint('[MockAuth] Connexion anonyme réussie');
    return _currentUser!;
  }

  /// Déconnexion
  Future<void> signOut() async {
    _currentUser = null;
    await _storage.delete('demo_user_email');
    _authStateController.add(null);

    debugPrint('[MockAuth] Déconnexion');
  }

  /// Suppression du compte
  Future<void> deleteAccount() async {
    if (_currentUser?.email != null) {
      _users.remove(_currentUser!.email);
      await _storage.delete('demo_user_email');
    }
    _currentUser = null;
    _authStateController.add(null);

    debugPrint('[MockAuth] Compte supprimé');
  }

  /// Nettoyage
  void dispose() {
    _authStateController.close();
  }
}

// Instance globale pour le mode DEMO
final mockAuthRepository = MockAuthRepository();
