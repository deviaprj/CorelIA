import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/app_user.dart';
import 'auth_repository.dart';

/// Repository d'authentification simulé — mode démo (sans Firebase) et tests.
///
/// Il reproduit les méthodes de [AuthRepository] sans réseau. L'e-mail de
/// vérification est simulé et le compte est considéré vérifié immédiatement :
/// sans serveur, il n'y a aucune boîte mail à consulter.
class MockAuthRepository {
  static const _emailKey = 'demo_user_email';

  final _authStateController = StreamController<AppUser?>.broadcast();
  final Map<String, AppUser> _users = {};

  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;

  bool get isEmailVerified => true;

  /// Réémet la valeur courante à chaque nouvel abonné.
  Stream<AppUser?> get authStateChanges async* {
    yield _currentUser;
    yield* _authStateController.stream;
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString(_emailKey);
    if (savedEmail != null && _users.containsKey(savedEmail)) {
      _currentUser = _users[savedEmail];
      _authStateController.add(_currentUser);
    }
    debugPrint('[MockAuth] initialisé (mode démo)');
  }

  Future<void> registerWithEmail(RegistrationData data) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (_users.containsKey(data.email)) {
      throw Exception('Cet e-mail est déjà utilisé');
    }
    final user = AppUser(
      uid: 'demo_${DateTime.now().millisecondsSinceEpoch}',
      email: data.email,
      displayName: data.fullName,
      firstName: data.firstName,
      lastName: data.lastName,
      birthDate: data.birthDate,
      createdAt: DateTime.now(),
    );
    _users[data.email] = user;
    await _setCurrent(user);
  }

  Future<void> signInWithEmail(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (password.length < 6) {
      throw Exception('Le mot de passe doit faire au moins 6 caractères');
    }
    final user = _users[email] ??
        AppUser(
          uid: 'demo_${DateTime.now().millisecondsSinceEpoch}',
          email: email,
          displayName: email.split('@').first,
          createdAt: DateTime.now(),
        );
    _users[email] = user;
    await _setCurrent(user);
  }

  Future<void> signInWithGoogle() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final user = AppUser(
      uid: 'google_demo_${DateTime.now().millisecondsSinceEpoch}',
      email: 'demo.google@gmail.com',
      displayName: 'Utilisateur Google démo',
      firstName: 'Utilisateur',
      lastName: 'Google démo',
      createdAt: DateTime.now(),
    );
    await _setCurrent(user);
  }

  Future<void> signInAnonymously() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final user = AppUser(
      uid: 'anon_${DateTime.now().millisecondsSinceEpoch}',
      displayName: 'Invité',
      createdAt: DateTime.now(),
    );
    _currentUser = user;
    _authStateController.add(user);
  }

  Future<void> sendEmailVerification() async {
    debugPrint('[MockAuth] e-mail de vérification simulé (mode démo)');
  }

  Future<void> reloadCurrentUser() async {}

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    _currentUser = null;
    _authStateController.add(null);
  }

  Future<void> deleteAccount() async {
    final email = _currentUser?.email;
    if (email != null) _users.remove(email);
    await signOut();
  }

  Future<void> _setCurrent(AppUser user) async {
    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    if (user.email != null) await prefs.setString(_emailKey, user.email!);
    _authStateController.add(user);
  }

  void dispose() => _authStateController.close();
}

/// Instance globale pour le mode démo.
final mockAuthRepository = MockAuthRepository();
